import AppKit
import SwiftUI

final class SDLLogWindowController: NSWindowController {
    private var hasAppliedInitialSize = false

    init(appState: AppState) {
        let contentView = SDLLogWindowContent(appState: appState)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: MainWindowMetrics.preferredWidth,
                height: MainWindowMetrics.preferredHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String.localizedKey("diagnosticsSDLLogs")
        window.contentMinSize = NSSize(
            width: MainWindowMetrics.minimumWidth,
            height: MainWindowMetrics.minimumHeight
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        if !hasAppliedInitialSize {
            window?.setContentSize(NSSize(
                width: MainWindowMetrics.preferredWidth,
                height: MainWindowMetrics.preferredHeight
            ))
            window?.center()
            hasAppliedInitialSize = true
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SDLLogWindowContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        SDLLogView()
            .environmentObject(appState)
            .environment(\.locale, appState.resolvedLocale)
            .appDismissTextFieldFocusOnTap()
    }
}

struct SDLLogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var selectedTags: Set<SDLLogTag> = []
    @State private var isTagFilterPresented = false
    @State private var isLogAtBottom = true

    private var availableTags: [SDLLogTag] {
        SDLLogTag.allCases.filter { tag in appState.sdlLogs.contains { $0.tag == tag } }
    }

    private var visibleLogs: [SDLLogEntry] {
        appState.sdlLogs.filter { entry in
            (selectedTags.isEmpty || selectedTags.contains(entry.tag))
                && (searchText.isEmpty || entry.line.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var tagFilterTitle: String {
        selectedTags.isEmpty
            ? String.localizedKey("diagnosticsAllTags")
            : String(format: String.localizedKey("diagnosticsSelectedTags"), selectedTags.count)
    }

    private func copy(_ logs: [SDLLogEntry]) {
        let text = logs.map(\.line).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                AppIconTile(symbol: "terminal.fill", color: .appIndigo, size: 40)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("diagnosticsSDLLogs")
                        .font(AppTypography.title)
                    Text("diagnosticsSDLLogsSubtitle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                PageSearchField(
                    searchText: $searchText,
                    searchPrompt: "diagnosticsFilterLogs",
                    expands: false
                )
            }
            .padding(.horizontal, AppSpacing.lg)
            .frame(minHeight: 68)
            .background(AppTheme.surface.opacity(0.72))

            Divider().opacity(0.6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    Button {
                        isTagFilterPresented.toggle()
                    } label: {
                        Label(tagFilterTitle, systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .popover(isPresented: $isTagFilterPresented, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("diagnosticsAllTags").font(.headline)
                                Spacer()
                                Button("diagnosticsClearTags") { selectedTags.removeAll() }
                                    .buttonStyle(.link)
                            }
                            Divider()
                            ForEach(availableTags) { tag in
                                Toggle(tag.rawValue, isOn: Binding(
                                    get: { selectedTags.contains(tag) },
                                    set: { isSelected in
                                        if isSelected { selectedTags.insert(tag) }
                                        else { selectedTags.remove(tag) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(14)
                        .frame(width: 220)
                    }
                    Button("diagnosticsCopy") { copy(visibleLogs) }
                        .disabled(visibleLogs.isEmpty)
                    Button("diagnosticsSelectAll") {
                        NotificationCenter.default.post(name: .screenRemoteSelectAllLogs, object: nil)
                    }
                    .disabled(visibleLogs.isEmpty)
                    Button("diagnosticsRefresh") {
                        selectedTags.removeAll()
                        appState.refreshSDLLogs()
                    }
                    if !isLogAtBottom {
                        Button {
                            NotificationCenter.default.post(name: .screenRemoteScrollLogsToBottom, object: nil)
                        } label: {
                            Label("diagnosticsScrollToBottom", systemImage: "arrow.down.to.line")
                        }
                    }
                    Button("diagnosticsClear") { appState.clearSDLLogs() }
                        .disabled(appState.sdlLogs.isEmpty)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
            }
            .background(AppTheme.surface.opacity(0.5))

            Divider().opacity(0.6)

            ZStack {
                SDLLogTextView(
                    entries: visibleLogs,
                    onScrollPositionChanged: { isAtBottom in
                        if isLogAtBottom != isAtBottom { isLogAtBottom = isAtBottom }
                    },
                    onReachedTop: { appState.loadOlderSDLLogs() }
                )

                if visibleLogs.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(AppTypography.largeTitle)
                            .foregroundColor(Color.white.opacity(0.55))
                        Text("diagnosticsNoSDLLogs")
                            .font(AppTypography.headline)
                            .foregroundColor(Color.white.opacity(0.9))
                        Text("diagnosticsNoSDLLogsDetail")
                            .font(AppTypography.caption)
                            .foregroundColor(Color.white.opacity(0.65))
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .background(AppTheme.background)
    }
}

private struct SDLLogTextView: NSViewRepresentable {
    let entries: [SDLLogEntry]
    let onScrollPositionChanged: (Bool) -> Void
    let onReachedTop: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScrollPositionChanged: onScrollPositionChanged,
            onReachedTop: onReachedTop
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.drawsBackground = true
        textView.backgroundColor = logBackgroundColor
        textView.textColor = logTextColor
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: MainWindowMetrics.preferredWidth,
            height: MainWindowMetrics.preferredHeight
        )

        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = logBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.observe(scrollView: scrollView)
        context.coordinator.observeSelectAll()
        context.coordinator.observeScrollToBottom()
        updateTextView(textView)
        context.coordinator.scrollToBottom()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.textView = textView
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged
        context.coordinator.onReachedTop = onReachedTop
        let shouldFollowBottom = context.coordinator.shouldFollowBottom
        let previousHeight = textView.frame.height
        let previousOriginY = scrollView.contentView.bounds.origin.y
        scrollView.backgroundColor = logBackgroundColor
        updateTextView(textView)
        if shouldFollowBottom {
            context.coordinator.scrollToBottom()
        } else if textView.frame.height > previousHeight {
            let addedHeight = textView.frame.height - previousHeight
            context.coordinator.restoreScrollPosition(verticalOffset: previousOriginY + addedHeight)
        }
    }

    private func updateTextView(_ textView: NSTextView) {
        let content = attributedLogText(entries)
        textView.backgroundColor = logBackgroundColor
        textView.textColor = logTextColor
        guard textView.attributedString() != content else { return }
        let selectedRange = textView.selectedRange()
        textView.textStorage?.setAttributedString(content)
        let selectedLocation = min(selectedRange.location, textView.string.utf16.count)
        textView.setSelectedRange(NSRange(
            location: selectedLocation,
            length: min(selectedRange.length, textView.string.utf16.count - selectedLocation)
        ))

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        layoutManager.ensureLayout(for: textContainer)
        let contentWidth = max(
            textView.enclosingScrollView?.contentSize.width ?? MainWindowMetrics.preferredWidth,
            320
        )
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: max(usedHeight + textView.textContainerInset.height * 2, 1)
        )
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject {
        weak var textView: NSTextView?
        var shouldFollowBottom = true
        var onScrollPositionChanged: (Bool) -> Void
        var onReachedTop: () -> Void
        private var observer: NSObjectProtocol?
        private var scrollObserver: NSObjectProtocol?
        private var bottomObserver: NSObjectProtocol?
        private var isProgrammaticScroll = false

        init(
            onScrollPositionChanged: @escaping (Bool) -> Void,
            onReachedTop: @escaping () -> Void
        ) {
            self.onScrollPositionChanged = onScrollPositionChanged
            self.onReachedTop = onReachedTop
        }

        func observe(scrollView: NSScrollView) {
            guard scrollObserver == nil else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView, !self.isProgrammaticScroll else { return }
                let isAtBottom = self.isAtBottom(scrollView)
                self.shouldFollowBottom = isAtBottom
                self.onScrollPositionChanged(isAtBottom)
                if scrollView.contentView.bounds.origin.y <= 12 {
                    self.onReachedTop()
                }
            }
        }

        func observeSelectAll() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .screenRemoteSelectAllLogs,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.textView?.window?.makeFirstResponder(self?.textView)
                self?.textView?.selectAll(nil)
            }
        }

        func observeScrollToBottom() {
            guard bottomObserver == nil else { return }
            bottomObserver = NotificationCenter.default.addObserver(
                forName: .screenRemoteScrollLogsToBottom,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scrollToBottom()
            }
        }

        func scrollToBottom() {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            shouldFollowBottom = true
            isProgrammaticScroll = true
            textView.scrollToEndOfDocument(nil)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            onScrollPositionChanged(true)
            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticScroll = false
            }
        }

        func restoreScrollPosition(verticalOffset: CGFloat) {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            isProgrammaticScroll = true
            let maximumOriginY = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.setBoundsOrigin(NSPoint(
                x: scrollView.contentView.bounds.origin.x,
                y: min(verticalOffset, maximumOriginY)
            ))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticScroll = false
            }
        }

        private func isAtBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let maximumOriginY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            return scrollView.contentView.bounds.origin.y >= maximumOriginY - 12
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            if let bottomObserver { NotificationCenter.default.removeObserver(bottomObserver) }
        }
    }
}

private let logBackgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
private let logTextColor = NSColor(calibratedWhite: 0.92, alpha: 1)
private let logTimestampColor = NSColor(calibratedWhite: 0.72, alpha: 1)

private func attributedLogText(_ entries: [SDLLogEntry]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: logTextColor
    ]

    for entry in entries {
        let line = entry.line
        let lineStart = result.length
        result.append(NSAttributedString(string: line + "\n", attributes: baseAttributes))

        let timestampLength = (entry.timestamp as NSString).length
        let tagStart = timestampLength + 3
        let tagLength = (entry.tag.rawValue as NSString).length + 2
        let messageStart = timestampLength + 6 + (entry.tag.rawValue as NSString).length
        result.addAttribute(.foregroundColor, value: logTimestampColor, range: NSRange(
            location: lineStart,
            length: timestampLength
        ))
        result.addAttribute(.foregroundColor, value: color(for: entry.tag), range: NSRange(
            location: lineStart + tagStart,
            length: tagLength
        ))
        result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold), range: NSRange(
            location: lineStart + tagStart,
            length: tagLength
        ))

