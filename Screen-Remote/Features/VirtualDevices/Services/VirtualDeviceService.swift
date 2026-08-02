import AppKit
import Foundation
import SwiftUI

final class VirtualDeviceService {
    private var emulatorProcesses: [String: Process] = [:]
    private var cachedAVDs: [String: [AndroidVirtualDevice]] = [:]

    func listImages(_ configuration: VirtualDeviceConfiguration) async throws -> [AndroidSystemImage] {
        if let cli = resolveCLI(configuration) {
            let output = try await runCLI(
                cli,
                ["sdk", "list", "system-images*", "--all"],
                configuration: configuration,
                timeout: 25
            )
            let images = parseCLIImages(output.standardOutput)
            if output.succeeded || !images.isEmpty { return images }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to list system images", output) }
        }
        let installation = try resolve(configuration)
        let output = try await AndroidCommandRunner.run(
            executable: installation.sdkmanager,
            arguments: ["--list", "--sdk_root=\(sdkRoot(configuration).path)"],
            sdkRoot: sdkRoot(configuration),
            timeout: 40
        )
        let images = parseImages(output.standardOutput)
        guard output.succeeded || !images.isEmpty else {
            throw commandError("virtualDeviceReadSystemImagesFailed", output)
        }
        return images
    }

    func listAVDs(
        _ configuration: VirtualDeviceConfiguration,
        forceRefresh: Bool = false
    ) async throws -> [AndroidVirtualDevice] {
        let cacheKey = avdCacheKey(configuration)
        if !forceRefresh, let cached = cachedAVDs[cacheKey] {
            return cached
        }

        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(
                cli, ["emulator", "list", "--long"], configuration: configuration, timeout: 15
            )
            if result.succeeded {
                let devices = parseCLIAVDs(result.standardOutput, avdHome: avdHome(configuration))
                cachedAVDs[cacheKey] = devices
                return devices
            }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to list virtual devices", result) }
        }
        let installation = try resolve(configuration)
        let result = try await AndroidCommandRunner.run(
            executable: installation.avdmanager, arguments: ["list", "avd"],
            sdkRoot: sdkRoot(configuration), avdHome: avdHome(configuration), timeout: 15
        )
        var parsedDevices = parseAVDs(result.standardOutput)
        let running = try await runningAVDs(installation: installation, configuration: configuration)
        for index in parsedDevices.indices { parsedDevices[index].serial = running[parsedDevices[index].name] }
        cachedAVDs[cacheKey] = parsedDevices
        return parsedDevices
    }

    func listHardwareProfiles(_ configuration: VirtualDeviceConfiguration) async throws -> [AndroidHardwareProfile] {
        if let installation = AndroidSDKLocator.locate(
            preferredRoot: configuration.sdkRoot,
            preferredTools: configuration.toolsPath
        ) {
            let result = try await AndroidCommandRunner.run(
                executable: installation.avdmanager,
                arguments: ["list", "device"],
                sdkRoot: sdkRoot(configuration),
                timeout: 15
            )
            let profiles = parseProfiles(result.standardOutput)
            if result.succeeded, !profiles.isEmpty { return profiles }
        }
        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(
                cli,
                ["emulator", "create", "--list-profiles"],
                configuration: configuration,
                timeout: 15
            )
            if result.succeeded {
                return result.standardOutput.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { AndroidHardwareProfile(id: $0, name: $0.replacingOccurrences(of: "_", with: " ").capitalized) }
            }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to list hardware profiles", result) }
        }
        throw VirtualDeviceError.message(String.localizedKey("virtualDeviceReadHardwareProfilesFailed"))
    }

    func listSkins(
        _ configuration: VirtualDeviceConfiguration,
        customDirectories: [URL] = []
    ) -> [AndroidSkin] {
        let builtInRoot = skinsRoot(configuration)
        let builtIn = skinDirectories(in: builtInRoot).compactMap {
            parseSkin(at: $0, isCustom: false)
        }
        let custom = customDirectories.compactMap { parseSkin(at: $0, isCustom: true) }
        var seen = Set<String>()
        return (custom + builtIn)
            .filter { seen.insert($0.path).inserted }
            .sorted {
                if $0.formFactor != $1.formFactor { return $0.formFactor.rawValue < $1.formFactor.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    func installImage(_ id: String, configuration: VirtualDeviceConfiguration) async throws {
        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(
                cli, ["sdk", "install", cliPackageName(id)], configuration: configuration
            )
            if result.succeeded { return }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to install system image", result) }
        }
        let installation = try resolve(configuration)
        let result = try await AndroidCommandRunner.run(
            executable: installation.sdkmanager,
            arguments: ["--sdk_root=\(sdkRoot(configuration).path)", "--install", legacyPackageName(id)],
            sdkRoot: sdkRoot(configuration), input: String(repeating: "y\n", count: 10)
        )
        guard result.succeeded else { throw commandError("virtualDeviceInstallSystemImageFailed", result) }
    }

    func uninstallImage(_ id: String, configuration: VirtualDeviceConfiguration) async throws {
        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(
                cli, ["sdk", "remove", cliPackageName(id)], configuration: configuration
            )
            if result.succeeded { return }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to remove system image", result) }
        }
        let installation = try resolve(configuration)
        let result = try await AndroidCommandRunner.run(
            executable: installation.sdkmanager,
            arguments: ["--sdk_root=\(sdkRoot(configuration).path)", "--uninstall", legacyPackageName(id)],
            sdkRoot: sdkRoot(configuration)
        )
        guard result.succeeded else { throw commandError("virtualDeviceUninstallSystemImageFailed", result) }
    }

    func createAVD(
        name: String,
        image: String,
        profile: String?,
        options: VirtualDeviceOptions,
        configuration: VirtualDeviceConfiguration
    ) async throws {
        let installation = try resolve(configuration)
        var arguments = ["create", "avd", "--name", name, "--package", image, "--force"]
        if let profile, !profile.isEmpty { arguments += ["--device", profile] }
        if options.sdCardMB > 0 { arguments += ["-c", "\(options.sdCardMB)M"] }
        if !configuration.avdHome.isEmpty {
            let safeName = name.replacingOccurrences(of: " ", with: "_")
            arguments += ["--path", URL(fileURLWithPath: configuration.avdHome)
                .appendingPathComponent("\(safeName).avd").path]
        }
        let result = try await AndroidCommandRunner.run(
            executable: installation.avdmanager, arguments: arguments,
            sdkRoot: sdkRoot(configuration), avdHome: avdHome(configuration), input: "no\n"
        )
        guard result.succeeded else { throw commandError("virtualDeviceCreateFailed", result) }
        let device = AndroidVirtualDevice(
            name: name,
            device: profile ?? "",
            path: avdDirectory(name: name, configuration: configuration).path,
            target: image,
            serial: nil
        )
        try updateAVD(device, options: options, configuration: configuration)
    }

    func updateAVD(
        _ device: AndroidVirtualDevice,
        options: VirtualDeviceOptions,
        configuration: VirtualDeviceConfiguration
    ) throws {
        let configURL = avdConfigURL(device: device, configuration: configuration)
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw VirtualDeviceError.message(String(format: String.localizedKey("virtualDeviceConfigNotFound"), configURL.path))
        }
        var values = parseINI(try String(contentsOf: configURL, encoding: .utf8))
        setINI(&values, "hw.ramSize", "\(options.ramMB)")
        setINI(&values, "vm.heapSize", "\(options.heapMB)")
        setINI(&values, "disk.dataPartition.size", "\(options.storageMB)M")
        setINI(&values, "hw.cpu.ncore", "\(options.cpuCores)")
        setINI(&values, "hw.lcd.width", "\(options.width)")
        setINI(&values, "hw.lcd.height", "\(options.height)")
        setINI(&values, "hw.lcd.density", "\(options.density)")
        setINI(&values, "hw.gpu.enabled", options.gpuMode == "off" ? "no" : "yes")
        setINI(&values, "hw.gpu.mode", options.gpuMode)
        setINI(&values, "fastboot.forceCold", options.bootMode == .cold ? "yes" : "no")
        setINI(&values, "hw.camera.back", options.cameraBack)
        setINI(&values, "hw.camera.front", options.cameraBack == "none" ? "none" : "emulated")
        setINI(&values, "hw.keyboard", options.keyboard ? "yes" : "no")
        setINI(&values, "hw.audioInput", options.audioInput ? "yes" : "no")
        setINI(&values, "hw.audioOutput", options.audioOutput ? "yes" : "no")
        setINI(&values, "showDeviceFrame", options.showDeviceFrame ? "yes" : "no")
        if !options.skinName.isEmpty { setINI(&values, "skin.name", options.skinName) }
        if !options.skinPath.isEmpty { setINI(&values, "skin.path", options.skinPath) }
        try renderINI(values).write(to: configURL, atomically: true, encoding: .utf8)
    }

    func options(
        for device: AndroidVirtualDevice,
        configuration: VirtualDeviceConfiguration
    ) -> VirtualDeviceOptions {
        let configURL = avdConfigURL(device: device, configuration: configuration)
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return VirtualDeviceOptions()
        }
        let values = parseINI(content).reduce(into: [String: String]()) { result, line in
            if let key = line.key { result[key] = line.value }
        }
        var options = VirtualDeviceOptions()
        options.systemImageID = systemImageID(from: values["image.sysdir.1"] ?? "")
        options.skinName = values["skin.name"] ?? ""
        options.skinPath = values["skin.path"] ?? ""
        options.ramMB = integer(values["hw.ramSize"], fallback: options.ramMB)
        options.heapMB = integer(values["vm.heapSize"], fallback: options.heapMB)
        options.storageMB = integer(values["disk.dataPartition.size"], fallback: options.storageMB)
        options.cpuCores = integer(values["hw.cpu.ncore"], fallback: options.cpuCores)
        options.width = integer(values["hw.lcd.width"], fallback: options.width)
        options.height = integer(values["hw.lcd.height"], fallback: options.height)
        options.density = integer(values["hw.lcd.density"], fallback: options.density)
        options.gpuMode = values["hw.gpu.mode"] ?? options.gpuMode
        options.bootMode = values["fastboot.forceCold"] == "yes" ? .cold : .quick
        options.cameraBack = values["hw.camera.back"] ?? options.cameraBack
        options.keyboard = values["hw.keyboard"] != "no"
        options.audioInput = values["hw.audioInput"] != "no"
        options.audioOutput = values["hw.audioOutput"] != "no"
        options.showDeviceFrame = values["showDeviceFrame"] != "no"
        options.formFactor = inferredFormFactor(skinName: options.skinName, imageID: options.systemImageID)
        return options
    }

    func deleteAVD(_ name: String, configuration: VirtualDeviceConfiguration) async throws {
        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(cli, ["emulator", "remove", name], configuration: configuration)
            if result.succeeded { return }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to remove virtual device", result) }
        }
        let installation = try resolve(configuration)
        let result = try await AndroidCommandRunner.run(
            executable: installation.avdmanager,
            arguments: ["delete", "avd", "--name", name], sdkRoot: sdkRoot(configuration),
            avdHome: avdHome(configuration)
        )
        guard result.succeeded else { throw commandError("virtualDeviceDeleteFailed", result) }
    }

    func startAVD(_ name: String, configuration: VirtualDeviceConfiguration) async throws {
        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(cli, ["emulator", "start", name], configuration: configuration)
            if result.succeeded { return }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to start virtual device", result) }
        }
        let installation = try resolve(configuration)
        let executable: URL
        if !configuration.emulatorPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: configuration.emulatorPath) {
            executable = URL(fileURLWithPath: configuration.emulatorPath)
        } else {
            executable = installation.emulator
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw VirtualDeviceError.message("virtualDeviceNoEmulatorFound")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-avd", name]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["ANDROID_HOME"] = installation.root.path
        environment["ANDROID_SDK_ROOT"] = installation.root.path
        environment["ANDROID_AVD_HOME"] = avdHome(configuration)
        process.environment = environment
        try process.run()
        emulatorProcesses[name] = process
    }

    func stopAVD(_ device: AndroidVirtualDevice, configuration: VirtualDeviceConfiguration) async throws {
        if let cli = resolveCLI(configuration) {
            let identifier = device.serial ?? device.name
            let result = try await runCLI(cli, ["emulator", "stop", identifier], configuration: configuration)
            if result.succeeded {
                emulatorProcesses.removeValue(forKey: device.name)
                return
            }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to stop virtual device", result) }
        }
        if let serial = device.serial {
            let installation = try resolve(configuration)
            let result = try await AndroidCommandRunner.run(
                executable: installation.adb, arguments: ["-s", serial, "emu", "kill"],
                sdkRoot: sdkRoot(configuration)
            )
            guard result.succeeded else { throw commandError("virtualDeviceStopFailed", result) }
        } else {
            emulatorProcesses[device.name]?.terminate()
        }
        emulatorProcesses.removeValue(forKey: device.name)
    }

    private struct INILine {
        var key: String?
        var value: String
        var raw: String
    }

    private func parseINI(_ content: String) -> [INILine] {
        content.components(separatedBy: .newlines).map { raw in
            guard !raw.hasPrefix("#"), let separator = raw.firstIndex(of: "=") else {
                return INILine(key: nil, value: "", raw: raw)
            }
            let key = String(raw[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(raw[raw.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            return INILine(key: key, value: value, raw: raw)
        }
    }

    private func setINI(_ lines: inout [INILine], _ key: String, _ value: String) {
        if let index = lines.firstIndex(where: { $0.key == key }) {
            lines[index].value = value
            lines[index].raw = "\(key)=\(value)"
        } else {
            lines.append(INILine(key: key, value: value, raw: "\(key)=\(value)"))
        }
    }

    private func renderINI(_ lines: [INILine]) -> String {
        lines.map(\.raw).joined(separator: "\n")
    }

    private func avdDirectory(name: String, configuration: VirtualDeviceConfiguration) -> URL {
        let safeName = name.replacingOccurrences(of: " ", with: "_")
        return URL(fileURLWithPath: avdHome(configuration), isDirectory: true)
            .appendingPathComponent("\(safeName).avd")
    }

    private func avdConfigURL(
        device: AndroidVirtualDevice,
        configuration: VirtualDeviceConfiguration
    ) -> URL {
        let directory = device.path.isEmpty
            ? avdDirectory(name: device.name, configuration: configuration)
            : URL(fileURLWithPath: device.path, isDirectory: true)
        return directory.appendingPathComponent("config.ini")
    }

    private func integer(_ value: String?, fallback: Int) -> Int {
        guard let value else { return fallback }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasSuffix("G"), let number = Double(normalized.dropLast()) {
            return Int((number * 1_024).rounded())
        }
        let digits = normalized.prefix { $0.isNumber }
        return Int(digits) ?? fallback
    }

    private func systemImageID(from path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: ";")
    }

    private func inferredFormFactor(skinName: String, imageID: String) -> VirtualDeviceFormFactor {
        skinFormFactor(skinName.isEmpty ? imageID : skinName)
    }

    private func skinDirectories(in root: URL) -> [URL] {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: root.appendingPathComponent("layout").path) {
            return [root]
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var result: [URL] = []
        for case let directory as URL in enumerator {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            if fileManager.fileExists(atPath: directory.appendingPathComponent("layout").path) {
                result.append(directory)
                enumerator.skipDescendants()
            }
        }
        return result
    }

    private func parseSkin(at directory: URL, isCustom: Bool) -> AndroidSkin? {
        let layoutURL = directory.appendingPathComponent("layout")
        guard let layout = try? String(contentsOf: layoutURL, encoding: .utf8) else { return nil }
        func firstInteger(after key: String) -> Int? {
            guard let expression = try? NSRegularExpression(pattern: "\\b\(key)\\s+(\\d+)") else { return nil }
            let range = NSRange(layout.startIndex..., in: layout)
            guard let match = expression.firstMatch(in: layout, range: range),
                  let valueRange = Range(match.range(at: 1), in: layout) else { return nil }
            return Int(layout[valueRange])
        }
        let previewNames = ["thumb.png", "back.webp", "back.png", "device_bezel.png", "fore.png"]
        let preview = previewNames
            .map(directory.appendingPathComponent)
            .first { FileManager.default.fileExists(atPath: $0.path) }
        let name = directory.lastPathComponent
        return AndroidSkin(
            id: directory.standardizedFileURL.path,
            name: name.replacingOccurrences(of: "_", with: " ").capitalized,
            path: directory.standardizedFileURL.path,
            formFactor: skinFormFactor(name),
            displayWidth: firstInteger(after: "width"),
            displayHeight: firstInteger(after: "height"),
            previewPath: preview?.path,
            isCustom: isCustom
        )
    }

    private func skinFormFactor(_ value: String) -> VirtualDeviceFormFactor {
        let name = value.lowercased()
        if name.contains("tv") { return .tv }
        if name.contains("tablet") || name.contains("pixel_c") || name.contains("nexus_7")
            || name.contains("nexus_9") || name.contains("nexus_10") { return .tablet }
        if name.contains("wear") { return .wear }
        if name.contains("automotive") { return .automotive }
        if name.contains("desktop") { return .desktop }
        if name.contains("xr") { return .xr }
        return .phone
    }

    private func resolve(_ configuration: VirtualDeviceConfiguration) throws -> AndroidSDKInstallation {
        guard let installation = AndroidSDKLocator.locate(
            preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
        ) else {
            throw VirtualDeviceError.message("virtualDeviceNoSDKToolsConfigured")
        }
        return installation
    }

    private func resolveCLI(_ configuration: VirtualDeviceConfiguration) -> AndroidCLIInstallation? {
        AndroidCLILocator.locate(
            preferredExecutable: configuration.androidCLIPath,
            preferredRoot: configuration.sdkRoot,
            preferredTools: configuration.toolsPath
        )
    }

    private func runCLI(
        _ cli: AndroidCLIInstallation,
        _ arguments: [String],
        configuration: VirtualDeviceConfiguration,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessOutput {
        try await AndroidCommandRunner.run(
            executable: cli.executable,
            arguments: ["--sdk=\(sdkRoot(configuration).path)"] + arguments,
            sdkRoot: sdkRoot(configuration), avdHome: avdHome(configuration), timeout: timeout
        )
    }

    private func cliPackageName(_ value: String) -> String {
        value.replacingOccurrences(of: ";", with: "/")
    }

    private func legacyPackageName(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: ";")
    }

    private func sdkRoot(_ configuration: VirtualDeviceConfiguration) -> URL {
        URL(fileURLWithPath: configuration.sdkRoot.isEmpty
            ? AndroidSDKLocator.defaultSDKRoot.path : configuration.sdkRoot)
    }

    private func skinsRoot(_ configuration: VirtualDeviceConfiguration) -> URL {
        configuration.skinsPath.isEmpty
            ? sdkRoot(configuration).appendingPathComponent("skins", isDirectory: true)
            : URL(fileURLWithPath: configuration.skinsPath, isDirectory: true)
    }

    private func avdHome(_ configuration: VirtualDeviceConfiguration) -> String {
        configuration.avdHome.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".android/avd").path
            : configuration.avdHome
    }

    private func avdCacheKey(_ configuration: VirtualDeviceConfiguration) -> String {
        [
            configuration.sdkRoot,
            configuration.androidCLIPath,
            configuration.toolsPath,
            configuration.avdHome,
            avdHome(configuration)
        ].joined(separator: "\u{1F}")
    }

    private func runningAVDs(
        installation: AndroidSDKInstallation, configuration: VirtualDeviceConfiguration
    ) async throws -> [String: String] {
        guard FileManager.default.isExecutableFile(atPath: installation.adb.path) else { return [:] }
        let devices = try await AndroidCommandRunner.run(
            executable: installation.adb, arguments: ["devices"], sdkRoot: sdkRoot(configuration)
        )
        let serials = devices.standardOutput.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, parts[0].hasPrefix("emulator-"), parts[1] == "device" else { return nil }
            return String(parts[0])
        }
        var result: [String: String] = [:]
        for serial in serials {
            let name = try await AndroidCommandRunner.run(
                executable: installation.adb, arguments: ["-s", serial, "emu", "avd", "name"],
                sdkRoot: sdkRoot(configuration)
            ).standardOutput.split(separator: "\n").first.map(String.init) ?? ""
            if !name.isEmpty { result[name] = serial }
        }
        return result
    }

    private func parseImages(_ text: String) -> [AndroidSystemImage] {
        var installed = Set<String>()
        var descriptions: [String: String] = [:]
        var section = ""
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.contains("installed packages") { section = "installed"; continue }
            if lower.contains("available packages") { section = "available"; continue }
            if lower.contains("available updates") { section = "updates"; continue }
            guard line.hasPrefix("system-images;") else { continue }
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let id = columns.first else { continue }
            if section == "installed" { installed.insert(id) }
            descriptions[id] = columns.count > 2 ? columns[2] : id
        }
#if arch(arm64)
        let architecture = "arm64-v8a"
#else
        let architecture = "x86_64"
#endif
        return descriptions.map { id, description in
            AndroidSystemImage(id: id, description: description, isInstalled: installed.contains(id))
        }
        .filter { $0.isInstalled || $0.id.contains(architecture) }
        .sorted { $0.id > $1.id }
    }

    private func parseCLIImages(_ text: String) -> [AndroidSystemImage] {
        var installed = Set<String>()
        var descriptions: [String: String] = [:]
        var section = ""
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("installed packages") { section = "installed"; continue }
            if lower.hasPrefix("available packages") { section = "available"; continue }
            guard line.hasPrefix("system-images/") else { continue }
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let id = columns.first else { continue }
            if section == "installed" { installed.insert(id) }
            descriptions[id] = columns.count > 2 ? columns.dropFirst(2).joined(separator: " ") : id
        }
