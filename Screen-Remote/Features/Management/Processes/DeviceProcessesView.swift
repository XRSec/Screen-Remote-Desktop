import AppKit
import SwiftUI

private let managementCardColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let managementCardGridMaxWidth: CGFloat = 914

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
                    LazyVGrid(columns: managementCardColumns, alignment: .center, spacing: 14) {
                        ProcessStat(value: "\(processes.count)", label: "managementRunningApps", icon: "waveform.path.ecg")
                        ProcessStat(value: memorySummary, label: "managementAvailableMemory", icon: "memorychip")
                    }
                    .frame(maxWidth: managementCardGridMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    PageSearchField(searchText: $searchText, searchPrompt: "managementSearchProcesses", expands: true)
                    if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if let errorMessage { ManagementErrorBanner(message: errorMessage); Spacer() }
                    else {
                        ScrollView {
                            LazyVGrid(columns: managementCardColumns, alignment: .center, spacing: 14) {
                                ForEach(filtered) { process in
                                    ProcessRow(process: process, stop: { stop(process) })
                                }
                            }
                            .frame(maxWidth: managementCardGridMaxWidth)
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

private struct ProcessStat: View {
    let value: String; let label: LocalizedStringKey; let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(AppTheme.accent)
            VStack(alignment: .leading) { Text(value).font(.headline); Text(label).font(.caption).foregroundColor(.secondary) }
            Spacer()
        }.padding(14).frame(maxWidth: .infinity).appCard()
    }
}

private struct ProcessRow: View {
    let process: ManagedProcess; let stop: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.fill").foregroundColor(AppTheme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) { Text(process.name).font(.subheadline.weight(.medium)); Text("PID \(process.pid)").font(.caption).foregroundColor(.secondary) }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(process.rssKilobytes) * 1024, countStyle: .memory)).font(.caption).foregroundColor(.secondary)
            Button(action: stop) { Image(systemName: "stop.circle") }.buttonStyle(.plain).help("managementForceStop")
        }.padding(.horizontal, 14).padding(.vertical, 10).appCard()
    }
}

// MARK: - Port forwarding