        let messageRange = NSRange(
            location: lineStart + messageStart,
            length: max(0, (line as NSString).length - messageStart)
        )
        highlightKeywords(in: result, range: messageRange)
    }
    return result
}

private func color(for tag: SDLLogTag) -> NSColor {
    switch tag {
    case .scrcpyServer: return .systemPurple
    case .audio: return .systemOrange
    case .video, .render: return NSColor(calibratedRed: 0.25, green: 0.75, blue: 0.95, alpha: 1)
    case .socks, .adb: return .systemBlue
    case .control: return .systemPink
    case .connection, .device: return .systemGreen
    case .apps, .files: return .systemYellow
    case .other: return .systemGray
    }
}

private func highlightKeywords(
    in text: NSMutableAttributedString,
    range: NSRange
) {
    let message = text.attributedSubstring(from: range).string
    let patterns: [(String, NSColor)] = [
        ("\\b(ERROR|FATAL|FAILED|EXCEPTION)\\b", .systemRed),
        ("\\b(WARN|WARNING)\\b", .systemOrange),
        ("\\b(READY|CONNECTED|STARTED|COMPLETED|SUCCESS)\\b", .systemGreen)
    ]
    for (pattern, color) in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
        regex.enumerateMatches(in: message, range: NSRange(location: 0, length: (message as NSString).length)) { match, _, _ in
            guard let match else { return }
            let absoluteRange = NSRange(
                location: range.location + match.range.location,
                length: match.range.length
            )
            text.addAttribute(.foregroundColor, value: color, range: absoluteRange)
            text.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), range: absoluteRange)
        }
    }
}