#if arch(arm64)
        let architecture = "arm64-v8a"
#else
        let architecture = "x86_64"
#endif
        return descriptions.map { id, description in
            AndroidSystemImage(id: id, description: description, isInstalled: installed.contains(id))
        }
        .filter { $0.isInstalled || $0.id.contains(architecture) }
        .sorted { $0.id > $1.id }
    }

    private func parseCLIAVDs(_ text: String, avdHome: String) -> [AndroidVirtualDevice] {
        let regex = try! NSRegularExpression(
            pattern: #"^\s*(\S+)\s{2,}(.+?)\s{2,}(android-\S+)\s{2,}(\S+)(?:\s{2,}(\S+))?\s*$"#,
            options: [.anchorsMatchLines]
        )
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            func value(_ index: Int) -> String? {
                guard match.range(at: index).location != NSNotFound,
                      let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
            guard let id = value(1), id != "AVD" else { return nil }
            let status = value(4) ?? "Offline"
            let isRunning = status.caseInsensitiveCompare("Running") == .orderedSame
                || status.caseInsensitiveCompare("Online") == .orderedSame
            return AndroidVirtualDevice(
                name: id,
                device: value(2) ?? id,
                path: URL(fileURLWithPath: avdHome, isDirectory: true)
                    .appendingPathComponent("\(id).avd", isDirectory: true).path,
                target: value(3) ?? "",
                serial: isRunning ? value(5) : nil
            )
        }
    }

    private func parseAVDs(_ text: String) -> [AndroidVirtualDevice] {
        text.components(separatedBy: "---------").compactMap { block in
            var values: [String: String] = [:]
            for line in block.split(separator: "\n") {
                for key in ["Name", "Device", "Path", "Target"] where line.contains("\(key):") {
                    values[key] = line.split(separator: ":", maxSplits: 1).last?
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            guard let name = values["Name"], !name.hasPrefix("._") else { return nil }
            return AndroidVirtualDevice(
                name: name, device: values["Device"] ?? "", path: values["Path"] ?? "",
                target: values["Target"] ?? "", serial: nil
            )
        }
    }

    private func parseProfiles(_ text: String) -> [AndroidHardwareProfile] {
        text.components(separatedBy: "---------").compactMap { block in
            var id: String?
            var name: String?
            for rawLine in block.split(separator: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("id:") {
                    let value = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    id = value.split(separator: "\"").count >= 2
                        ? value.split(separator: "\"")[1].description
                        : value.split(whereSeparator: \.isWhitespace).first.map(String.init)
                } else if line.hasPrefix("Name:") {
                    name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                }
            }
            guard let id, let name else { return nil }
            return AndroidHardwareProfile(id: id, name: name)
        }.sorted { $0.name < $1.name }
    }

    private func commandError(_ prefixKey: String, _ result: ProcessOutput) -> VirtualDeviceError {
        let prefix = String.localizedKey(prefixKey)
        let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return .message(detail.isEmpty
            ? String(format: String.localizedKey("virtualDeviceCommandErrorWithCode"), prefix, result.status)
            : String(format: String.localizedKey("virtualDeviceCommandErrorWithDetails"), prefix, detail))
    }
}

enum VirtualDeviceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
