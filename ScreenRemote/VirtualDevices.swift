import Foundation
import SwiftUI

struct AndroidSystemImage: Identifiable, Hashable {
    let id: String
    let description: String
    let isInstalled: Bool

    var displayName: String {
        let separator: Character = id.contains(";") ? ";" : "/"
        let parts = id.split(separator: separator).map(String.init)
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

struct VirtualDeviceConfiguration {
    let sdkRoot: String
    let androidCLIPath: String
    let toolsPath: String
    let emulatorPath: String
    let avdHome: String
}

final class VirtualDeviceService {
    private var emulatorProcesses: [String: Process] = [:]

    func listImages(_ configuration: VirtualDeviceConfiguration) async throws -> [AndroidSystemImage] {
        if let cli = resolveCLI(configuration) {
            let output = try await runCLI(
                cli, ["sdk", "list", "system-images*", "--all"], configuration: configuration
            )
            if output.succeeded { return parseCLIImages(output.standardOutput) }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to list system images", output) }
        }
        let installation = try resolve(configuration)
        let output = try await AndroidCommandRunner.run(
            executable: installation.sdkmanager,
            arguments: ["--list", "--sdk_root=\(sdkRoot(configuration).path)"],
            sdkRoot: sdkRoot(configuration)
        )
        guard output.succeeded else { throw commandError("virtualDeviceReadSystemImagesFailed", output) }
        return parseImages(output.standardOutput)
    }

    func listAVDs(_ configuration: VirtualDeviceConfiguration) async throws -> [AndroidVirtualDevice] {
        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(cli, ["emulator", "list", "--long"], configuration: configuration)
            if result.succeeded { return parseCLIAVDs(result.standardOutput) }
            if AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to list virtual devices", result) }
        }
        let installation = try resolve(configuration)
        let result = try await AndroidCommandRunner.run(
            executable: installation.avdmanager, arguments: ["list", "avd"],
            sdkRoot: sdkRoot(configuration), avdHome: avdHome(configuration)
        )
        var devices = parseAVDs(result.standardOutput)
        let running = try await runningAVDs(installation: installation, configuration: configuration)
        for index in devices.indices { devices[index].serial = running[devices[index].name] }
        return devices
    }

    func listHardwareProfiles(_ configuration: VirtualDeviceConfiguration) async throws -> [AndroidHardwareProfile] {
        if let cli = resolveCLI(configuration) {
            let result = try await runCLI(
                cli, ["emulator", "create", "--list-profiles"], configuration: configuration
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
        let installation = try resolve(configuration)
        let result = try await AndroidCommandRunner.run(
            executable: installation.avdmanager, arguments: ["list", "device"],
            sdkRoot: sdkRoot(configuration)
        )
        guard result.succeeded else { throw commandError("virtualDeviceReadHardwareProfilesFailed", result) }
        return parseProfiles(result.standardOutput)
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
        name: String, image: String, profile: String?, configuration: VirtualDeviceConfiguration
    ) async throws {
        if let cli = resolveCLI(configuration) {
            let selectedProfile = profile.flatMap { $0.isEmpty ? nil : $0 } ?? "medium_phone"
            let result = try await runCLI(
                cli, ["emulator", "create", selectedProfile], configuration: configuration
            )
            if result.succeeded { return }
            if image.isEmpty || AndroidSDKLocator.locate(
                preferredRoot: configuration.sdkRoot, preferredTools: configuration.toolsPath
            ) == nil { throw commandError("Failed to create virtual device", result) }
        }
        let installation = try resolve(configuration)
        var arguments = ["create", "avd", "--name", name, "--package", image, "--force"]
        if let profile, !profile.isEmpty { arguments += ["--device", profile] }
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
        configuration: VirtualDeviceConfiguration
    ) async throws -> ProcessOutput {
        try await AndroidCommandRunner.run(
            executable: cli.executable,
            arguments: ["--sdk=\(sdkRoot(configuration).path)"] + arguments,
            sdkRoot: sdkRoot(configuration), avdHome: avdHome(configuration)
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

    private func parseCLIAVDs(_ text: String) -> [AndroidVirtualDevice] {
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
            return AndroidVirtualDevice(
                name: id, device: value(2) ?? id, path: "", target: value(3) ?? "",
                serial: status.caseInsensitiveCompare("Running") == .orderedSame ? value(5) : nil
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
    @Published var isWorking = false
    @Published var status = ""
    @Published var errorMessage: String?
    private let service = VirtualDeviceService()

    func refresh(_ configuration: VirtualDeviceConfiguration) {
        perform(String.localizedKey("virtualDeviceStatusReadingSDK")) {
            async let images = self.service.listImages(configuration)
            async let devices = self.service.listAVDs(configuration)
            async let profiles = self.service.listHardwareProfiles(configuration)
            self.images = try await images
            self.devices = try await devices
            self.profiles = try await profiles
        }
    }

    func install(_ image: AndroidSystemImage, configuration: VirtualDeviceConfiguration) {
        perform(String(format: String.localizedKey("virtualDeviceStatusInstalling"), image.displayName)) {
            try await self.service.installImage(image.id, configuration: configuration)
            self.images = try await self.service.listImages(configuration)
        }
    }

    func uninstall(_ image: AndroidSystemImage, configuration: VirtualDeviceConfiguration) {
        perform(String(format: String.localizedKey("virtualDeviceStatusUninstalling"), image.displayName)) {
            try await self.service.uninstallImage(image.id, configuration: configuration)
            self.images = try await self.service.listImages(configuration)
        }
    }

    func create(name: String, image: String, profile: String?, configuration: VirtualDeviceConfiguration) {
        perform(String(format: String.localizedKey("virtualDeviceStatusCreating"), name)) {
            try await self.service.createAVD(name: name, image: image, profile: profile, configuration: configuration)
            self.devices = try await self.service.listAVDs(configuration)
        }
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

    private func perform(_ status: String, operation: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        self.status = status
        errorMessage = nil
        Task {
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
            isWorking = false
            self.status = ""
        }
    }
}

struct VirtualDeviceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel = VirtualDeviceViewModel()
    @State private var tab = 0
    @State private var showingCreate = false

    private var configuration: VirtualDeviceConfiguration {
        VirtualDeviceConfiguration(
            sdkRoot: appState.androidSDKRoot, androidCLIPath: appState.androidCLIPath,
            toolsPath: appState.commandLineToolsPath,
            emulatorPath: appState.emulatorPath, avdHome: appState.avdHome
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("virtualDeviceTitle").font(.title2.bold())
                    Text("virtualDeviceSubtitle").foregroundColor(.secondary)
                }
                Spacer()
                if tab == 0 { Button("virtualDeviceCreateAction") { showingCreate = true }.disabled(viewModel.isWorking) }
                Button { viewModel.refresh(configuration) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(viewModel.isWorking)
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
            }.padding(22)
            Divider()

            Picker("", selection: $tab) {
                Text("virtualDeviceMyDevices").tag(0)
                Text("virtualDeviceSystemImages").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal, 22).padding(.vertical, 14)

            if viewModel.isWorking {
                HStack { ProgressView(); Text(viewModel.status).font(.caption).foregroundColor(.secondary) }
                    .padding(.bottom, 8)
            }
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.secondary).padding(.horizontal, 22).padding(.bottom, 8)
            }

            List {
                if tab == 0 {
                    ForEach(viewModel.devices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: device.isRunning ? "play.circle.fill" : "iphone.gen3")
                                .foregroundColor(device.isRunning ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(device.name).font(.headline)
                                Text(device.target.isEmpty ? device.path : device.target)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(device.isRunning ? "virtualDeviceActionStop" : "virtualDeviceActionStart") {
                                viewModel.toggle(device, configuration: configuration)
                            }
                            Button(action: { viewModel.delete(device, configuration: configuration) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }.disabled(device.isRunning)
                        }.padding(.vertical, 5)
                    }
                } else {
                    ForEach(viewModel.images) { image in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(image.displayName)
                                Text(image.id).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            if image.isInstalled {
                                Label("virtualDeviceInstalled", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                                Button(action: { viewModel.uninstall(image, configuration: configuration) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            } else {
                                Button("virtualDeviceDownload") { viewModel.install(image, configuration: configuration) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }.listStyle(.inset)
        }
        .frame(width: 820, height: 620)
        .background(AppTheme.background)
        .onAppear { viewModel.refresh(configuration) }
        .sheet(isPresented: $showingCreate) {
            CreateVirtualDeviceView(viewModel: viewModel, configuration: configuration)
        }
    }
}

private struct CreateVirtualDeviceView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var viewModel: VirtualDeviceViewModel
    let configuration: VirtualDeviceConfiguration
    @State private var name = ""
    @State private var image = ""
    @State private var profile = ""

    private var usesAndroidCLI: Bool {
        AndroidCLILocator.locate(
            preferredExecutable: configuration.androidCLIPath,
            preferredRoot: configuration.sdkRoot,
            preferredTools: configuration.toolsPath
        ) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("virtualDeviceCreateTitle").font(.title2.bold())
            if usesAndroidCLI {
                Label("virtualDeviceUseAndroidCLI", systemImage: "sparkles")
                    .font(.caption).foregroundColor(AppTheme.accent)
                Text("virtualDeviceAndroidCLIDescription")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Label("virtualDeviceUseLegacyCLI", systemImage: "arrow.uturn.backward")
                    .font(.caption).foregroundColor(.secondary)
                TextField("virtualDeviceDeviceName", text: $name)
                Picker("virtualDeviceSystemImage", selection: $image) {
                    Text("virtualDevicePleaseSelect").tag("")
                    ForEach(viewModel.images.filter(\.isInstalled)) { Text($0.displayName).tag($0.id) }
                }
            }
            Picker("virtualDeviceHardwareProfile", selection: $profile) {
                Text(usesAndroidCLI ? "virtualDevicePleaseSelect" : "virtualDeviceDefault").tag("")
                ForEach(viewModel.profiles) { Text($0.name).tag($0.id) }
            }
            Spacer()
            HStack {
                Button("commonCancel") { presentationMode.wrappedValue.dismiss() }
                Spacer()
                Button("commonCreate") {
                    let fallbackImage = image.isEmpty
                        ? (viewModel.images.first(where: \.isInstalled)?.id ?? "") : image
                    viewModel.create(
                        name: usesAndroidCLI ? profile : name,
                        image: fallbackImage, profile: profile, configuration: configuration
                    )
                    presentationMode.wrappedValue.dismiss()
                }.keyboardShortcut(.defaultAction)
                    .disabled(usesAndroidCLI
                        ? profile.isEmpty
                        : name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image.isEmpty)
            }
        }.padding(22).frame(width: 480, height: 280)
    }
}
