import AppKit
import Foundation
import SwiftUI

enum VirtualDeviceFormFactor: String, CaseIterable, Identifiable {
    case phone
    case tablet
    case tv
    case wear
    case automotive
    case desktop
    case xr
    case other

    var id: String { rawValue }
    var localizationKey: LocalizedStringKey {
        switch self {
        case .phone: "virtualDeviceFormFactorPhone"
        case .tablet: "virtualDeviceFormFactorTablet"
        case .tv: "virtualDeviceFormFactorTV"
        case .wear: "virtualDeviceFormFactorWear"
        case .automotive: "virtualDeviceFormFactorAutomotive"
        case .desktop: "virtualDeviceFormFactorDesktop"
        case .xr: "virtualDeviceFormFactorXR"
        case .other: "virtualDeviceFormFactorOther"
        }
    }
    var icon: String {
        switch self {
        case .phone: "iphone.gen3"
        case .tablet: "ipad"
        case .tv: "tv"
        case .wear: "applewatch"
        case .automotive: "car"
        case .desktop: "desktopcomputer"
        case .xr: "visionpro"
        case .other: "square.grid.2x2"
        }
    }
}

enum AndroidImageService: String, CaseIterable, Identifiable {
    case googlePlay
    case googleAPIs
    case aosp

    var id: String { rawValue }
    var localizationKey: LocalizedStringKey {
        switch self {
        case .googlePlay: "virtualDeviceImageServiceGooglePlay"
        case .googleAPIs: "virtualDeviceImageServiceGoogleAPIs"
        case .aosp: "virtualDeviceImageServiceAOSP"
        }
    }
}

struct AndroidSystemImage: Identifiable, Hashable {
    let id: String
    let description: String
    let isInstalled: Bool

    var displayName: String {
        let parts = packageParts
        guard parts.count >= 4 else { return description }
        let api = parts[1].replacingOccurrences(of: "android-", with: "API ")
        let flavor: String
        switch parts[2] {
        case "google_apis": flavor = "Google APIs"
        case "google_apis_playstore": flavor = "Google Play"
        case "default": flavor = "AOSP"
        case "android-tv": flavor = "Android TV"
        case "android-wear": flavor = "Wear OS"
        default: flavor = parts[2]
        }
        return "\(api) · \(flavor) · \(parts[3])"
    }

    private var packageParts: [String] {
        let separator: Character = id.contains(";") ? ";" : "/"
        return id.split(separator: separator).map(String.init)
    }

    var canonicalID: String {
        Self.canonicalID(id)
    }

    static func canonicalID(_ value: String) -> String {
        let parts = value
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: ";", with: "/")
            .split(separator: "/")
            .map(String.init)
        guard let systemImagesIndex = parts.lastIndex(of: "system-images") else {
            return parts.joined(separator: ";")
        }
        return parts[systemImagesIndex...].joined(separator: ";")
    }

    var apiLevel: String { packageParts.count > 1 ? packageParts[1].replacingOccurrences(of: "android-", with: "") : "" }
    var apiCategory: String {
        let majorLevel = apiLevel.prefix { $0.isNumber }
        return majorLevel.isEmpty ? apiLevel : String(majorLevel)
    }
    var variant: String { packageParts.count > 2 ? packageParts[2] : "" }
    var architecture: String { packageParts.count > 3 ? packageParts[3] : "" }

    var formFactor: VirtualDeviceFormFactor {
        let value = variant.lowercased()
        if value.contains("wear") { return .wear }
        if value.contains("automotive") || value.contains("atd") { return .automotive }
        if value.contains("tv") { return .tv }
        if value.contains("tablet") { return .tablet }
        if value.contains("desktop") { return .desktop }
        if value.contains("xr") { return .xr }
        return .phone
    }

    var service: AndroidImageService {
        let value = variant.lowercased()
        if value.contains("playstore") || value.contains("google_play") || value.contains("google-tv") {
            return .googlePlay
        }
        if value.contains("google") { return .googleAPIs }
        return .aosp
    }
}