struct GroupManagerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @State private var newGroupName = ""
    @State private var parentID = DeviceGroup.allID

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("diagnosticsDeviceGroups").font(.title2.bold())
                    Text("diagnosticsDeviceGroupsSubtitle").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
            }
            .padding(20)
            Divider()

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("diagnosticsNewGroupName", text: $newGroupName).textFieldStyle(.roundedBorder)
                    Button("commonAdd") {
                        appState.addGroup(named: newGroupName, parentID: parentID)
                        newGroupName = ""
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Text("groupParent").font(.caption).foregroundColor(.secondary)
                    Picker("groupParent", selection: $parentID) {
                        Text("sidebarAllDevices").tag(DeviceGroup.allID)
                        ForEach(appState.flattenedGroups()) { entry in
                            Text(String(repeating: "  ", count: entry.depth) + "↳ " + entry.group.name)
                                .tag(entry.group.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)

            List {
                HStack {
                    Image(systemName: "house.fill").foregroundColor(AppTheme.accent)
                    Text("sidebarAllDevices").fontWeight(.semibold)
                    Spacer()
                    Text(String(format: String.localizedKey("diagnosticsDeviceCount"), appState.devices.count))
                        .font(.caption).foregroundColor(.secondary)
                }

                OutlineGroup(appState.groupTree(), children: \.children) { node in
                    groupRow(node.group)
                }
            }
            .listStyle(.inset)
        }
        .background(AppTheme.background)
    }

    private func groupRow(_ group: DeviceGroup) -> some View {
        HStack {
            Image(systemName: group.symbol).foregroundColor(AppTheme.accent)
            Text(group.name)
            Spacer()
            Text(String(
                format: String.localizedKey("diagnosticsDeviceCount"),
                appState.devices.filter { $0.groupIDs.contains(group.id) }.count
            ))
            .font(.caption).foregroundColor(.secondary)
            Button {
                parentID = group.id
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .help("groupAddChild")
            Button {
                confirmRemoveGroup(group)
            } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("groupDeleteSubtree")
        }
    }

    private func confirmRemoveGroup(_ group: DeviceGroup) {
        let alert = NSAlert()
        alert.messageText = String(
            format: String.localizedKey("groupDeleteConfirmationTitle"),
            group.name
        )
        alert.informativeText = String.localizedKey("groupDeleteConfirmationDetail")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String.localizedKey("commonDelete"))
        alert.addButton(withTitle: String.localizedKey("commonCancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        appState.removeGroup(id: group.id)
        if parentID == group.id || !appState.groups.contains(where: { $0.id == parentID }) {
            parentID = DeviceGroup.allID
        }
    }
}
