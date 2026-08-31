import AppKit
import SwiftUI

private let managementCardColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let managementCardGridMaxWidth: CGFloat = 914

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

// pi-lens-ignore: type_body_length
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
                                    delete: { confirmDelete(entry, in: column.path) }
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
            Image(systemName: "doc.fill").font(AppTypography.largeTitle).foregroundColor(.secondary)
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
                Button("managementDelete") { confirmDelete(selection.entry, in: selection.basePath) }
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
            Button(action: navigateUp) { Image(systemName: "chevron.up") }
                .help("managementParentFolder")
                .accessibilityLabel(Text("managementParentFolder"))
                .disabled(activeDirectoryPath == "/")
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
                    .accessibilityLabel(Text("managementDownloadSelected"))
                Button(action: deleteSelectedEntries) { Image(systemName: "trash") }
                    .help("managementDeleteSelected")
                    .accessibilityLabel(Text("managementDeleteSelected"))
            }
            Button(action: createFolder) { Image(systemName: "folder.badge.plus") }
                .help("managementNewFolder")
                .accessibilityLabel(Text("managementNewFolder"))
            Button(action: upload) { Image(systemName: "square.and.arrow.up") }
                .help("managementUpload")
                .accessibilityLabel(Text("managementUpload"))
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

    private func confirmDelete(_ entry: RemoteFileEntry, in basePath: String? = nil) {
        let alert = NSAlert()
        alert.messageText = String.localizedKey("managementDelete")
        alert.informativeText = String(
            format: String.localizedKey("managementDeleteConfirmation"),
            entry.name
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String.localizedKey("managementDelete"))
        alert.addButton(withTitle: String.localizedKey("commonCancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        delete(entry, in: basePath)
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
            .accessibilityLabel(Text(entry.name))
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(entry.isDirectory ? .blue : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(entry.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(action: open) {
                Image(systemName: entry.isDirectory ? "chevron.right" : "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isDirectory ? Text("managementOpen") : Text("managementDownload"))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: AppRadius.small).fill((isSelected || isBatchSelected) ? AppTheme.accent.opacity(0.1) : Color.clear))
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