struct AndroidVirtualDevice: Identifiable {
    var id: String { name }
    let name: String
    let device: String
    let path: String
    let target: String
    var serial: String?
    var isRunning: Bool { serial != nil }
}

struct AndroidHardwareProfile: Identifiable, Hashable {
    let id: String
    let name: String
}

struct AndroidSkin: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let formFactor: VirtualDeviceFormFactor
    let displayWidth: Int?
    let displayHeight: Int?
    let previewPath: String?
    let isCustom: Bool

    var detail: String {
        guard let displayWidth, let displayHeight else { return path }
        return "\(displayWidth) × \(displayHeight)"
    }
}

enum VirtualDeviceBootMode: String, CaseIterable, Identifiable {
    case quick
    case cold

    var id: String { rawValue }
    var localizationKey: LocalizedStringKey {
        switch self {
        case .quick: "virtualDeviceBootModeQuick"
        case .cold: "virtualDeviceBootModeCold"
        }
    }
}

struct VirtualDeviceOptions: Equatable {
    var systemImageID = ""
    var formFactor: VirtualDeviceFormFactor = .phone
    var skinName = ""
    var skinPath = ""
    var ramMB = 2_048
    var heapMB = 512
    var storageMB = 6_144
    var sdCardMB = 512
    var cpuCores = 4
    var width = 1_080
    var height = 2_400
    var density = 420
    var gpuMode = "auto"
    var bootMode: VirtualDeviceBootMode = .quick
    var cameraBack = "emulated"
    var keyboard = true
    var audioInput = true
    var audioOutput = true
    var showDeviceFrame = true
}

struct VirtualDeviceConfiguration {
    let sdkRoot: String
    let androidCLIPath: String
    let toolsPath: String
    let emulatorPath: String
    let skinsPath: String
    let avdHome: String
}

final class VirtualDeviceService {
    private var emulatorProcesses: [String: Process] = [:]

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

