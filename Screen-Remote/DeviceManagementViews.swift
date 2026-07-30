import AppKit
import SwiftUI

private let managementCardColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let managementCardGridMaxWidth: CGFloat = 914

extension Notification.Name {
    static let screenRemoteRefreshManagement = Notification.Name("screenRemoteRefreshManagement")
}

struct ManagementTarget {
    let device: Device
    let serial: String
    let adbPath: String
}

@MainActor
func managementTarget(from appState: AppState) -> ManagementTarget? {
    guard appState.devices.indices.contains(appState.selectedDevice) else { return nil }
    let device = appState.devices[appState.selectedDevice]
    let session = appState.screenSessions.session(for: device.id)
    guard session.isConnected, !session.adbSerial.isEmpty else { return nil }
    return ManagementTarget(device: device, serial: session.adbSerial, adbPath: appState.adbPath)
}

private struct ManagementCommandOutput {
    let status: Int32
    let data: Data
    let error: String
    let timedOut: Bool

    var text: String { String(decoding: data, as: UTF8.self) }
    var succeeded: Bool { status == 0 && !timedOut }
    var failureDetail: String {
        if timedOut { return String.localizedKey("managementCommandTimedOut") }
        let stderr = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : stderr
    }
}

private enum ManagementADB {
    static func run(
        target: ManagementTarget,
        arguments: [String],
        timeout: TimeInterval = 20
    ) async throws -> ManagementCommandOutput {
        guard FileManager.default.isExecutableFile(atPath: target.adbPath) else {
            throw ManagementError.message(String.localizedKey("managementADBMissing"))
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: target.adbPath)
                process.arguments = ["-s", target.serial] + arguments
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                let lock = NSLock()
                var didTimeOut = false
                do {
                    try process.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard process.isRunning else { return }
                        didTimeOut = true
                        process.terminate()
                    }
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let error = String(decoding: errorData, as: UTF8.self)
                    lock.lock()
                    let timedOut = didTimeOut
                    lock.unlock()
                    continuation.resume(returning: ManagementCommandOutput(
                        status: process.terminationStatus,
                        data: data,
                        error: error,
                        timedOut: timedOut
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func shell(
        target: ManagementTarget,
        command: String,
        timeout: TimeInterval = 20
    ) async throws -> String {
        let output = try await run(target: target, arguments: ["shell", command], timeout: timeout)
        guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
        return output.text
    }

    static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

private enum ManagementError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

struct ManagementUnavailableView: View {
    var body: some View {
        ContentUnavailableViewCompat(
            icon: "cable.connector",
            title: "managementSessionRequiredTitle",
            detail: "managementSessionRequiredDetail"
        )
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct ManagementErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundColor(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appBackground(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Files

private struct RemoteFileEntry: Identifiable {
    let name: String
    let isDirectory: Bool
    var id: String { name }
}

private struct RemoteDirectoryColumn: Identifiable {
    let path: String
    var entries: [RemoteFileEntry] = []
    var isLoading = true
    var errorMessage: String?
    var id: String { path }
}

private struct RemoteFileSelection: Identifiable {
    let entry: RemoteFileEntry
    let basePath: String
    var id: String { basePath == "/" ? "/\(entry.name)" : "\(basePath)/\(entry.name)" }
}

struct DeviceFilesView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var path = "/sdcard"
    @State private var columns: [RemoteDirectoryColumn] = []
    @State private var selectedPaths: [String: String] = [:]
    @State private var selectedFile: RemoteFileSelection?
    @State private var selectedEntries: [String: RemoteFileSelection] = [:]
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var maximumColumnCount = 1
    @State private var availableBrowserWidth: CGFloat = 0

    private let minimumColumnWidth: CGFloat = 300
    private let absoluteMaximumColumnCount = 3

    private var activeDirectoryPath: String { columns.last?.path ?? path }
    private var visibleDirectoryColumns: [RemoteDirectoryColumn] {
        let detailColumnCount = selectedFile == nil ? 0 : 1
        let availableDirectoryColumns = max(0, maximumColumnCount - detailColumnCount)
        return Array(columns.suffix(availableDirectoryColumns))
    }

    var body: some View {
        Group {
            if managementTarget(from: appState) == nil {
                ManagementUnavailableView()
            } else {
                VStack(spacing: 0) {
                    fileToolbar
                    Divider()
                    if let errorMessage {
                        ManagementErrorBanner(message: errorMessage).padding(.horizontal, 18).padding(.top, 12)
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            ForEach(visibleDirectoryColumns) { column in
                                directoryColumn(column)
                                    .frame(width: minimumColumnWidth)
                                if column.id != visibleDirectoryColumns.last?.id || selectedFile != nil {
                                    Divider().frame(maxHeight: .infinity)
                                }
                            }
                            if let selectedFile {
                                fileDetailColumn(selectedFile)
                                    .frame(width: minimumColumnWidth)
                            }
                        }
                        .frame(minWidth: proxy.size.width, alignment: .leading)
                        .frame(maxHeight: .infinity)
                        .onAppear { updateColumnLimit(for: proxy.size.width) }
                        .onChange(of: proxy.size.width) { width in updateColumnLimit(for: width) }
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: appState.selectedDevice) { _ in path = "/sdcard"; refresh() }
        .onChange(of: managementTarget(from: appState)?.serial ?? "") { serial in if !serial.isEmpty { refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .screenRemoteRefreshManagement)) { _ in refresh() }
    }

    private func directoryColumn(_ column: RemoteDirectoryColumn) -> some View {
        VStack(spacing: 0) {
            if column.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = column.errorMessage {
                ManagementErrorBanner(message: errorMessage).padding(14)
                Spacer()
            }
            else {
                GeometryReader { proxy in
                    let visibleEntries = filteredEntries(in: column)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleEntries) { entry in
                                let fullPath = remotePath(entry, in: column.path)
                                RemoteFileRow(
                                    entry: entry,
                                    isSelected: selectedPaths[column.path] == fullPath || selectedFile?.id == fullPath,
                                    isBatchSelected: selectedEntries[fullPath] != nil,
                                    select: { select(entry, in: column) },
                                    toggleSelection: { toggleSelection(entry, in: column.path) },
                                    open: { select(entry, in: column) },
                                    download: { download(entry, in: column.path) },
                                    delete: { delete(entry, in: column.path) }
                                )
                                Divider().padding(.leading, 48)
                            }
                            Color.clear
                                .frame(
                                    height: max(
                                        1,
                                        proxy.size.height - CGFloat(visibleEntries.count * 45) - 20
                                    )
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard column.path != activeDirectoryPath else { return }
                                    activateDirectoryColumn(column)
                                }
                        }
                        .padding(10)
                    }
                }
            }
        }
    }

    private func fileDetailColumn(_ selection: RemoteFileSelection) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 24)
            Image(systemName: "doc.fill").font(.system(size: 42)).foregroundColor(.secondary)
            Text(selection.entry.name).font(.headline).multilineTextAlignment(.center).lineLimit(3)
            VStack(spacing: 8) {
                HStack { Text("managementFileType").foregroundColor(.secondary); Spacer(); Text("managementFile") }
                HStack(alignment: .top) {
                    Text("managementFilePath").foregroundColor(.secondary)
                    Spacer()
                    Text(selection.id).font(.system(.caption, design: .monospaced)).multilineTextAlignment(.trailing)
                }
            }
            .font(.subheadline)
            .padding(14)
            .appCard()
            HStack {
                Button("managementDownload") { download(selection.entry, in: selection.basePath) }
                Button("managementDelete") { delete(selection.entry, in: selection.basePath) }
            }
            Spacer()
        }
        .padding(18)
    }

    private var fileToolbar: some View {
        Group {
            if availableBrowserWidth > 0 && availableBrowserWidth < 520 {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        addressControls
                        Spacer()
                        fileTools
                    }
                    PageSearchField(searchText: $searchText, searchPrompt: "managementSearchFiles", expands: true)
                }
            } else {
                HStack(spacing: 12) {
                    addressControls
                    Spacer(minLength: 12)
                    fileTools
                    Spacer(minLength: 12)
                    PageSearchField(searchText: $searchText, searchPrompt: "managementSearchFiles", expands: false)
                }
            }
        }
        .padding(isCompact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addressControls: some View {
        HStack(spacing: 10) {
            Button(action: navigateUp) { Image(systemName: "chevron.up") }.disabled(activeDirectoryPath == "/")
            Text(activeDirectoryPath)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var fileTools: some View {
        HStack(spacing: 10) {
            if !selectedEntries.isEmpty {
                Button(action: downloadSelectedEntries) { Image(systemName: "square.and.arrow.down") }
                    .help("managementDownloadSelected")
                Button(action: deleteSelectedEntries) { Image(systemName: "trash") }
                    .help("managementDeleteSelected")
            }
            Button(action: createFolder) { Image(systemName: "folder.badge.plus") }.help("managementNewFolder")
            Button(action: upload) { Image(systemName: "square.and.arrow.up") }.help("managementUpload")
        }
    }

    private func refresh() {
        guard let target = managementTarget(from: appState) else { return }
        errorMessage = nil
        selectedPaths = [:]
        selectedFile = nil
        selectedEntries = [:]
        columns = [RemoteDirectoryColumn(path: path)]
        loadColumn(path: path, target: target)
    }

    private func remotePath(_ entry: RemoteFileEntry, in basePath: String? = nil) -> String {
        let basePath = basePath ?? path
        return basePath == "/" ? "/\(entry.name)" : "\(basePath)/\(entry.name)"
    }

    private func select(_ entry: RemoteFileEntry, in column: RemoteDirectoryColumn) {
        guard let columnIndex = columns.firstIndex(where: { $0.id == column.id }) else { return }
        let fullPath = remotePath(entry, in: column.path)
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            toggleSelection(entry, in: column.path)
            return
        }
        selectedEntries = [fullPath: RemoteFileSelection(entry: entry, basePath: column.path)]
        selectedPaths[column.path] = fullPath
        columns = Array(columns.prefix(columnIndex + 1))
        selectedFile = nil
        if entry.isDirectory {
            path = fullPath
            columns.append(RemoteDirectoryColumn(path: fullPath))
            guard let target = managementTarget(from: appState) else { return }
            loadColumn(path: fullPath, target: target)
        } else {
            path = column.path
            selectedFile = RemoteFileSelection(entry: entry, basePath: column.path)
        }
    }

    private func toggleSelection(_ entry: RemoteFileEntry, in basePath: String) {
        let selection = RemoteFileSelection(entry: entry, basePath: basePath)
        if selectedEntries[selection.id] == nil {
            selectedEntries[selection.id] = selection
        } else {
            selectedEntries.removeValue(forKey: selection.id)
        }
    }

    private func activateDirectoryColumn(_ column: RemoteDirectoryColumn) {
        guard column.path != activeDirectoryPath,
              let index = columns.firstIndex(where: { $0.id == column.id }) else { return }
        columns = Array(columns.prefix(index + 1))
        path = column.path
        selectedFile = nil
        selectedPaths = selectedPaths.filter { key, _ in columns.contains(where: { $0.path == key }) }
        searchText = ""
    }

    private func updateColumnLimit(for availableWidth: CGFloat) {
        availableBrowserWidth = availableWidth
        let dividerWidth: CGFloat = 1
        let fittingCount = Int((availableWidth + dividerWidth) / (minimumColumnWidth + dividerWidth))
        maximumColumnCount = min(absoluteMaximumColumnCount, max(1, fittingCount))
    }

    private func navigateUp() {
        if selectedFile != nil {
            selectedFile = nil
            path = columns.last?.path ?? path
            return
        }
        if columns.count > 1 {
            let removedColumn = columns.removeLast()
            selectedPaths.removeValue(forKey: columns.last?.path ?? removedColumn.path)
            path = columns.last?.path ?? path
            searchText = ""
            return
        }
        let current = activeDirectoryPath
        guard current != "/" else { return }
        path = (current as NSString).deletingLastPathComponent
        if path.isEmpty { path = "/" }
        refresh()
    }

    private func filteredEntries(in column: RemoteDirectoryColumn) -> [RemoteFileEntry] {
        guard column.path == activeDirectoryPath, !searchText.isEmpty else { return column.entries }
        return column.entries.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func download(_ entry: RemoteFileEntry, in basePath: String? = nil) {
        guard let target = managementTarget(from: appState) else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = entry.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await runFileADB(target: target, arguments: ["pull", remotePath(entry, in: basePath), url.path], logAction: "download") }
    }

    private func downloadSelectedEntries() {
        guard let target = managementTarget(from: appState), !selectedEntries.isEmpty else { return }
        let selections = Array(selectedEntries.values)
        if selections.count == 1, let selection = selections.first, !selection.entry.isDirectory {
            download(selection.entry, in: selection.basePath)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String.localizedKey("managementDownloadSelected")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            for selection in selections {
                await runFileADB(
                    target: target,
                    arguments: ["pull", selection.id, destination.path],
                    logAction: "batch download"
                )
            }
        }
    }

    private func deleteSelectedEntries() {
        guard let target = managementTarget(from: appState), !selectedEntries.isEmpty else { return }
        let selections = Array(selectedEntries.values)
        let alert = NSAlert()
        alert.messageText = String.localizedKey("managementDeleteSelected")
        alert.informativeText = String(
            format: String.localizedKey("managementDeleteSelectedConfirmation"),
            selections.count
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String.localizedKey("managementDelete"))
        alert.addButton(withTitle: String.localizedKey("commonCancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let command = "rm -rf " + selections.map { ManagementADB.quote($0.id) }.joined(separator: " ")
        let removesCurrentDirectory = selections.contains { activeDirectoryPath == $0.id || activeDirectoryPath.hasPrefix($0.id + "/") }
        Task {
            do {
                _ = try await ManagementADB.shell(target: target, command: command, timeout: 60)
                selectedEntries = [:]
                selectedFile = nil
                if removesCurrentDirectory, let fallback = selections.first?.basePath {
                    path = fallback
                    refresh()
                } else {
                    for columnPath in columns.map(\.path) { reloadColumn(path: columnPath) }
                }
                appState.appendSDLLog("Remote batch delete completed: \(target.device.name), count=\(selections.count)")
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Remote batch delete failed: \(target.device.name), \(error.localizedDescription)")
            }
        }
    }

    private func upload() {
        guard let target = managementTarget(from: appState) else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let destination = activeDirectoryPath
        Task { await runFileADB(target: target, arguments: ["push", url.path, destination], logAction: "upload"); reloadColumn(path: destination) }
    }

    private func createFolder() {
        guard let target = managementTarget(from: appState) else { return }
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = String.localizedKey("managementFolderName")
        let alert = NSAlert()
        alert.messageText = String.localizedKey("managementNewFolder")
        alert.accessoryView = input
        alert.addButton(withTitle: String.localizedKey("managementCreate"))
        alert.addButton(withTitle: String.localizedKey("commonCancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return }
        Task {
            do {
                let destination = activeDirectoryPath == "/" ? "/\(name)" : "\(activeDirectoryPath)/\(name)"
                _ = try await ManagementADB.shell(target: target, command: "mkdir -p \(ManagementADB.quote(destination))")
                reloadColumn(path: activeDirectoryPath)
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func delete(_ entry: RemoteFileEntry, in basePath: String? = nil) {
        guard let target = managementTarget(from: appState) else { return }
        Task {
            do {
                _ = try await ManagementADB.shell(target: target, command: "rm -rf \(ManagementADB.quote(remotePath(entry, in: basePath)))", timeout: 30)
                selectedFile = nil
                selectedEntries.removeValue(forKey: remotePath(entry, in: basePath))
                reloadColumn(path: basePath ?? activeDirectoryPath)
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func reloadColumn(path: String) {
        guard let target = managementTarget(from: appState), columns.contains(where: { $0.path == path }) else { return }
        if let index = columns.firstIndex(where: { $0.path == path }) {
            columns[index].isLoading = true
            columns[index].errorMessage = nil
        }
        loadColumn(path: path, target: target)
    }

    private func loadColumn(path: String, target: ManagementTarget) {
        Task {
            do {
                let output = try await ManagementADB.shell(
                    target: target,
                    command: "ls -1Ap \(ManagementADB.quote(path))",
                    timeout: 30
                )
                guard let index = columns.firstIndex(where: { $0.path == path }) else { return }
                columns[index].entries = parseRemoteFileEntries(output)
                columns[index].isLoading = false
                columns[index].errorMessage = nil
                appState.appendSDLLog("Remote directory loaded: \(target.device.name), path=\(path), count=\(columns[index].entries.count)")
            } catch {
                guard let index = columns.firstIndex(where: { $0.path == path }) else { return }
                columns[index].isLoading = false
                columns[index].errorMessage = error.localizedDescription
                appState.appendSDLLog("Failed to load remote directory: \(target.device.name), path=\(path), \(error.localizedDescription)")
            }
        }
    }

    private func runFileADB(target: ManagementTarget, arguments: [String], logAction: String) async {
        do {
            let output = try await ManagementADB.run(target: target, arguments: arguments, timeout: 120)
            guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
            appState.appendSDLLog("Remote file \(logAction) completed: \(target.device.name)")
        } catch {
            errorMessage = error.localizedDescription
            appState.appendSDLLog("Remote file \(logAction) failed: \(target.device.name), \(error.localizedDescription)")
        }
    }
}

private func parseRemoteFileEntries(_ output: String) -> [RemoteFileEntry] {
    output.split(whereSeparator: \.isNewline).compactMap { raw in
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "./", value != "../" else { return nil }
        let isDirectory = value.hasSuffix("/")
        return RemoteFileEntry(name: isDirectory ? String(value.dropLast()) : value, isDirectory: isDirectory)
    }.sorted { lhs, rhs in
        lhs.isDirectory != rhs.isDirectory
            ? lhs.isDirectory
            : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

private struct RemoteFileRow: View {
    let entry: RemoteFileEntry
    let isSelected: Bool
    let isBatchSelected: Bool
    let select: () -> Void
    let toggleSelection: () -> Void
    let open: () -> Void
    let download: () -> Void
    let delete: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isBatchSelected },
                    set: { _ in toggleSelection() }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill").foregroundColor(entry.isDirectory ? .blue : .secondary).frame(width: 24)
            Text(entry.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(action: open) { Image(systemName: entry.isDirectory ? "chevron.right" : "square.and.arrow.down") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill((isSelected || isBatchSelected) ? AppTheme.accent.opacity(0.1) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onTapGesture(count: 2, perform: open)
        .contextMenu {
            Button("managementDownload", action: download).disabled(entry.isDirectory)
            Button("managementDelete", action: delete)
        }
    }
}

// MARK: - Processes

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

private enum DeviceUtilitySheet: String, Identifiable {
    case fixedPort
    case screenshot
    case reboot
    case activation
    case density
    case resolution
    case animation
    case standby

    var id: String { rawValue }
}

private struct DeviceUtilityItem: Identifiable {
    let sheet: DeviceUtilitySheet
    let title: LocalizedStringKey
    let icon: String
    let detail: String

    var id: DeviceUtilitySheet { sheet }
}

private struct DeviceUtilitySnapshot {
    var wirelessPort = ""
    var density = ""
    var resolutionWidth = ""
    var resolutionHeight = ""
    var windowAnimationScale = "1.0"
    var transitionAnimationScale = "1.0"
    var animatorDurationScale = "1.0"
    var installedActivationPackages: Set<String> = []
}

private struct DeviceActivationTarget: Identifiable {
    let id: String
    let title: String
    let command: String
}

struct DeviceUtilitiesView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var isBusy = false
    @State private var isRefreshing = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var activeSheet: DeviceUtilitySheet?
    @State private var snapshot = DeviceUtilitySnapshot()
    @State private var fixedPort = "5555"
    @State private var density = ""
    @State private var resolutionWidth = ""
    @State private var resolutionHeight = ""
    @State private var windowAnimationScale = "1.0"
    @State private var transitionAnimationScale = "1.0"
    @State private var animatorDurationScale = "1.0"
    @State private var screenshotURL: URL?

    private var actions: [DeviceUtilityItem] {
        [
            DeviceUtilityItem(
                sheet: .fixedPort,
                title: "managementFixedPort",
                icon: "wifi",
                detail: snapshot.wirelessPort.isEmpty
                    ? String.localizedKey("managementFixedPortDetail")
                    : String(format: String.localizedKey("managementCurrentPort"), snapshot.wirelessPort)
            ),
            DeviceUtilityItem(
                sheet: .screenshot,
                title: "managementScreenshot",
                icon: "camera",
                detail: String.localizedKey("managementScreenshotPreviewDetail")
            ),
            DeviceUtilityItem(
                sheet: .reboot,
                title: "managementAdvancedReboot",
                icon: "restart",
                detail: String.localizedKey("managementAdvancedRebootDetail")
            ),
            DeviceUtilityItem(
                sheet: .activation,
                title: "managementActivateApp",
                icon: "checkmark.shield",
                detail: String.localizedKey("managementActivateAppDetail")
            ),
            DeviceUtilityItem(
                sheet: .density,
                title: "managementChangeDensity",
                icon: "textformat.size",
                detail: snapshot.density.isEmpty
                    ? String.localizedKey("managementChangeDensityDetail")
                    : String(format: String.localizedKey("managementCurrentDensity"), snapshot.density)
            ),
            DeviceUtilityItem(
                sheet: .resolution,
                title: "managementChangeResolution",
                icon: "rectangle.arrowtriangle.2.outward",
                detail: snapshot.resolutionWidth.isEmpty
                    ? String.localizedKey("managementChangeResolutionDetail")
                    : String(format: String.localizedKey("managementCurrentResolution"), snapshot.resolutionWidth, snapshot.resolutionHeight)
            ),
            DeviceUtilityItem(
                sheet: .animation,
                title: "managementAnimationScale",
                icon: "slider.horizontal.3",
                detail: String.localizedKey("managementAnimationScaleDetail")
            ),
            DeviceUtilityItem(
                sheet: .standby,
                title: "managementStandby",
                icon: "moon.zzz",
                detail: String.localizedKey("managementStandbyActionsDetail")
            )
        ]
    }

    var body: some View {
        ScrollView {
            if managementTarget(from: appState) == nil { ManagementUnavailableView() }
            else {
                VStack(alignment: .leading, spacing: 16) {
                    if isBusy || isRefreshing { ProgressView().frame(maxWidth: .infinity) }
                    if let errorMessage { ManagementErrorBanner(message: errorMessage) }
                    if let resultMessage {
                        Label(resultMessage, systemImage: "checkmark.circle.fill").foregroundColor(.green).padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading).appCard()
                    }
                    LazyVGrid(columns: managementCardColumns, alignment: .center, spacing: 14) {
                        ForEach(actions) { action in
                            Button { present(action.sheet) } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: action.icon).font(.title3).foregroundColor(AppTheme.accent).frame(width: 38, height: 38)
                                        .appBackground(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(action.title).font(.headline)
                                        Text(action.detail).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                }.padding(14).appCard(radius: 12)
                            }.buttonStyle(.plain).disabled(isBusy)
                        }
                    }
                    .frame(maxWidth: managementCardGridMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                }.padding(isCompact ? 20 : 28)
            }
        }
        .onAppear(perform: refreshSnapshot)
        .onChange(of: appState.selectedDevice) { _ in refreshSnapshot() }
        .onChange(of: managementTarget(from: appState)?.serial ?? "") { serial in
            if !serial.isEmpty { refreshSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenRemoteRefreshManagement)) { _ in
            refreshSnapshot()
        }
        .sheet(item: $activeSheet) { sheet in
            utilitySheet(sheet)
                .environment(\.locale, appState.resolvedLocale)
        }
    }

    private func present(_ sheet: DeviceUtilitySheet) {
        resultMessage = nil
        errorMessage = nil
        switch sheet {
        case .fixedPort:
            fixedPort = snapshot.wirelessPort.isEmpty ? "5555" : snapshot.wirelessPort
        case .density:
            density = snapshot.density
        case .resolution:
            resolutionWidth = snapshot.resolutionWidth
            resolutionHeight = snapshot.resolutionHeight
        case .animation:
            windowAnimationScale = snapshot.windowAnimationScale
            transitionAnimationScale = snapshot.transitionAnimationScale
            animatorDurationScale = snapshot.animatorDurationScale
        case .screenshot:
            captureScreenshot()
            return
        default:
            break
        }
        activeSheet = sheet
    }

    @ViewBuilder
    private func utilitySheet(_ sheet: DeviceUtilitySheet) -> some View {
        VStack(spacing: 0) {
            UtilitySheetHeader(title: sheetTitle(sheet)) { activeSheet = nil }
            Divider()
            Group {
                switch sheet {
                case .fixedPort: fixedPortSheet
                case .screenshot: screenshotSheet
                case .reboot: rebootSheet
                case .activation: activationSheet
                case .density: densitySheet
                case .resolution: resolutionSheet
                case .animation: animationSheet
                case .standby: standbySheet
                }
            }
            .padding(20)
        }
        .frame(width: min(500, max(420, appState.appWindowWidth * 0.62)))
        .background(AppTheme.background)
    }

    private func sheetTitle(_ sheet: DeviceUtilitySheet) -> LocalizedStringKey {
        switch sheet {
        case .fixedPort: "managementFixedPort"
        case .screenshot: "managementScreenshotReady"
        case .reboot: "managementAdvancedReboot"
        case .activation: "managementActivateApp"
        case .density: "managementChangeDensity"
        case .resolution: "managementChangeResolution"
        case .animation: "managementAnimationScale"
        case .standby: "managementStandby"
        }
    }

    private var fixedPortSheet: some View {
        UtilityForm(
            detail: "managementFixedPortWarning",
            primaryTitle: "managementApply",
            primaryEnabled: validPort != nil && fixedPort != snapshot.wirelessPort,
            primaryAction: { runFixedPort() }
        ) {
            UtilityTextField(title: "managementDevicePort", text: $fixedPort)
        }
    }

    private var densitySheet: some View {
        UtilityForm(
            detail: "managementChangeDensityDetail",
            primaryTitle: "managementApply",
            primaryEnabled: validDensity != nil && density != snapshot.density,
            primaryAction: { runShellAction("density", command: "wm density \(validDensity!)", refreshAfter: true) },
            secondaryTitle: "managementReset",
            secondaryAction: { runShellAction("densityReset", command: "wm density reset", refreshAfter: true) }
        ) {
            UtilityTextField(title: "managementDensityValue", text: $density)
        }
    }

    private var resolutionSheet: some View {
        UtilityForm(
            detail: "managementChangeResolutionDetail",
            primaryTitle: "managementApply",
            primaryEnabled: validResolution != nil && (
                resolutionWidth != snapshot.resolutionWidth ||
                resolutionHeight != snapshot.resolutionHeight
            ),
            primaryAction: {
                guard let size = validResolution else { return }
                runShellAction("resolution", command: "wm size \(size.0)x\(size.1)", refreshAfter: true)
            },
            secondaryTitle: "managementReset",
            secondaryAction: { runShellAction("resolutionReset", command: "wm size reset", refreshAfter: true) }
        ) {
            HStack(spacing: 12) {
                UtilityTextField(title: "managementWidth", text: $resolutionWidth)
                UtilityTextField(title: "managementHeight", text: $resolutionHeight)
            }
        }
    }

    private var animationSheet: some View {
        UtilityForm(
            detail: "managementAnimationScaleDetail",
            primaryTitle: "managementApply",
            primaryEnabled: validAnimationScales != nil && (
                windowAnimationScale != snapshot.windowAnimationScale ||
                transitionAnimationScale != snapshot.transitionAnimationScale ||
                animatorDurationScale != snapshot.animatorDurationScale
            ),
            primaryAction: {
                guard let scales = validAnimationScales else { return }
                let command = "settings put global window_animation_scale \(scales.0); settings put global transition_animation_scale \(scales.1); settings put global animator_duration_scale \(scales.2)"
                runShellAction("animationScale", command: command, refreshAfter: true)
            }
        ) {
            UtilityTextField(title: "managementWindowAnimationScale", text: $windowAnimationScale)
            UtilityTextField(title: "managementTransitionAnimationScale", text: $transitionAnimationScale)
            UtilityTextField(title: "managementAnimatorDurationScale", text: $animatorDurationScale)
        }
    }

    private var rebootSheet: some View {
        UtilityOptionList(detail: "managementAdvancedRebootWarning") {
            UtilityOptionButton(title: "managementRestart", icon: "restart") { runReboot(mode: "normal") }
            UtilityOptionButton(title: "managementPowerOff", icon: "power", isDestructive: true) { runReboot(mode: "powerOff") }
            UtilityOptionButton(title: "managementRecovery", icon: "cross.case", isDestructive: true) { runReboot(mode: "recovery") }
            UtilityOptionButton(title: "managementFastboot", icon: "terminal", isDestructive: true) { runReboot(mode: "fastboot") }
        }
    }

    private var standbySheet: some View {
        UtilityOptionList(detail: "managementStandbyActionsDetail") {
            UtilityOptionButton(title: "managementSleep", icon: "moon.zzz") {
                runShellAction("sleep", command: "input keyevent 223")
            }
            UtilityOptionButton(title: "managementWake", icon: "sun.max") {
                runShellAction("wake", command: "input keyevent 224")
            }
        }
    }

    private var activationSheet: some View {
        UtilityOptionList(detail: "managementActivateAppDetail") {
            ForEach(activationTargets) { target in
                UtilityOptionButton(
                    titleText: target.title,
                    icon: "checkmark.shield",
                    badge: snapshot.installedActivationPackages.contains(target.id)
                        ? String.localizedKey("managementInstalled")
                        : String.localizedKey("managementNotInstalled"),
                    enabled: snapshot.installedActivationPackages.contains(target.id)
                ) {
                    runShellAction("activate:\(target.id)", command: target.command)
                }
            }
        }
    }

    @ViewBuilder
    private var screenshotSheet: some View {
        if let screenshotURL, let image = NSImage(contentsOf: screenshotURL) {
            VStack(alignment: .leading, spacing: 16) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 420)
                    .appBackground(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("managementOpen") { NSWorkspace.shared.open(screenshotURL) }
                    Spacer()
                    Button("commonSave") { saveScreenshot(screenshotURL) }.keyboardShortcut(.defaultAction)
                }
            }
        } else {
            ManagementErrorBanner(message: String.localizedKey("managementScreenshotFailed"))
        }
    }

    private var validPort: Int? {
        guard let port = Int(fixedPort), (1024...65535).contains(port) else { return nil }
        return port
    }

    private var validDensity: Int? {
        guard let value = Int(density), (72...1000).contains(value) else { return nil }
        return value
    }

    private var validResolution: (Int, Int)? {
        guard let width = Int(resolutionWidth), let height = Int(resolutionHeight),
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private var validAnimationScales: (String, String, String)? {
        let values = [windowAnimationScale, transitionAnimationScale, animatorDurationScale]
        guard values.allSatisfy({ Double($0).map { $0 >= 0 } == true }) else { return nil }
        return (values[0], values[1], values[2])
    }

    private var activationTargets: [DeviceActivationTarget] {
        [
            DeviceActivationTarget(
                id: "moe.shizuku.privileged.api",
                title: "Shizuku",
                command: "$(pm path moe.shizuku.privileged.api | sed \"s#package:##;s#/base.apk#/lib/$(getprop ro.product.cpu.abi | sed \\\"s/arm64-v8a/arm64/\\\")/libshizuku.so#\")"
            ),
            DeviceActivationTarget(
                id: "me.piebridge.brevent",
                title: "Brevent",
                command: "sh /data/data/me.piebridge.brevent/brevent.sh"
            ),
            DeviceActivationTarget(
                id: "com.catchingnow.icebox",
                title: "Ice Box",
                command: "sh /storage/emulated/0/Android/data/com.catchingnow.icebox/files/start.sh"
            )
        ]
    }

    private func refreshSnapshot() {
        guard let target = managementTarget(from: appState), !isRefreshing else { return }
        isRefreshing = true
        Task {
            do {
                let command = """
                echo PORT=$(getprop service.adb.tcp.port); \
                echo DENSITY=$(wm density | tail -n 1 | sed 's/.*: //'); \
                echo SIZE=$(wm size | tail -n 1 | sed 's/.*: //'); \
                echo WINDOW=$(settings get global window_animation_scale); \
                echo TRANSITION=$(settings get global transition_animation_scale); \
                echo ANIMATOR=$(settings get global animator_duration_scale); \
                pm list packages | grep -E '^package:(moe.shizuku.privileged.api|me.piebridge.brevent|com.catchingnow.icebox)$' || true
                """
                snapshot = parseUtilitySnapshot(try await ManagementADB.shell(target: target, command: command))
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Failed to load device utility state: \(target.device.name), \(error.localizedDescription)")
            }
            isRefreshing = false
        }
    }

    private func captureScreenshot() {
        guard let target = managementTarget(from: appState) else { return }
        isBusy = true
        resultMessage = nil
        errorMessage = nil
        Task {
            let identifier = UUID().uuidString.lowercased()
            let remotePath = "/data/local/tmp/screen_remote_screenshot_\(identifier).png"
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Screen-Remote-\(identifier).png")
            do {
                _ = try? await ManagementADB.run(
                    target: target,
                    arguments: ["shell", "rm", "-f", remotePath]
                )
                let capture = try await ManagementADB.run(
                    target: target,
                    arguments: ["shell", "screencap", "-p", remotePath],
                    timeout: 30
                )
                guard capture.succeeded else {
                    throw ManagementError.message(capture.failureDetail)
                }
                let pull = try await ManagementADB.run(
                    target: target,
                    arguments: ["pull", remotePath, localURL.path],
                    timeout: 30
                )
                guard pull.succeeded,
                      let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path),
                      (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0,
                      NSImage(contentsOf: localURL) != nil else {
                    throw ManagementError.message(
                        pull.succeeded ? String.localizedKey("managementScreenshotFailed") : pull.failureDetail
                    )
                }
                _ = try? await ManagementADB.run(
                    target: target,
                    arguments: ["shell", "rm", "-f", remotePath]
                )
                screenshotURL = localURL
                activeSheet = .screenshot
                appState.appendSDLLog("Device screenshot captured: \(target.device.name)")
            } catch {
                _ = try? await ManagementADB.run(
                    target: target,
                    arguments: ["shell", "rm", "-f", remotePath]
                )
                try? FileManager.default.removeItem(at: localURL)
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Device screenshot failed: \(target.device.name), \(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    private func saveScreenshot(_ sourceURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Screen Remote.png"
        panel.allowedFileTypes = ["png"]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            activeSheet = nil
            resultMessage = String.localizedKey("managementScreenshotSaved")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runFixedPort() {
        guard let target = managementTarget(from: appState), let port = validPort else { return }
        activeSheet = nil
        isBusy = true
        Task {
            do {
                let output = try await ManagementADB.run(target: target, arguments: ["tcpip", String(port)])
                guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
                resultMessage = String(format: String.localizedKey("managementFixedPortApplied"), port)
                appState.appendSDLLog("Wireless debugging port changed: \(target.device.name), port=\(port)")
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Failed to change wireless debugging port: \(target.device.name), \(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    private func runReboot(mode: String) {
        guard let target = managementTarget(from: appState) else { return }
        activeSheet = nil
        isBusy = true
        Task {
            do {
                let output: ManagementCommandOutput
                switch mode {
                case "powerOff":
                    output = try await ManagementADB.run(target: target, arguments: ["shell", "reboot", "-p"])
                case "recovery":
                    output = try await ManagementADB.run(target: target, arguments: ["reboot", "recovery"])
                case "fastboot":
                    output = try await ManagementADB.run(target: target, arguments: ["reboot", "bootloader"])
                default:
                    output = try await ManagementADB.run(target: target, arguments: ["reboot"])
                }
                guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
                resultMessage = String.localizedKey("managementCommandSent")
                appState.appendSDLLog("Device reboot command sent: \(target.device.name), mode=\(mode)")
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Device reboot command failed: \(target.device.name), mode=\(mode), \(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    private func runShellAction(_ action: String, command: String, refreshAfter: Bool = false) {
        guard let target = managementTarget(from: appState) else { return }
        activeSheet = nil
        isBusy = true
        resultMessage = nil
        errorMessage = nil
        Task {
            do {
                _ = try await ManagementADB.shell(target: target, command: command)
                resultMessage = String.localizedKey("managementActionCompleted")
                appState.appendSDLLog("Device utility completed: \(target.device.name), action=\(action)")
                if refreshAfter { refreshSnapshot() }
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Device utility failed: \(target.device.name), action=\(action), \(error.localizedDescription)")
            }
            isBusy = false
        }
    }
}

private func parseUtilitySnapshot(_ output: String) -> DeviceUtilitySnapshot {
    var values: [String: String] = [:]
    var packages: Set<String> = []
    for rawLine in output.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("package:") {
            packages.insert(String(line.dropFirst("package:".count)))
        } else if let separator = line.firstIndex(of: "=") {
            values[String(line[..<separator])] = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    let size = (values["SIZE"] ?? "").split(separator: "x", maxSplits: 1).map(String.init)
    return DeviceUtilitySnapshot(
        wirelessPort: (values["PORT"] ?? "").replacingOccurrences(of: "-1", with: ""),
        density: values["DENSITY"] ?? "",
        resolutionWidth: size.first ?? "",
        resolutionHeight: size.count > 1 ? size[1] : "",
        windowAnimationScale: values["WINDOW"] ?? "1.0",
        transitionAnimationScale: values["TRANSITION"] ?? "1.0",
        animatorDurationScale: values["ANIMATOR"] ?? "1.0",
        installedActivationPackages: packages
    )
}

private struct UtilitySheetHeader: View {
    let title: LocalizedStringKey
    let close: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.title2.bold())
            Spacer()
            Button(action: close) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("commonCancel")
        }
        .padding(20)
    }
}

private struct UtilityForm<Content: View>: View {
    let detail: LocalizedStringKey
    let primaryTitle: LocalizedStringKey
    let primaryEnabled: Bool
    let primaryAction: () -> Void
    var secondaryTitle: LocalizedStringKey?
    var secondaryAction: (() -> Void)?
    let content: Content

    init(
        detail: LocalizedStringKey,
        primaryTitle: LocalizedStringKey,
        primaryEnabled: Bool,
        primaryAction: @escaping () -> Void,
        secondaryTitle: LocalizedStringKey? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.detail = detail
        self.primaryTitle = primaryTitle
        self.primaryEnabled = primaryEnabled
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(detail).font(.subheadline).foregroundColor(.secondary)
            content
            HStack {
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                }
                Spacer()
                Button(primaryTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!primaryEnabled)
            }
        }
    }
}

private struct UtilityTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField("", text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

private struct UtilityOptionList<Content: View>: View {
    let detail: LocalizedStringKey
    let content: Content

    init(detail: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(detail).font(.subheadline).foregroundColor(.secondary)
            VStack(spacing: 8) { content }
        }
    }
}

private struct UtilityOptionButton: View {
    let title: LocalizedStringKey?
    let titleText: String?
    let icon: String
    var badge: String?
    var enabled = true
    var isDestructive = false
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        icon: String,
        badge: String? = nil,
        enabled: Bool = true,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.titleText = nil
        self.icon = icon
        self.badge = badge
        self.enabled = enabled
        self.isDestructive = isDestructive
        self.action = action
    }

    init(
        titleText: String,
        icon: String,
        badge: String? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.titleText = titleText
        self.icon = icon
        self.badge = badge
        self.enabled = enabled
        self.isDestructive = false
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22)
                if let title { Text(title) }
                else if let titleText { Text(titleText) }
                Spacer()
                if let badge {
                    Text(badge).font(.caption2).foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .appBackground(Color.primary.opacity(0.06), in: Capsule())
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .appCard(radius: 12)
        }
        .buttonStyle(.plain)
        .foregroundColor(isDestructive ? .red : .primary)
        .disabled(!enabled)
    }
}
