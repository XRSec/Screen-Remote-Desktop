import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var adbStatus: ToolStatus = .unchecked
    @State private var scrcpyStatus: ToolStatus = .unchecked
    @State private var androidCLIStatus: ToolStatus = .unchecked
    @State private var commandLineToolsStatus: ToolStatus = .unchecked
    @State private var emulatorStatus: ToolStatus = .unchecked
    @State private var skinsStatus: ToolStatus = .unchecked
    @State private var downloadKind: ToolDownloadKind?
    @State private var cacheUsageBytes: Int64 = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BasicPreferencesCard(
                        language: $appState.appLanguage,
                        theme: $appState.appTheme
                    )
                    CacheManagementCard(
                        cacheSize: formattedCacheSize,
                        clear: clearCaches
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
                .frame(maxWidth: 700)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppTheme.background)
        .onAppear {
            detectBasicTools()
            detectSDK()
            refreshCacheUsage()
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

    private var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheUsageBytes, countStyle: .file)
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

    private func refreshCacheUsage() {
        cacheUsageBytes = DeviceAppCacheStore.diskUsageBytes()
            + ScrcpyCodecCapabilityCache.diskUsageBytes()
    }

    private func clearCaches() {
        let alert = NSAlert()
        alert.messageText = String.localizedKey("settingsClearCache")
        alert.informativeText = String.localizedKey("settingsClearCacheConfirmation")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String.localizedKey("settingsClearCache"))
        alert.addButton(withTitle: String.localizedKey("commonCancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        appState.deviceApps.clearCache()
        ScrcpyCodecCapabilityCache.clearAll()
        refreshCacheUsage()
        appState.appendSDLLog("Application caches cleared", tag: .other)
    }
}

private struct CacheManagementCard: View {
    let cacheSize: String
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SettingsSectionHeader(
                symbol: "internaldrive",
                title: "settingsCacheSection",
                detail: "settingsCacheSectionDetail"
            )
            HStack {
                Label("settingsCacheSize", systemImage: "externaldrive")
                    .foregroundColor(.secondary)
                Spacer()
                Text(cacheSize)
                    .font(AppTypography.monospacedCaption)
                Button("settingsClearCache", action: clear)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .settingsPanel()
    }
}

private struct BasicPreferencesCard: View {
    @Binding var language: AppLanguagePreference
    @Binding var theme: AppThemePreference

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SettingsSectionHeader(
                symbol: "switch.2",
                title: "settingsBasicPreferences",
                detail: "settingsBasicPreferencesDetail"
            )
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
        .settingsPanel()
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
            SettingsSectionHeader(
                symbol: "iphone.gen3",
                title: "settingsVirtualDeviceCapability",
                detail: "settingsVirtualDeviceCapabilityDetail"
            )
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
        .settingsPanel()
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
            HStack(spacing: 10) {
                SettingsSectionHeader(
                    symbol: "cursorarrow.motionlines",
                    title: "settingsBasicControl",
                    detail: "settingsBasicControlDetail"
                )
                Spacer()
                Button("settingsAutoDetect", action: detect)
                    .controlSize(.small)
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
        .settingsPanel()
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
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(AppTypography.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(AppTypography.subheadline.weight(.semibold))
                    Text(detail).font(AppTypography.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Label(status.title, systemImage: status.icon)
                    .font(AppTypography.caption)
                    .foregroundColor(status.color)
            }
            HStack(spacing: AppSpacing.sm) {
                TextField("settingsExecutablePath", text: $path).textFieldStyle(.roundedBorder)
                Button("commonChooseEllipsis", action: browse)
                if status != .ready {
                    Button("commonDownloadEllipsis", action: download)
                }
            }
            .controlSize(.small)
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
                        .accessibilityLabel(Text(status.title))
                }
                Button("commonChooseEllipsis", action: browse)
                if let download, status != .ready {
                    Button("commonDownloadEllipsis", action: download)
                }
            }
            .controlSize(.small)
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
                    .accessibilityLabel(Text(status.title))
                Button("commonChooseEllipsis", action: browse)
                if let download, status != .ready {
                    Button("commonDownloadEllipsis", action: download)
                }
            }
            .controlSize(.small)
        }
    }
}

private struct SettingsSectionHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: symbol)
                .font(AppTypography.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppTypography.subheadline.weight(.semibold))
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private extension View {
    func settingsPanel() -> some View {
        padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(AppTheme.surface.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
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
