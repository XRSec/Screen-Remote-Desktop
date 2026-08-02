import AppKit
import Foundation

enum DeviceAppManagementError: LocalizedError {
    case adbNotFound
    case helperNotFound
    case noConnection
    case unauthorized
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .adbNotFound: String.localizedKey("appsManageADBNotFound")
        case .helperNotFound: String.localizedKey("appsManageHelperNotFound")
        case .noConnection: String.localizedKey("appsManageNoConnection")
        case .unauthorized: String.localizedKey("appsManageUnauthorized")
        case .commandFailed(let detail):
            detail.isEmpty
                ? String.localizedKey("appsManageCommandFailed")
                : String(format: String.localizedKey("appsManageCommandFailedWithDetails"), detail)
        }
    }
}

enum DeviceAppADB {
    private static let helperMainClass = "dadb.helper.AppIconExportMain"

    static func resolveSerial(for device: Device, configuredADBPath: String) async throws -> String {
        let adbPath = executablePath(configuredADBPath, kind: .adb)
        guard FileManager.default.isExecutableFile(atPath: adbPath) else {
            throw DeviceAppManagementError.adbNotFound
        }

        let devicesOutput = try await runADB(
            configuredADBPath: adbPath,
            arguments: ["devices"],
            timeout: 8
        )
        guard devicesOutput.succeeded else {
            throw DeviceAppManagementError.commandFailed(devicesOutput.failureDetail)
        }
        let states = parseDeviceStates(devicesOutput.standardOutput)
        let candidates = device.connections.sorted { $0.priority < $1.priority }

        for connection in candidates {
            let serial = serial(for: connection)
            guard !serial.isEmpty, let state = matchingState(for: serial, in: states) else { continue }
            if state == "device" { return serial }
            if state == "unauthorized" { throw DeviceAppManagementError.unauthorized }
        }

        throw DeviceAppManagementError.noConnection
    }

    static func listApps(
        serial: String,
        configuredADBPath: String
    ) async throws -> [ManagedAndroidApp] {
        let helper = try await preparedHelper(
            serial: serial,
            configuredADBPath: configuredADBPath
        )

        let pageSize = 250
        var offset = 0
        var result: [ManagedAndroidApp] = []
        while true {
            let output = try await helper.invoke(
                mainClass: helperMainClass,
                arguments: ["list", String(offset), String(pageSize), "1"],
                timeout: 40
            )
            let page = try parseAppList(output.standardOutput)
            result.append(contentsOf: page)
            guard page.count == pageSize else { break }
            offset += page.count
        }
        return result.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func loadAppIcons(
        packageNames: [String],
        serial: String,
        configuredADBPath: String
    ) async throws -> [RemoteAppIcon] {
        guard !packageNames.isEmpty else { return [] }
        let request = packageNames.joined(separator: "\n")
        let payload = Data(request.utf8).base64EncodedString()
        let helper = try await preparedHelper(
            serial: serial,
            configuredADBPath: configuredADBPath
        )
        let output = try await helper.invoke(
            mainClass: helperMainClass,
            arguments: ["icons", payload],
            timeout: 90
        )
        return try await parseIconBatch(output.standardOutput)
    }

    private static func preparedHelper(
        serial: String,
        configuredADBPath: String
    ) async throws -> PreparedDADBHelper {
        do {
            return try await DADBHelperRuntime.prepare(
                serial: serial,
                configuredADBPath: configuredADBPath
            )
        } catch let error as DADBHelperRuntimeError {
            switch error {
            case .adbNotFound:
                throw DeviceAppManagementError.adbNotFound
            case .helperNotFound:
                throw DeviceAppManagementError.helperNotFound
            case .commandFailed(let detail):
                throw DeviceAppManagementError.commandFailed(detail)
            }
        }
    }

    private static func parseAppList(_ output: String) throws -> [ManagedAndroidApp] {
        try output.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 7,
                  let labelData = Data(base64Encoded: fields[1]),
                  let label = String(data: labelData, encoding: .utf8),
                  let versionCode = Int64(fields[5]),
                  let lastUpdateTime = Int64(fields[6]) else {
                throw DeviceAppManagementError.commandFailed("DADB helper returned an invalid app list record.")
            }
            return ManagedAndroidApp(
                packageName: fields[0],
                name: label.isEmpty ? fields[0] : label,
                isEnabled: fields[2] == "1",
                isSystem: fields[3] == "1",
                versionCode: versionCode,
                lastUpdateTime: lastUpdateTime,
                iconFileName: nil
            )
        }
    }

