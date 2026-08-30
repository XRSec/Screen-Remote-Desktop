import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @State private var adbStatus: ToolStatus = .unchecked
    @State private var scrcpyStatus: ToolStatus = .unchecked
    @State private var androidCLIStatus: ToolStatus = .unchecked
    @State private var commandLineToolsStatus: ToolStatus = .unchecked
    @State private var emulatorStatus: ToolStatus = .unchecked
    @State private var skinsStatus: ToolStatus = .unchecked
    @State private var downloadKind: ToolDownloadKind?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                AppIconTile(symbol: "gearshape.fill", color: AppTheme.accent, size: 42)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("settingsTitle")
                        .font(AppTypography.title)
                    Text("settingsSubtitle")
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, AppSpacing.xl)
            .frame(minHeight: 72)
            .background(AppTheme.surface.opacity(0.72))

            Divider().opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    BasicPreferencesCard(
                        language: $appState.appLanguage,
                        theme: $appState.appTheme
                    )
                    BasicControlToolsCard(
                        adbPath: $appState.adbPath,
                        scrcpyPath: $appState.scrcpyPath,
                        adbStatus: adbStatus,
                        scrcpyStatus: scrcpyStatus,
                        browseADB: { chooseTool(binding: $appState.adbPath) },
                        browseScrcpy: { chooseTool(binding: $appState.scrcpyPath) },
                        downloadADB: { downloadKind = .adb },
                        downloadScrcpy: { downloadKind = .scrcpy },
                        detect: detectBasicTools
                    )

                    SDKConfigurationCard(
                        sdkRoot: $appState.androidSDKRoot,
                        androidCLIPath: $appState.androidCLIPath,
                        toolsPath: $appState.commandLineToolsPath,
                        emulatorPath: $appState.emulatorPath,
                        skinsPath: $appState.skinsPath,
                        avdHome: $appState.avdHome,
                        androidCLIStatus: androidCLIStatus,
                        commandLineToolsStatus: commandLineToolsStatus,
                        emulatorStatus: emulatorStatus,
                        skinsStatus: skinsStatus,
                        browseDirectory: chooseDirectory,
                        browseExecutable: chooseTool,
                        downloadAndroidCLI: { downloadKind = .androidCLI },
                        downloadEmulator: { downloadKind = .emulator },
                        downloadSkins: { downloadKind = .skins },
                        detect: detectSDK
                    )

                    Text("settingsStorageLocation")
                        .font(.caption2)
                        .foregroundColor(Color.secondary.opacity(0.65))
                        .padding(.horizontal, 4)

                }
                .frame(maxWidth: 760)
                .padding(AppSpacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppTheme.background)
        .onAppear {
            detectBasicTools()
            detectSDK()
        }
        .onChange(of: appState.adbPath) { _ in testPaths() }
        .onChange(of: appState.scrcpyPath) { _ in testPaths() }
        .onChange(of: appState.androidCLIPath) { _ in testPaths() }
        .onChange(of: appState.commandLineToolsPath) { _ in testPaths() }
        .onChange(of: appState.emulatorPath) { _ in testPaths() }
        .onChange(of: appState.skinsPath) { _ in testPaths() }
        .sheet(item: $downloadKind) { kind in
            ToolDownloadView(kind: kind) { installedPath in
                switch kind {
                case .adb: appState.adbPath = installedPath
                case .scrcpy: appState.scrcpyPath = installedPath
                case .androidCLI:
                    appState.androidCLIPath = installedPath
                    appState.commandLineToolsPath = URL(fileURLWithPath: installedPath)
                        .deletingLastPathComponent().path
                    detectSDK()
                case .emulator: appState.emulatorPath = installedPath
                case .skins: appState.skinsPath = installedPath
                }
                testPaths()
            }
        }
    }

    private func chooseTool(binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String.localizedKey("settingsChooseExecutable")
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
            testPaths()
        }
    }

    private func chooseDirectory(binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String.localizedKey("settingsChooseDirectory")
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
            testPaths()
        }
    }

    private func detectBasicTools() {
        if !FileManager.default.isExecutableFile(atPath: appState.adbPath),
           let path = ToolLocator.find(.adb) { appState.adbPath = path }
        if !FileManager.default.isExecutableFile(atPath: appState.scrcpyPath),
           let path = ToolLocator.find(.scrcpy) { appState.scrcpyPath = path }
        testPaths()
    }

    private func detectSDK() {
        if let cli = AndroidCLILocator.locate(
            preferredExecutable: appState.androidCLIPath,
            preferredRoot: appState.androidSDKRoot,
            preferredTools: appState.commandLineToolsPath
        ) {
            appState.androidSDKRoot = cli.root.path
            appState.androidCLIPath = cli.executable.path
        }
        guard let installation = AndroidSDKLocator.locate(
            preferredRoot: appState.androidSDKRoot,
            preferredTools: appState.commandLineToolsPath
        ) else {
            testPaths()
            return
        }
        appState.androidSDKRoot = installation.root.path
        appState.commandLineToolsPath = installation.toolsBin.path
        if FileManager.default.isExecutableFile(atPath: installation.emulator.path) {
            appState.emulatorPath = installation.emulator.path
        }
        if appState.skinsPath.isEmpty {
            appState.skinsPath = installation.root.appendingPathComponent("skins", isDirectory: true).path
        }
        testPaths()
    }

    private func testPaths() {
        adbStatus = FileManager.default.isExecutableFile(atPath: appState.adbPath) ? .ready : .missing
        scrcpyStatus = FileManager.default.isExecutableFile(atPath: appState.scrcpyPath) ? .ready : .missing
        androidCLIStatus = FileManager.default.isExecutableFile(atPath: appState.androidCLIPath) ? .ready : .missing
        let tools = URL(fileURLWithPath: appState.commandLineToolsPath)
        commandLineToolsStatus = FileManager.default.isExecutableFile(
            atPath: tools.appendingPathComponent("sdkmanager").path
        ) && FileManager.default.isExecutableFile(
            atPath: tools.appendingPathComponent("avdmanager").path
        ) ? .ready : .missing
        emulatorStatus = FileManager.default.isExecutableFile(atPath: appState.emulatorPath) ? .ready : .missing
        skinsStatus = containsSkin(in: appState.skinsPath) ? .ready : .missing
    }

    private func containsSkin(in path: String) -> Bool {
        guard !path.isEmpty,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: URL(fileURLWithPath: path, isDirectory: true),
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else { return false }
        return entries.contains {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("layout").path)
        }
    }
}