    func listAVDs(_ configuration: VirtualDeviceConfiguration) async throws -> [AndroidVirtualDevice] {
        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(
                cli, ["emulator", "list", "--long"], configuration: configuration, timeout: 15
            )
            if result.succeeded {
                return parseCLIAVDs(result.standardOutput, avdHome: avdHome(configuration))
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
        var devices = parseAVDs(result.standardOutput)
        let running = try await runningAVDs(installation: installation, configuration: configuration)
        for index in devices.indices { devices[index].serial = running[devices[index].name] }
        return devices
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

@MainActor
final class VirtualDeviceViewModel: ObservableObject {
    @Published var images: [AndroidSystemImage] = []
    @Published var devices: [AndroidVirtualDevice] = []
    @Published var profiles: [AndroidHardwareProfile] = []
    @Published var skins: [AndroidSkin] = []
    @Published var isWorking = false
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var workingImageID: String?
    private let service = VirtualDeviceService()

    func refresh(_ configuration: VirtualDeviceConfiguration) {
        skins = service.listSkins(configuration)
        perform(String.localizedKey("virtualDeviceStatusReadingSDK")) {
            async let images = self.service.listImages(configuration)
            async let devices = self.service.listAVDs(configuration)
            async let profiles = self.service.listHardwareProfiles(configuration)
            self.images = try await images
            self.devices = try await devices
            self.profiles = try await profiles
        }
    }

    func refreshDevices(_ configuration: VirtualDeviceConfiguration) {
        perform(String.localizedKey("virtualDeviceStatusReadingSDK")) {
            self.devices = try await self.service.listAVDs(configuration)
        }
    }

    func install(_ image: AndroidSystemImage, configuration: VirtualDeviceConfiguration) {
        workingImageID = image.id
        perform(String(format: String.localizedKey("virtualDeviceStatusInstalling"), image.displayName)) {
            try await self.service.installImage(image.id, configuration: configuration)
            self.images = try await self.service.listImages(configuration)
        } completion: { self.workingImageID = nil }
    }

    func uninstall(_ image: AndroidSystemImage, configuration: VirtualDeviceConfiguration) {
        let usingDevices = devicesUsing(image, configuration: configuration)
        guard usingDevices.isEmpty else {
            errorMessage = String(
                format: String.localizedKey("virtualDeviceImageInUseError"),
                usingDevices.map(\.name).joined(separator: ", ")
            )
            return
        }
        workingImageID = image.id
        perform(String(format: String.localizedKey("virtualDeviceStatusUninstalling"), image.displayName)) {
            try await self.service.uninstallImage(image.id, configuration: configuration)
            self.images = try await self.service.listImages(configuration)
        } completion: { self.workingImageID = nil }
    }

    func devicesUsing(
        _ image: AndroidSystemImage,
        configuration: VirtualDeviceConfiguration
    ) -> [AndroidVirtualDevice] {
        devices.filter { device in
            let configuredImageID = service.options(for: device, configuration: configuration).systemImageID
            return AndroidSystemImage.canonicalID(configuredImageID) == image.canonicalID
        }
    }

    func create(
        name: String,
        image: String,
        profile: String?,
        options: VirtualDeviceOptions,
        configuration: VirtualDeviceConfiguration
    ) {
        perform(String(format: String.localizedKey("virtualDeviceStatusCreating"), name)) {
            try await self.service.createAVD(
                name: name,
                image: image,
                profile: profile,
                options: options,
                configuration: configuration
            )
            self.devices = try await self.service.listAVDs(configuration)
        }
    }

    func edit(
        _ device: AndroidVirtualDevice,
        options: VirtualDeviceOptions,
        configuration: VirtualDeviceConfiguration
    ) {
        perform(String(format: String.localizedKey("virtualDeviceStatusUpdating"), device.name)) {
            try self.service.updateAVD(device, options: options, configuration: configuration)
            self.devices = try await self.service.listAVDs(configuration)
        }
    }

    func options(for device: AndroidVirtualDevice, configuration: VirtualDeviceConfiguration) -> VirtualDeviceOptions {
        service.options(for: device, configuration: configuration)
    }

    func prepareEditorResources(_ configuration: VirtualDeviceConfiguration) {
        skins = service.listSkins(configuration)
        Task {
            do {
                async let images = self.service.listImages(configuration)
                async let profiles = self.service.listHardwareProfiles(configuration)
                self.images = try await images
                self.profiles = try await profiles
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func addCustomSkin(_ url: URL, configuration: VirtualDeviceConfiguration) -> AndroidSkin? {
        let custom = service.listSkins(configuration, customDirectories: [url]).first { $0.isCustom }
        if let custom, !skins.contains(where: { $0.path == custom.path }) {
            skins.insert(custom, at: 0)
        }
        return custom
    }

    func delete(_ device: AndroidVirtualDevice, configuration: VirtualDeviceConfiguration) {
        perform(String(format: String.localizedKey("virtualDeviceStatusDeleting"), device.name)) {
            try await self.service.deleteAVD(device.name, configuration: configuration)
            self.devices = try await self.service.listAVDs(configuration)
        }
    }

    func toggle(_ device: AndroidVirtualDevice, configuration: VirtualDeviceConfiguration) {
        perform(device.isRunning
            ? String(format: String.localizedKey("virtualDeviceStatusStopping"), device.name)
            : String(format: String.localizedKey("virtualDeviceStatusStarting"), device.name)) {
            if device.isRunning {
                try await self.service.stopAVD(device, configuration: configuration)
            } else {
                try await self.service.startAVD(device.name, configuration: configuration)
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            self.devices = try await self.service.listAVDs(configuration)
        }
    }

    private func perform(
        _ status: String,
        operation: @escaping () async throws -> Void,
        completion: @escaping () -> Void = { }
    ) {
        guard !isWorking else { return }
        isWorking = true
        self.status = status
        errorMessage = nil
        Task {
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
            isWorking = false
            self.status = ""
            completion()
        }
    }
}

private enum VirtualDeviceSheet: Identifiable {
    case create
    case edit(AndroidVirtualDevice)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let device): "edit-\(device.id)"
        }
    }
}

struct VirtualDeviceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel = VirtualDeviceViewModel()
    @State private var tab = 0
    @State private var activeSheet: VirtualDeviceSheet?

    private var configuration: VirtualDeviceConfiguration {
        VirtualDeviceConfiguration(
            sdkRoot: appState.androidSDKRoot,
            androidCLIPath: appState.androidCLIPath,
            toolsPath: appState.commandLineToolsPath,
            emulatorPath: appState.emulatorPath,
            skinsPath: appState.skinsPath,
            avdHome: appState.avdHome
        )
    }

    private var isCompact: Bool {
        AppPresentationMetrics.preferredWidth(
            relativeTo: appState.appWindowWidth,
            idealWidth: AppPresentationMetrics.IdealWidth.virtualDevices
        ) < 600
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Picker("virtualDeviceTitle", selection: $tab) {
                Text("virtualDeviceMyDevices").tag(0)
                Text("virtualDeviceSystemImages").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            if viewModel.isWorking {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text(viewModel.status).font(.caption).foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
            }
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if tab == 0 {
                virtualDevicesContent
            } else {
                SystemImagesView(viewModel: viewModel, configuration: configuration)
            }
        }
        .appPresentationWidth(
            relativeTo: appState.appWindowWidth,
            idealWidth: AppPresentationMetrics.IdealWidth.virtualDevices
        )
        .appPresentationHeight(relativeTo: appState.appWindowHeight)
        .background(AppTheme.background)
        .onAppear {
            viewModel.refresh(configuration)
            if appState.shouldOpenVirtualDeviceCreator {
                appState.shouldOpenVirtualDeviceCreator = false
                activeSheet = .create
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                VirtualDeviceEditorView(
                    viewModel: viewModel,
                    configuration: configuration,
                    device: nil,
                    initialOptions: VirtualDeviceOptions()
                )
                .environment(\.locale, appState.resolvedLocale)
            case .edit(let device):
                VirtualDeviceEditorView(
                    viewModel: viewModel,
                    configuration: configuration,
                    device: device,
                    initialOptions: viewModel.options(for: device, configuration: configuration)
                )
                .environment(\.locale, appState.resolvedLocale)
            }
        }
    }

    private var header: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 12) {
                    headerTitle
                    HStack(spacing: 10) {
                        headerActions
                    }
                }
                .padding(16)
            } else {
                HStack(spacing: 10) {
                    headerTitle
                    Spacer()
                    headerActions
                }
                .padding(22)
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("virtualDeviceTitle").font(.title2.bold())
            Text("virtualDeviceSubtitle").font(.subheadline).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        if tab == 0 {
            Button {
                activeSheet = .create
            } label: {
                Label("virtualDeviceCreateAction", systemImage: "plus")
            }
            .disabled(viewModel.isWorking)
        }
        Spacer()
        Button { viewModel.refresh(configuration) } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("virtualDeviceRefresh")
        .disabled(viewModel.isWorking)
        Button("commonDone") { presentationMode.wrappedValue.dismiss() }
    }

    private var virtualDevicesContent: some View {
        Group {
            if viewModel.devices.isEmpty && !viewModel.isWorking {
                VStack(spacing: 13) {
                    Image(systemName: "iphone.gen3.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary)
                    Text("virtualDeviceNoDevicesTitle").font(.headline)
                    Text("virtualDeviceNoDevicesDetail")
                        .font(.subheadline).foregroundColor(.secondary)
                    Button("virtualDeviceCreateAction") { activeSheet = .create }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.devices) { device in
                            HStack(spacing: 14) {
                                Image(systemName: device.isRunning ? "play.circle.fill" : "iphone.gen3")
                                    .font(.system(size: 25))
                                    .foregroundColor(device.isRunning ? .green : AppTheme.accent)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 7) {
                                        Text(device.name).font(.headline)
                                        if device.isRunning {
                                            Text("virtualDeviceRunning")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(.green)
                                        }
                                    }
                                    Text(device.target.isEmpty ? device.path : device.target)
                                        .font(.caption).foregroundColor(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Button {
                                    activeSheet = .edit(device)
                                } label: {
                                    Label("commonEdit", systemImage: "slider.horizontal.3")
                                        .labelStyle(.iconOnly)
                                }
                                .help("commonEdit")
                                .disabled(device.isRunning || viewModel.isWorking)
                                Button {
                                    viewModel.toggle(device, configuration: configuration)
                                } label: {
                                    Label(
                                        device.isRunning ? "virtualDeviceActionStop" : "virtualDeviceActionStart",
                                        systemImage: device.isRunning ? "stop.fill" : "play.fill"
                                    )
                                    .labelStyle(.iconOnly)
                                }
                                .help(device.isRunning ? "virtualDeviceActionStop" : "virtualDeviceActionStart")
                                .disabled(viewModel.isWorking)
                                Button {
                                    viewModel.delete(device, configuration: configuration)
                                } label: {
                                    Image(systemName: "trash").foregroundColor(.red)
                                }
                                .disabled(device.isRunning || viewModel.isWorking)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

private struct SystemImagesView: View {
    @ObservedObject var viewModel: VirtualDeviceViewModel
    let configuration: VirtualDeviceConfiguration
    @State private var searchText = ""
    @State private var formFactor = "all"
    @State private var apiCategory = "all"
    @State private var service = "all"
    @State private var imagePendingRemoval: AndroidSystemImage?

    private var apiCategories: [String] {
        Array(Set(viewModel.images.map(\.apiCategory).filter { !$0.isEmpty })).sorted {
            (Int($0) ?? 0) > (Int($1) ?? 0)
        }
    }

    private var filteredImages: [AndroidSystemImage] {
        viewModel.images.filter { image in
            let matchesSearch = searchText.isEmpty
                || image.displayName.localizedCaseInsensitiveContains(searchText)
                || image.id.localizedCaseInsensitiveContains(searchText)
            let matchesFormFactor = formFactor == "all" || image.formFactor.rawValue == formFactor
            let matchesAPI = apiCategory == "all" || image.apiCategory == apiCategory
            let matchesService = service == "all" || image.service.rawValue == service
            return matchesSearch && matchesFormFactor && matchesAPI && matchesService
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("virtualDeviceImageSearch", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.055)))

                HStack(spacing: 8) {
                    FilterPicker(title: "virtualDeviceFilterFormFactor", selection: $formFactor) {
                        Text("virtualDeviceFilterAll").tag("all")
                        ForEach(VirtualDeviceFormFactor.allCases) { value in
                            Text(value.localizationKey).tag(value.rawValue)
                        }
                    }
                    FilterPicker(title: "virtualDeviceFilterAPI", selection: $apiCategory) {
                        Text("virtualDeviceFilterAll").tag("all")
                        ForEach(apiCategories, id: \.self) { Text("API \($0)").tag($0) }
                    }
                    FilterPicker(title: "virtualDeviceFilterService", selection: $service) {
                        Text("virtualDeviceFilterAll").tag("all")
                        ForEach(AndroidImageService.allCases) { value in
                            Text(value.localizationKey).tag(value.rawValue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: String.localizedKey("virtualDeviceImageCount"), filteredImages.count))
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            if filteredImages.isEmpty && !viewModel.isWorking {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.system(size: 38)).foregroundColor(.secondary)
                    Text("virtualDeviceNoMatchingImages").font(.headline)
                    Text("virtualDeviceNoMatchingImagesDetail")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        imageSection(
                            title: "virtualDeviceInstalledSection",
                            icon: "checkmark.circle.fill",
                            images: filteredImages.filter(\.isInstalled)
                        )
                        imageSection(
                            title: "virtualDeviceAvailableSection",
                            icon: "arrow.down.circle",
                            images: filteredImages.filter { !$0.isInstalled }
                        )
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                }
            }
        }
        .alert(item: $imagePendingRemoval) { image in
            Alert(
                title: Text("virtualDeviceRemoveImageConfirmationTitle"),
                message: Text(String(
                    format: String.localizedKey("virtualDeviceRemoveImageConfirmationMessage"),
                    image.displayName
                )),
                primaryButton: .destructive(Text("virtualDeviceRemove")) {
                    viewModel.uninstall(image, configuration: configuration)
                },
                secondaryButton: .cancel(Text("commonCancel"))
            )
        }
    }

    @ViewBuilder
    private func imageSection(
        title: LocalizedStringKey,
        icon: String,
        images: [AndroidSystemImage]
    ) -> some View {
        if !images.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        let usingDevices = viewModel.devicesUsing(image, configuration: configuration)
                        SystemImageRow(
                            image: image,
                            isWorking: viewModel.workingImageID == image.id,
                            isInteractionDisabled: viewModel.isWorking,
                            usageDescription: usingDevices.isEmpty ? nil : String(
                                format: String.localizedKey("virtualDeviceImageInUseHelp"),
                                usingDevices.map(\.name).joined(separator: ", ")
                            ),
                            action: {
                                if image.isInstalled {
                                    imagePendingRemoval = image
                                } else {
                                    viewModel.install(image, configuration: configuration)
                                }
                            }
                        )
                        if index < images.count - 1 { Divider().padding(.leading, 48) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
            }
        }
    }
}

private struct FilterPicker<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Picker(title, selection: $selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct SystemImageRow: View {
    let image: AndroidSystemImage
    let isWorking: Bool
    let isInteractionDisabled: Bool
    let usageDescription: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: image.formFactor.icon)
                .font(.system(size: 18))
                .foregroundColor(image.isInstalled ? .green : AppTheme.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.055)))
            VStack(alignment: .leading, spacing: 3) {
                Text(image.displayName).font(.system(size: 13, weight: .medium))
                Text(image.description).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                Text(image.id).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if image.isInstalled {
                Label("virtualDeviceInstalled", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundColor(.green)
            }
            if let usageDescription {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help(usageDescription)
            }
            if isWorking {
                ProgressView().scaleEffect(0.7).frame(width: 48)
            } else {
                Button(image.isInstalled ? "virtualDeviceRemove" : "virtualDeviceDownload", action: action)
                    .disabled(isInteractionDisabled || isWorking || usageDescription != nil)
                    .help(usageDescription ?? "")
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 68)
    }
}

struct VirtualDeviceEditorView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: VirtualDeviceViewModel
    let configuration: VirtualDeviceConfiguration
    let device: AndroidVirtualDevice?

    @State private var name: String
    @State private var profile = ""
    @State private var options: VirtualDeviceOptions
    @State private var selectedSkinPath: String

    init(
        viewModel: VirtualDeviceViewModel,
        configuration: VirtualDeviceConfiguration,
        device: AndroidVirtualDevice?,
        initialOptions: VirtualDeviceOptions
    ) {
        self.viewModel = viewModel
        self.configuration = configuration
        self.device = device
        _name = State(initialValue: device?.name ?? "")
        _options = State(initialValue: initialOptions)
        _selectedSkinPath = State(initialValue: initialOptions.skinPath)
    }

    private var isEditing: Bool { device != nil }
    private var availableSkins: [AndroidSkin] {
        viewModel.skins.filter { $0.formFactor == options.formFactor }
    }
    private var installedImages: [AndroidSystemImage] {
        viewModel.images.filter { image in
            guard image.isInstalled else { return false }
            switch options.formFactor {
            case .tablet: return image.formFactor == .tablet || image.formFactor == .phone
            default: return image.formFactor == options.formFactor
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEditing ? "virtualDeviceEditTitle" : "virtualDeviceCreateTitle")
                        .font(.title2.bold())
                    Text("virtualDeviceEditorSubtitle").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Label("virtualDeviceCLIBacked", systemImage: "terminal")
                    .font(.caption).foregroundColor(AppTheme.accent)
            }
            .padding(22)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    editorSection(number: 1, title: "virtualDeviceTypeSection") {
                        HStack(spacing: 10) {
                            ForEach([VirtualDeviceFormFactor.phone, .tablet, .tv]) { factor in
                                Button {
                                    applyFormFactor(factor)
                                } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: factor.icon).font(.system(size: 24))
                                        Text(factor.localizationKey).font(.caption.weight(.medium))
                                    }
                                    .foregroundColor(options.formFactor == factor ? AppTheme.accent : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 72)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(options.formFactor == factor ? AppTheme.accent.opacity(0.11) : Color.primary.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(options.formFactor == factor ? AppTheme.accent : AppTheme.line, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    editorSection(number: 2, title: "virtualDeviceSkinSection") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: String.localizedKey("virtualDeviceSkinCount"), availableSkins.count))
                                .font(.caption).foregroundColor(.secondary)
                            HStack {
                                Button("virtualDeviceOpenSkinsFolder") { revealSkinsFolder() }
                                Button("virtualDeviceAddCustomSkin") { chooseCustomSkin() }
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                            ForEach(availableSkins) { skin in
                                SkinCard(skin: skin, isSelected: selectedSkinPath == skin.path) {
                                    selectSkin(skin)
                                }
                            }
                        }
                    }

                    editorSection(number: 3, title: "virtualDeviceSystemSection") {
                        if isEditing {
                            HStack {
                                Image(systemName: "shippingbox.fill").foregroundColor(AppTheme.accent)
                                Text(options.systemImageID.isEmpty ? device?.target ?? "" : options.systemImageID)
                                    .font(.system(size: 11, design: .monospaced)).lineLimit(2)
                            }
                            Text("virtualDeviceSystemImmutable")
                                .font(.caption2).foregroundColor(.secondary)
                        } else if installedImages.isEmpty {
                            Label("virtualDeviceNoCompatibleInstalledImages", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        } else {
                            Picker("virtualDeviceSystemImage", selection: $options.systemImageID) {
                                Text("virtualDevicePleaseSelect").tag("")
                                ForEach(installedImages) { image in
                                    Text(image.displayName).tag(image.id)
                                }
                            }
                        }
                    }

                    editorSection(number: 4, title: "virtualDeviceParametersSection") {
                        VStack(spacing: 11) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 120), spacing: 14)],
                                spacing: 11
                            ) {
                                LabeledIntegerField(title: "virtualDeviceRAM", value: $options.ramMB, suffix: "MB")
                                LabeledIntegerField(title: "virtualDeviceCPUCores", value: $options.cpuCores, suffix: "")
                                LabeledIntegerField(title: "virtualDeviceStorage", value: $options.storageMB, suffix: "MB")
                                LabeledIntegerField(title: "virtualDeviceHeap", value: $options.heapMB, suffix: "MB")
                                LabeledIntegerField(title: "virtualDeviceWidth", value: $options.width, suffix: "px")
                                LabeledIntegerField(title: "virtualDeviceHeight", value: $options.height, suffix: "px")
                                LabeledIntegerField(title: "virtualDeviceDensity", value: $options.density, suffix: "dpi")
                                LabeledIntegerField(title: "virtualDeviceSDCard", value: $options.sdCardMB, suffix: "MB")
                            }
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 155), spacing: 18)],
                                alignment: .leading,
                                spacing: 11
                            ) {
                                Picker("virtualDeviceGPU", selection: $options.gpuMode) {
                                    Text("virtualDeviceGPUAuto").tag("auto")
                                    Text("virtualDeviceGPUHost").tag("host")
                                    Text("virtualDeviceGPUSoftware").tag("swiftshader_indirect")
                                    Text("virtualDeviceGPUOff").tag("off")
                                }
                                Picker("virtualDeviceBootMode", selection: $options.bootMode) {
                                    ForEach(VirtualDeviceBootMode.allCases) { mode in
                                        Text(mode.localizationKey).tag(mode)
                                    }
                                }
                                Picker("virtualDeviceCamera", selection: $options.cameraBack) {
                                    Text("virtualDeviceCameraEmulated").tag("emulated")
                                    Text("virtualDeviceCameraWebcam").tag("webcam0")
                                    Text("virtualDeviceCameraNone").tag("none")
                                }
                            }
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 145), spacing: 20)],
                                alignment: .leading,
                                spacing: 9
                            ) {
                                Toggle("virtualDeviceKeyboard", isOn: $options.keyboard)
                                Toggle("virtualDeviceAudioInput", isOn: $options.audioInput)
                                Toggle("virtualDeviceAudioOutput", isOn: $options.audioOutput)
                                Toggle("virtualDeviceShowFrame", isOn: $options.showDeviceFrame)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }

                    editorSection(number: 5, title: "virtualDeviceIdentitySection") {
                        TextField("virtualDeviceDeviceName", text: $name)
                            .disabled(isEditing)
                        Picker("virtualDeviceHardwareProfile", selection: $profile) {
                            Text("virtualDeviceDefault").tag("")
                            ForEach(viewModel.profiles) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                .padding(22)
            }

            Divider()
            HStack {
                Button("commonCancel") { presentationMode.wrappedValue.dismiss() }
                Spacer()
                Button(isEditing ? "commonSave" : "commonCreate") {
                    save()
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .appPresentationWidth(
            relativeTo: appState.appWindowWidth,
            idealWidth: AppPresentationMetrics.IdealWidth.virtualDeviceEditor
        )
        .appPresentationHeight(relativeTo: appState.appWindowHeight)
        .background(AppTheme.background)
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasName && (isEditing || !options.systemImageID.isEmpty)
    }

    @ViewBuilder
    private func editorSection<Content: View>(
        number: Int,
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption2.bold()).foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(AppTheme.accent))
                Text(title).font(.headline)
            }
            content()
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))
    }

    private func applyFormFactor(_ factor: VirtualDeviceFormFactor) {
        options.formFactor = factor
        selectedSkinPath = ""
        options.skinName = ""
        options.skinPath = ""
        options.systemImageID = ""
        switch factor {
        case .phone:
            options.width = 1_080; options.height = 2_400; options.density = 420
        case .tablet:
            options.width = 1_600; options.height = 2_560; options.density = 320
        case .tv:
            options.width = 1_920; options.height = 1_080; options.density = 320
        default: break
        }
    }

    private func selectSkin(_ skin: AndroidSkin) {
        selectedSkinPath = skin.path
        options.skinName = URL(fileURLWithPath: skin.path).lastPathComponent
        options.skinPath = skin.path
        if let width = skin.displayWidth { options.width = width }
        if let height = skin.displayHeight { options.height = height }
    }

    private func chooseCustomSkin() {
        let panel = NSOpenPanel()
        panel.title = String.localizedKey("virtualDeviceChooseSkinFolder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let skin = viewModel.addCustomSkin(url, configuration: configuration) else { return }
            options.formFactor = skin.formFactor
            selectSkin(skin)
        }
    }

    private func revealSkinsFolder() {
        let root = configuration.skinsPath.isEmpty
            ? URL(fileURLWithPath: configuration.sdkRoot.isEmpty
                ? AndroidSDKLocator.defaultSDKRoot.path : configuration.sdkRoot)
                .appendingPathComponent("skins", isDirectory: true)
            : URL(fileURLWithPath: configuration.skinsPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    private func save() {
        if let device {
            viewModel.edit(device, options: options, configuration: configuration)
        } else {
            viewModel.create(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                image: options.systemImageID,
                profile: profile.isEmpty ? nil : profile,
                options: options,
                configuration: configuration
            )
        }
    }
}

private struct SkinCard: View {
    let skin: AndroidSkin
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let previewPath = skin.previewPath,
                       let image = NSImage(contentsOfFile: previewPath) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: skin.formFactor.icon)
                            .resizable().scaledToFit().padding(18)
                    }
                }
                .frame(height: 72)
                .foregroundColor(.secondary)
                Text(skin.name).font(.caption.weight(.medium)).lineLimit(1)
                Text(skin.detail).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9).fill(isSelected ? AppTheme.accent.opacity(0.1) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(isSelected ? AppTheme.accent : AppTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct LabeledIntegerField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            HStack(spacing: 4) {
                TextField("", value: $value, formatter: integerFormatter)
                    .textFieldStyle(.roundedBorder)
                if !suffix.isEmpty { Text(suffix).font(.caption2).foregroundColor(.secondary) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }
}
