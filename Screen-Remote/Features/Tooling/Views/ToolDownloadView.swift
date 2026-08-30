import Foundation
import SwiftUI

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
