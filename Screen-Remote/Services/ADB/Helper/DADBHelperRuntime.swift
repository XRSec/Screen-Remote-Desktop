import Foundation

struct DADBHelperCommandOutput {
    let status: Int32
    let standardOutput: String
    let standardError: String
    let timedOut: Bool

    var succeeded: Bool { status == 0 && !timedOut }

    var englishFailureDetail: String {
        if timedOut { return "ADB command timed out." }
        let error = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty { return error }
        let output = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "ADB command failed with status \(status)." : output
    }
}

enum DADBHelperRuntimeError: Error {
    case adbNotFound
    case helperNotFound
    case commandFailed(String)

    var englishDiagnostic: String {
        switch self {
        case .adbNotFound:
            return "ADB executable was not found."
        case .helperNotFound:
            return "Bundled dadb helper was not found."
        case .commandFailed(let detail):
            return detail.isEmpty ? "DADB helper command failed." : detail
        }
    }
}

struct PreparedDADBHelper {
    let serial: String
    let configuredADBPath: String

    func invoke(
        mainClass: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> DADBHelperCommandOutput {
        let command = ([
            "CLASSPATH=\(DADBHelperRuntime.shellQuote(DADBHelperRuntime.remotePath))",
            "exec",
            "app_process",
            "/",
            mainClass
        ] + arguments.map(DADBHelperRuntime.shellQuote))
            .joined(separator: " ")
        let output = try await DADBHelperRuntime.runADB(
            configuredADBPath: configuredADBPath,
            arguments: ["-s", serial, "shell", command],
            timeout: timeout
        )
        guard output.succeeded else {
            throw DADBHelperRuntimeError.commandFailed(output.englishFailureDetail)
        }
        return output
    }
}

enum DADBHelperRuntime {
    static let version = "1.6.0"
    static let remotePath = "/data/local/tmp/dadb-helper.jar"
    private static let versionMainClass = "dadb.helper.HelperVersionMain"

    static func prepare(
        serial: String,
        configuredADBPath: String
    ) async throws -> PreparedDADBHelper {
        let helperURL = try bundledHelperURL()
        let versionCommand = "CLASSPATH=\(shellQuote(remotePath)) exec app_process / \(versionMainClass) \(shellQuote(version))"
        let guardedCommand = "if [ ! -f \(shellQuote(remotePath)) ]; then echo DADB_HELPER_MISSING; else \(versionCommand); fi"

        let first = try await runADB(
            configuredADBPath: configuredADBPath,
            arguments: ["-s", serial, "shell", guardedCommand],
            timeout: 15
        )
        if first.succeeded, first.standardOutput.firstNonemptyLine == "DADB_HELPER_READY" {
            return PreparedDADBHelper(serial: serial, configuredADBPath: configuredADBPath)
        }

        let push = try await runADB(
            configuredADBPath: configuredADBPath,
            arguments: ["-s", serial, "push", helperURL.path, remotePath],
            timeout: 45
        )
        guard push.succeeded else {
            throw DADBHelperRuntimeError.commandFailed(push.englishFailureDetail)
        }

        let retry = try await runADB(
            configuredADBPath: configuredADBPath,
            arguments: ["-s", serial, "shell", guardedCommand],
            timeout: 15
        )
        guard retry.succeeded,
              retry.standardOutput.firstNonemptyLine == "DADB_HELPER_READY" else {
            throw DADBHelperRuntimeError.commandFailed(retry.englishFailureDetail)
        }
        return PreparedDADBHelper(serial: serial, configuredADBPath: configuredADBPath)
    }

    static func runADB(
        configuredADBPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> DADBHelperCommandOutput {
        let adbPath = FileManager.default.isExecutableFile(atPath: configuredADBPath)
            ? configuredADBPath
            : (ToolLocator.find(.adb) ?? configuredADBPath)
        guard FileManager.default.isExecutableFile(atPath: adbPath) else {
            throw DADBHelperRuntimeError.adbNotFound
        }
        return try await run(
            executable: adbPath,
            arguments: arguments,
            timeout: timeout
        )
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func bundledHelperURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "dadb-helper", withExtension: "jar") else {
            throw DADBHelperRuntimeError.helperNotFound
        }
        return url
    }

    private static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> DADBHelperCommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

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
                    continuation.resume(returning: DADBHelperCommandOutput(
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
}

private extension String {
    var firstNonemptyLine: String? {
        split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
}
