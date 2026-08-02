import SwiftUI
import Foundation
import CFNetwork

enum ToolDownloadKind: String, Identifiable {
    case adb
    case scrcpy
    case androidCLI
    case emulator
    case skins

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .adb: "ADB"
        case .scrcpy: "scrcpy"
        case .androidCLI: "Android CLI"
        case .emulator: "Android Emulator"
        case .skins: String.localizedKey("toolDownloadSkinsName")
        }
    }

    var installLocation: String {
        switch self {
        case .adb: "SDK/platform-tools/"
        case .scrcpy: "SDK/scrcpy/"
        case .androidCLI: "SDK/cmdline-tools/latest/"
        case .emulator: "SDK/emulator/"
        case .skins: "SDK/skins/"
        }
    }
}

enum ToolLocator {
    static func find(_ kind: ToolDownloadKind) -> String? {
        let name = kind.rawValue
        var candidates: [String] = []

        if let commandPath = commandPath(for: name) {
            candidates.append(commandPath)
        }

        let home = NSHomeDirectory()
        let support = "\(home)/Library/Application Support/Screen Remote/Tools"
        switch kind {
        case .adb:
            candidates += [
                "\(home)/Library/Android/sdk/platform-tools/adb",
                "/opt/homebrew/bin/adb",
                "/usr/local/bin/adb",
                "\(support)/platform-tools/adb",
                "\(home)/Library/Application Support/adb"
            ]
        case .scrcpy:
            candidates += [
                "\(home)/Library/Android/sdk/scrcpy/scrcpy",
                "/opt/homebrew/bin/scrcpy",
                "/usr/local/bin/scrcpy",
                "\(support)/scrcpy/scrcpy",
                "\(home)/Library/Application Support/scrcpy"
            ]
        case .androidCLI, .emulator, .skins:
            break
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func commandPath(for name: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; whence -p \(name)"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first
        } catch {
            return nil
        }
    }
}

struct ToolDownloadView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    @StateObject private var installer: ToolInstaller
    let kind: ToolDownloadKind
    let installed: (String) -> Void

    init(kind: ToolDownloadKind, installed: @escaping (String) -> Void) {
        self.kind = kind
        self.installed = installed
        _installer = StateObject(wrappedValue: ToolInstaller(kind: kind))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: String.localizedKey("toolDownloadTitle"), kind.displayName)).font(.title2.bold())
                    Text("toolDownloadSubtitle").foregroundColor(.secondary)
                }
                Spacer()
                Button("toolDownloadClose") { presentationMode.wrappedValue.dismiss() }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("toolDownloadUseProxy", isOn: $appState.useDownloadProxy)
                    .font(.headline)
                    .disabled(installer.isWorking)
                if appState.useDownloadProxy {
                    HStack(spacing: 8) {
                        Picker("toolDownloadProxyType", selection: $appState.downloadProxyType) {
                            Text(verbatim: "HTTP").tag("http")
                            Text(verbatim: "SOCKS5").tag("socks5")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 126)
                        TextField("toolDownloadProxyDefaultAddress", text: $appState.downloadProxy)
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(installer.isWorking)
                    Text("toolDownloadProxyHelp")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("toolDownloadDirectConnect")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if kind == .scrcpy {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("toolDownloadUseAccelerator", isOn: $appState.useDownloadAccelerator)
                        .font(.headline)
                        .disabled(installer.isWorking)
                    if appState.useDownloadAccelerator {
                        TextField("toolDownloadAcceleratorPlaceholder", text: $appState.downloadAccelerator)
                            .textFieldStyle(.roundedBorder)
                            .disabled(installer.isWorking)
                        Text("toolDownloadAcceleratorHelp")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("toolDownloadScrcpyOfficialSource")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if kind == .skins {
                Text("toolDownloadSkinsSource")
                    .font(.caption).foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(installer.statusText)
                    Spacer()
                    if installer.isDownloading { Text(installer.progressText).appMonospacedDigit() }
                }
                .font(.subheadline)

                ProgressView(value: installer.progress)
                    .progressViewStyle(.linear)

                Text(String(
                    format: String.localizedKey("toolDownloadInstallLocation"),
                    kind == .skins ? resolvedSkinsPath : kind.installLocation
                ))
                    .font(.caption).foregroundColor(.secondary)
            }

            if let error = installer.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                if installer.isWorking {
                    Button("commonCancel") { installer.cancel() }
                }
                Spacer()
                Button(installer.isComplete ? "toolDownloadDone" : "toolDownloadDownloadAndInstall") {
                    if installer.isComplete {
                        if let path = installer.installedPath { installed(path) }
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        installer.start(
                            accelerator: kind == .scrcpy && appState.useDownloadAccelerator
                                ? appState.downloadAccelerator : "",
                            proxy: appState.useDownloadProxy ? appState.downloadProxy : "",
                            proxyType: appState.downloadProxyType,
                            sdkRoot: appState.androidSDKRoot,
                            toolsPath: appState.commandLineToolsPath,
                            androidCLIPath: appState.androidCLIPath,
                            skinsPath: appState.skinsPath
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(installer.isWorking)
            }
        }
        .padding(22)
        .appPresentationWidth(relativeTo: appState.appWindowWidth)
        .appPresentationHeight(relativeTo: appState.appWindowHeight)
        .background(AppTheme.background)
    }

    private var resolvedSkinsPath: String {
        appState.skinsPath.isEmpty
            ? URL(fileURLWithPath: appState.androidSDKRoot.isEmpty
                ? AndroidSDKLocator.defaultSDKRoot.path : appState.androidSDKRoot)
                .appendingPathComponent("skins", isDirectory: true).path
            : appState.skinsPath
    }
}