private struct BasicPreferencesCard: View {
    @Binding var language: AppLanguagePreference
    @Binding var theme: AppThemePreference

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.md) {
                AppIconTile(symbol: "switch.2", color: .appIndigo, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("settingsBasicPreferences")
                        .font(AppTypography.section)
                    Text("settingsBasicPreferencesDetail")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("settingsLanguage").font(.caption.weight(.medium))
                Picker("settingsLanguage", selection: $language) {
                    Text("settingsLanguageSystem").tag(AppLanguagePreference.system)
                    Text("settingsLanguageEnglish").tag(AppLanguagePreference.english)
                    Text("settingsLanguageChinese").tag(AppLanguagePreference.simplifiedChinese)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("settingsTheme").font(.caption.weight(.medium))
                Picker("settingsTheme", selection: $theme) {
                    Text("settingsThemeSystem").tag(AppThemePreference.system)
                    Text("settingsThemeLight").tag(AppThemePreference.light)
                    Text("settingsThemeDark").tag(AppThemePreference.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(AppSpacing.lg)
        .appCard()
    }
}

private struct SDKConfigurationCard: View {
    @Binding var sdkRoot: String
    @Binding var androidCLIPath: String
    @Binding var toolsPath: String
    @Binding var emulatorPath: String
    @Binding var skinsPath: String
    @Binding var avdHome: String
    let androidCLIStatus: ToolStatus
    let commandLineToolsStatus: ToolStatus
    let emulatorStatus: ToolStatus
    let skinsStatus: ToolStatus
    let browseDirectory: (Binding<String>) -> Void
    let browseExecutable: (Binding<String>) -> Void
    let downloadAndroidCLI: () -> Void
    let downloadEmulator: () -> Void
    let downloadSkins: () -> Void
    let detect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: AppSpacing.md) {
                AppIconTile(symbol: "iphone.gen3", color: .appTeal, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("settingsVirtualDeviceCapability")
                        .font(AppTypography.section)
                    Text("settingsVirtualDeviceCapabilityDetail")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: AppSpacing.sm) {
                Spacer()
                Button {
                    openSDKFolder()
                } label: {
                    Label("settingsOpenFolder", systemImage: "folder")
                }
                Button("settingsAutoDetect", action: detect)
            }
            HStack(spacing: 6) {
                Text("settingsShared").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .foregroundColor(.secondary)
                Text("settingsSharedByNewAndLegacy").font(.caption.weight(.medium))
            }

            DirectorySettingRow(
                title: String.localizedKey("settingsSDKRoot"), placeholder: "~/Library/Android/sdk",
                path: $sdkRoot, browse: { browseDirectory($sdkRoot) }
            )

            DirectorySettingRow(
                title: String.localizedKey("settingsAVDHome"), placeholder: String.localizedKey("settingsAVDHomePlaceholder"),
                path: $avdHome, browse: { browseDirectory($avdHome) }
            )

            DirectorySettingRow(
                title: String.localizedKey("settingsSkinsPath"),
                placeholder: "…/skins",
                path: $skinsPath, status: skinsStatus,
                download: downloadSkins,
                browse: { browseDirectory($skinsPath) }
            )
            Text("settingsSkinsPathDetail")
                .font(.caption2).foregroundColor(.secondary)

            ExecutableSettingRow(
                title: String.localizedKey("settingsAndroidEmulator"),
                path: $emulatorPath, status: emulatorStatus,
                download: downloadEmulator,
                browse: { browseExecutable($emulatorPath) }
            )

            Divider()

            HStack(spacing: 6) {
                Text("settingsNew").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(AppTheme.accent.opacity(0.12)))
                    .foregroundColor(AppTheme.accent)
                Text("settingsRecommendedAndroidCLI").font(.caption.weight(.medium))
            }
            ExecutableSettingRow(
                title: String.localizedKey("settingsAndroidCLI"),
                path: $androidCLIPath, status: androidCLIStatus,
                download: downloadAndroidCLI,
                browse: { browseExecutable($androidCLIPath) }
            )
            Text("settingsNewCLIExplanation")
                .font(.caption2).foregroundColor(.secondary)

            Divider()

            HStack(spacing: 6) {
                Text("settingsLegacy").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .foregroundColor(.secondary)
                Text("settingsLegacyToolsCompatibility").font(.caption.weight(.medium))
            }
            DirectorySettingRow(
                title: String.localizedKey("settingsCommandLineTools"),
                placeholder: "…/cmdline-tools/latest/bin",
                path: $toolsPath, status: commandLineToolsStatus,
                browse: { browseDirectory($toolsPath) }
            )
        }
        .padding(16)
        .appCard()
    }

    private func openSDKFolder() {
        let path = sdkRoot.isEmpty ? AndroidSDKLocator.defaultSDKRoot.path : sdkRoot
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

private struct BasicControlToolsCard: View {
    @Binding var adbPath: String
    @Binding var scrcpyPath: String
    let adbStatus: ToolStatus
    let scrcpyStatus: ToolStatus
    let browseADB: () -> Void
    let browseScrcpy: () -> Void
    let downloadADB: () -> Void
    let downloadScrcpy: () -> Void
    let detect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: AppSpacing.md) {
                AppIconTile(symbol: "cursorarrow.motionlines", color: .appCyan, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("settingsBasicControl")
                        .font(AppTypography.section)
                    Text("settingsBasicControlDetail")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("settingsAutoDetect", action: detect)
            }
            InlineToolRow(
                title: String.localizedKey("settingsAndroidDebugBridge"),
                detail: String.localizedKey("settingsADBDetail"),
                icon: "terminal.fill", path: $adbPath, status: adbStatus,
                browse: browseADB, download: downloadADB
            )
            Divider()
            InlineToolRow(
                title: "scrcpy", detail: String.localizedKey("settingsScrcpyDetail"),
                icon: "rectangle.on.rectangle.angled", path: $scrcpyPath, status: scrcpyStatus,
                browse: browseScrcpy, download: downloadScrcpy
            )
            Text("settingsToolInstallLocations")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(16)
        .appCard()
    }
}

private struct InlineToolRow: View {
    let title: String
    let detail: String
    let icon: String
    @Binding var path: String
    let status: ToolStatus
    let browse: () -> Void
    let download: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.accent.opacity(0.1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Label(status.title, systemImage: status.icon)
                    .font(.caption.weight(.medium))
                    .foregroundColor(status.color)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .appBackground(status.color.opacity(0.1), in: Capsule())
            }
            HStack(spacing: 8) {
                TextField("settingsExecutablePath", text: $path).textFieldStyle(.roundedBorder)
                Button("commonChooseEllipsis", action: browse)
                Button("commonDownloadEllipsis", action: download)
            }
        }
    }
}

