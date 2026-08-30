import AppKit
import SwiftUI

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
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack(spacing: AppSpacing.sm) {
                        LabeledPortField(title: "managementLocalPort", text: $localPort)
                        Image(systemName: "arrow.right")
                            .font(AppTypography.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        LabeledPortField(title: "managementDevicePort", text: $remotePort)
                        Button("managementAddForward", action: addForward)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 2)
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                    if let errorMessage { ManagementErrorBanner(message: errorMessage) }
                    if entries.isEmpty && !isLoading {
                        ContentUnavailableViewCompat(icon: "arrow.left.arrow.right", title: "managementNoForwards", detail: "managementNoForwardsDetail").frame(minHeight: 220)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                HStack {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(AppTypography.caption.weight(.medium))
                                        .foregroundColor(AppTheme.accent)
                                        .frame(width: 20)
                                    Text(entry.local)
                                        .font(AppTypography.monospacedCaption)
                                    Image(systemName: "arrow.right")
                                        .font(AppTypography.caption2)
                                        .foregroundColor(.secondary)
                                    Text(entry.remote)
                                        .font(AppTypography.monospacedCaption)
                                    Spacer()
                                    Button(action: { remove(entry) }) {
                                        Image(systemName: "trash")
                                            .font(AppTypography.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.plain)
                                    .help("managementDelete")
                                    .accessibilityLabel(Text("managementDelete"))
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.sm)
                                if index != entries.count - 1 {
                                    Divider().padding(.leading, 42)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                                .fill(Color.primary.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                                .stroke(AppTheme.line, lineWidth: 1)
                        )
                    }
                    Spacer()
                }.padding(isCompact ? AppSpacing.lg : AppSpacing.xxl)
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
                    let fields = line.split(whereSeparator: \.isWhitespace)
                    guard fields.count >= 3, fields[0] == Substring(target.serial) else { return nil }
                    let local = String(fields[1])
                    let remote = String(fields[2])
                    guard local.hasPrefix("tcp:"), remote.hasPrefix("tcp:") else { return nil }
                    return PortForwardEntry(serial: String(fields[0]), local: local, remote: remote)
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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.caption.weight(.medium))
                .foregroundColor(.secondary)
            TextField("8080", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)
        }
    }
}

// MARK: - Utilities
