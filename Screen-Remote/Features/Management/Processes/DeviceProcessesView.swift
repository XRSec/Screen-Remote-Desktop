import AppKit
import SwiftUI

private let processListMaxWidth: CGFloat = 914

private struct ManagedProcess: Identifiable {
    let pid: Int
    let rssKilobytes: Int
    let name: String
    var id: Int { pid }
    var packageName: String { name.components(separatedBy: ":").first ?? name }
}

struct DeviceProcessesView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var processes: [ManagedProcess] = []
    @State private var searchText = ""
    @State private var memorySummary = "—"
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filtered: [ManagedProcess] {
        searchText.isEmpty ? processes : processes.filter { $0.name.localizedCaseInsensitiveContains(searchText) || String($0.pid).contains(searchText) }
    }

    var body: some View {
        Group {
            if managementTarget(from: appState) == nil { ManagementUnavailableView() }
            else {
                VStack(spacing: 14) {
                    HStack(spacing: 18) {
                        ProcessSummaryMetric(
                            value: "\(processes.count)",
                            label: "managementRunningApps",
                            icon: "waveform.path.ecg"
                        )
                        Divider().frame(height: 28)
                        ProcessSummaryMetric(
                            value: memorySummary,
                            label: "managementAvailableMemory",
                            icon: "memorychip"
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)

                    PageSearchField(searchText: $searchText, searchPrompt: "managementSearchProcesses", expands: true)
                    if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if let errorMessage { ManagementErrorBanner(message: errorMessage); Spacer() }
                    else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, process in
                                    ProcessRow(process: process, stop: { stop(process) })
                                    if index != filtered.count - 1 {
                                        Divider().padding(.leading, 44)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                                    .fill(Color.primary.opacity(0.02))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                                    .stroke(AppTheme.line, lineWidth: 1)
                            )
                            .frame(maxWidth: processListMaxWidth)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
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
                let output = try await ManagementADB.shell(target: target, command: "ps -A -o PID,RSS,NAME; echo __MEM__; grep -E '^MemTotal:|^MemAvailable:' /proc/meminfo")
                let parts = output.components(separatedBy: "__MEM__")
                processes = parseProcesses(parts.first ?? "")
                memorySummary = parseAvailableMemory(parts.count > 1 ? parts[1] : "")
                appState.appendSDLLog("App processes loaded: \(target.device.name), count=\(processes.count)")
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Failed to load app processes: \(target.device.name), \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    private func stop(_ process: ManagedProcess) {
        guard let target = managementTarget(from: appState) else { return }
        Task {
            do { _ = try await ManagementADB.shell(target: target, command: "am force-stop \(ManagementADB.quote(process.packageName))"); refresh() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private func parseProcesses(_ output: String) -> [ManagedProcess] {
    output.split(whereSeparator: \.isNewline).dropFirst().compactMap { raw in
        let fields = raw.split(maxSplits: 2, whereSeparator: \.isWhitespace)
        guard fields.count == 3, let pid = Int(fields[0]), let rss = Int(fields[1]) else { return nil }
        let name = String(fields[2]); let package = name.components(separatedBy: ":").first ?? name
        guard package.contains("."), !package.contains("/") else { return nil }
        return ManagedProcess(pid: pid, rssKilobytes: rss, name: name)
    }.sorted { $0.rssKilobytes > $1.rssKilobytes }
}

private func parseAvailableMemory(_ output: String) -> String {
    guard let line = output.split(whereSeparator: \.isNewline).first(where: { $0.contains("MemAvailable") }),
          let value = Int(line.split(whereSeparator: \.isWhitespace).dropFirst().first ?? "") else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(value) * 1024, countStyle: .memory)
}

private struct ProcessSummaryMetric: View {
    let value: String
    let label: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppTypography.subheadline)
                .foregroundColor(AppTheme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(AppTypography.subheadline.weight(.semibold))
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct ProcessRow: View {
    let process: ManagedProcess
    let stop: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "app.fill")
                .font(AppTypography.caption)
                .foregroundColor(AppTheme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(AppTypography.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("PID \(process.pid)")
                    .font(AppTypography.monospacedCaption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            Text(ByteCountFormatter.string(
                fromByteCount: Int64(process.rssKilobytes) * 1024,
                countStyle: .memory
            ))
            .font(AppTypography.monospacedCaption)
            .foregroundColor(.secondary)
            .frame(minWidth: 70, alignment: .trailing)

            Button(action: stop) {
                Image(systemName: "stop.circle")
                    .font(AppTypography.caption)
                    .foregroundColor(isHovered ? .red : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("managementForceStop")
            .accessibilityLabel(Text("managementForceStop"))
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(isHovered ? Color.primary.opacity(0.035) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Port forwarding