    private static func parseIconBatch(_ output: String) async throws -> [RemoteAppIcon] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3, lines[0] == "BATCH" else {
            throw DeviceAppManagementError.commandFailed("DADB helper returned an invalid icon batch header.")
        }
        guard lines[1] != "-", lines[2] != "-" else { return [] }
        guard let manifestData = Data(base64Encoded: lines[1]),
              let manifest = String(data: manifestData, encoding: .utf8),
              let zipData = Data(base64Encoded: lines[2]) else {
            throw DeviceAppManagementError.commandFailed("DADB helper returned invalid icon batch data.")
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-remote-icons-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = temporaryDirectory.appendingPathComponent("icons.zip")
        let extractedURL = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(at: extractedURL, withIntermediateDirectories: true)
        try zipData.write(to: archiveURL, options: .atomic)
        let extraction = try await run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractedURL.path],
            environment: [:],
            timeout: 20
        )
        guard extraction.succeeded else {
            throw DeviceAppManagementError.commandFailed(extraction.failureDetail)
        }

        return try manifest.split(whereSeparator: \.isNewline).map { rawLine in
            let fields = String(rawLine).components(separatedBy: "\t")
            guard fields.count >= 6,
                  !fields[5].contains("/"),
                  !fields[5].contains(".."),
                  let labelData = Data(base64Encoded: fields[1]),
                  let label = String(data: labelData, encoding: .utf8),
                  let versionCode = Int64(fields[2]),
                  let lastUpdateTime = Int64(fields[4]) else {
                throw DeviceAppManagementError.commandFailed("DADB helper returned an invalid icon manifest record.")
            }
            let imageData = try Data(contentsOf: extractedURL.appendingPathComponent(fields[5]))
            guard NSImage(data: imageData) != nil else {
                throw DeviceAppManagementError.commandFailed("DADB helper returned invalid app icon image data.")
            }
            return RemoteAppIcon(
                packageName: fields[0],
                name: label,
                versionCode: versionCode,
                lastUpdateTime: lastUpdateTime,
                imageData: imageData
            )
        }
    }

    static func runADB(
        configuredADBPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> DeviceAppProcessOutput {
        let adbPath = executablePath(configuredADBPath, kind: .adb)
        guard FileManager.default.isExecutableFile(atPath: adbPath) else {
            throw DeviceAppManagementError.adbNotFound
        }
        return try await run(executable: adbPath, arguments: arguments, environment: [:], timeout: timeout)
    }

    static func firstValue(named key: String, in output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("\(key)=") })?
            .dropFirst(key.count + 1)
            .description
    }

    static func packageValue(named key: String, in output: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        guard let expression = try? NSRegularExpression(
            pattern: "(?:^|\\s)\(escapedKey)=([^\\s]+)",
            options: [.anchorsMatchLines]
        ) else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = expression.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        let value = String(output[valueRange])
        return value == "null" ? nil : value
    }

    private static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> DeviceAppProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                var processEnvironment = ProcessInfo.processInfo.environment
                environment.forEach { processEnvironment[$0.key] = $0.value }
                process.environment = processEnvironment

                do {
                    try process.run()
                    let lock = NSLock()
                    var timedOut = false
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard process.isRunning else { return }
                        timedOut = true
                        process.terminate()
                    }
                    let group = DispatchGroup()
                    var stdout = Data()
                    var stderr = Data()
                    group.enter()
                    DispatchQueue.global().async {
                        stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    process.waitUntilExit()
                    group.wait()
                    lock.lock()
                    let didTimeOut = timedOut
                    lock.unlock()
                    continuation.resume(returning: DeviceAppProcessOutput(
                        status: process.terminationStatus,
                        standardOutput: String(decoding: stdout, as: UTF8.self),
                        standardError: String(decoding: stderr, as: UTF8.self),
                        timedOut: didTimeOut
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func parseDeviceStates(_ output: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> (String, String)? in
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count >= 2 else { return nil }
                return (normalize(fields[0]), fields[1].lowercased())
            })
    }

    private static func matchingState(for serial: String, in states: [String: String]) -> String? {
        states[normalize(serial)]
    }

    private static func serial(for connection: DeviceConnection) -> String {
        switch connection.transport {
        case .usb:
            return connection.serial.trimmingCharacters(in: .whitespacesAndNewlines)
        case .tcp:
            let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return "" }
            if host.hasPrefix("[") || host.filter({ $0 == ":" }).count <= 1 {
                return "\(host):\(connection.port)"
            }
            return "[\(host)]:\(connection.port)"
        case .mdns:
            return connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func normalize(_ value: String) -> String {
        sanitizedSerial(value)
            .lowercased()
    }

    private static func sanitizedSerial(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".:", with: ":")
    }

    private static func executablePath(_ configured: String, kind: ToolDownloadKind) -> String {
        FileManager.default.isExecutableFile(atPath: configured)
            ? configured
            : (ToolLocator.find(kind) ?? configured)
    }

}