private struct DirectorySettingRow: View {
    let title: String
    let placeholder: String
    @Binding var path: String
    var status: ToolStatus?
    var download: (() -> Void)?
    let browse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(.caption.weight(.medium))
            HStack(spacing: AppSpacing.sm) {
                TextField(placeholder, text: $path)
                    .textFieldStyle(.roundedBorder)
                if let status {
                    Image(systemName: status.icon)
                        .foregroundColor(status.color)
                        .help(status.title)
                }
                Button("commonChooseEllipsis", action: browse)
                if let download { Button("commonDownloadEllipsis", action: download) }
            }
        }
    }
}

private struct ExecutableSettingRow: View {
    let title: String
    @Binding var path: String
    let status: ToolStatus
    var download: (() -> Void)?
    let browse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(.caption.weight(.medium))
            HStack(spacing: AppSpacing.sm) {
                TextField("settingsExecutablePath", text: $path)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: status.icon)
                    .foregroundColor(status.color)
                    .help(status.title)
                Button("commonChooseEllipsis", action: browse)
                if let download { Button("commonDownloadEllipsis", action: download) }
            }
        }
    }
}

private enum ToolStatus: Equatable {
    case unchecked, ready, missing

    var title: String {
        switch self {
        case .unchecked: String.localizedKey("settingsStatusUnchecked")
        case .ready: String.localizedKey("settingsStatusReady")
        case .missing: String.localizedKey("settingsStatusMissing")
        }
    }
    var color: Color {
        switch self {
        case .unchecked: .secondary
        case .ready: .green
        case .missing: .orange
        }
    }
    var icon: String {
        switch self {
        case .unchecked: "circle.dashed"
        case .ready: "checkmark.circle.fill"
        case .missing: "exclamationmark.circle"
        }
    }
}
