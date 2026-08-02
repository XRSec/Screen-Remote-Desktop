import AppKit
import SwiftUI

private let managementCardColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let managementCardGridMaxWidth: CGFloat = 914

private struct PortForwardEntry: Identifiable {
    let serial: String; let local: String; let remote: String
    var id: String { "\(serial)-\(local)-\(remote)" }
}

struct PortForwardView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var entries: [PortForwardEntry] = []
    @State private var localPort = "8080"
    @State private var remotePort = "8080"
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if managementTarget(from: appState) == nil { ManagementUnavailableView() }
            else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        LabeledPortField(title: "managementLocalPort", text: $localPort)
                        Image(systemName: "arrow.right")
                        LabeledPortField(title: "managementDevicePort", text: $remotePort)
                        Button("managementAddForward", action: addForward).buttonStyle(.bordered)
                    }.padding(16).appCard()
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                    if let errorMessage { ManagementErrorBanner(message: errorMessage) }
                    if entries.isEmpty && !isLoading {
                        ContentUnavailableViewCompat(icon: "arrow.left.arrow.right", title: "managementNoForwards", detail: "managementNoForwardsDetail").frame(minHeight: 220)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(entries) { entry in
                                HStack {
                                    Image(systemName: "arrow.left.arrow.right").foregroundColor(AppTheme.accent)
                                    Text(entry.local).font(.system(.body, design: .monospaced))
                                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                                    Text(entry.remote).font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button(action: { remove(entry) }) { Image(systemName: "trash") }.buttonStyle(.plain)
                                }.padding(14)
                                Divider().padding(.leading, 44)
                            }
                        }.appCard()
                    }
                    Spacer()
                }.padding(isCompact ? 20 : 28)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: appState.selectedDevice) { _ in refresh() }
        .onChange(of: managementTarget(from: appState)?.serial ?? "") { serial in if !serial.isEmpty { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .screenRemoteRefreshManagement)) { _ in refresh() }
    }

    private func refresh() {
        guard let target = managementTarget(from: appState) else { return }
        isLoading = true; errorMessage = nil
        Task {
            do {
                let output = try await ManagementADB.run(target: target, arguments: ["forward", "--list"])
                guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
                entries = output.text.split(whereSeparator: \.isNewline).compactMap { line in
                    let fields = line.split(whereSeparator: \.isWhitespace); guard fields.count >= 3, fields[0] == Substring(target.serial) else { return nil }
                    return PortForwardEntry(serial: String(fields[0]), local: String(fields[1]), remote: String(fields[2]))
                }
            } catch { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    private func addForward() {
        guard let target = managementTarget(from: appState), let local = Int(localPort), let remote = Int(remotePort), (1...65535).contains(local), (1...65535).contains(remote) else {
            errorMessage = String.localizedKey("managementInvalidPort"); return
        }
        Task {
            do {
                let output = try await ManagementADB.run(target: target, arguments: ["forward", "tcp:\(local)", "tcp:\(remote)"])
                guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
                appState.appendSDLLog("ADB port forward added: \(target.device.name), tcp:\(local) -> tcp:\(remote)")
                refresh()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func remove(_ entry: PortForwardEntry) {
        guard let target = managementTarget(from: appState) else { return }
        Task {
            do {
                let output = try await ManagementADB.run(target: target, arguments: ["forward", "--remove", entry.local])
                guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
                appState.appendSDLLog("ADB port forward removed: \(target.device.name), \(entry.local)")
                refresh()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct LabeledPortField: View {
    let title: LocalizedStringKey; @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundColor(.secondary); TextField("8080", text: $text).frame(width: 90) }
    }
}

// MARK: - Utilities
