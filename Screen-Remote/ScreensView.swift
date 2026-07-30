import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ScreenDrag {
    static func provider(for deviceID: UUID) -> NSItemProvider {
        let provider = NSItemProvider(object: deviceID.uuidString as NSString)
        provider.suggestedName = deviceID.uuidString
        return provider
    }

    static func loadDeviceID(
        from providers: [NSItemProvider],
        completion: @escaping (UUID) -> Void
    ) -> Bool {
        guard let provider = providers.first(where: {
            $0.canLoadObject(ofClass: NSString.self)
        }) else { return false }

        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let string = value as? String, let id = UUID(uuidString: string) else { return }
            DispatchQueue.main.async { completion(id) }
        }
        return true
    }
}

@MainActor
final class ScreenWindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var detachedScreenIDs: Set<UUID> = []
    @Published var usesBorderlessWindows = false {
        didSet { updateWindowStyles() }
    }

    private var windowControllers: [UUID: NSWindowController] = [:]
    private var deviceIDsByWindowNumber: [Int: UUID] = [:]

    func isDetached(_ deviceID: UUID) -> Bool {
        detachedScreenIDs.contains(deviceID)
    }

    func detach(_ device: Device, appState: AppState) {
        if let controller = windowControllers[device.id] {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let content = DetachedScreenWindowView(deviceID: device.id)
            .environmentObject(appState)
            .environmentObject(self)
            .environment(\.locale, appState.resolvedLocale)

        let contentSize = ScreenWindowMetrics.preferredContentSize(
            device: device,
            session: appState.screenSessions.session(for: device.id)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: titledStyle,
            backing: .buffered,
            defer: false
        )
        window.title = device.name
        window.contentViewController = NSHostingController(rootView: content)
        window.isReleasedWhenClosed = false
        window.minSize = ScreenWindowMetrics.minimumContentSize
        window.center()
        window.delegate = self
        applyWindowStyle(to: window)

        let controller = NSWindowController(window: window)
        windowControllers[device.id] = controller
        deviceIDsByWindowNumber[window.windowNumber] = device.id
        detachedScreenIDs.insert(device.id)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func dock(_ deviceID: UUID) {
        guard let controller = windowControllers.removeValue(forKey: deviceID) else {
            detachedScreenIDs.remove(deviceID)
            return
        }
        if let window = controller.window {
            window.delegate = nil
            deviceIDsByWindowNumber.removeValue(forKey: window.windowNumber)
            window.close()
        }
        detachedScreenIDs.remove(deviceID)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let deviceID = deviceIDsByWindowNumber.removeValue(forKey: window.windowNumber) else {
            return
        }
        windowControllers.removeValue(forKey: deviceID)
        detachedScreenIDs.remove(deviceID)
    }

    private var titledStyle: NSWindow.StyleMask {
        [.titled, .closable, .miniaturizable, .resizable]
    }

    private func updateWindowStyles() {
        for controller in windowControllers.values {
            if let window = controller.window { applyWindowStyle(to: window) }
        }
    }

    private func applyWindowStyle(to window: NSWindow) {
        window.styleMask = usesBorderlessWindows ? [.borderless, .resizable] : titledStyle
        window.titlebarAppearsTransparent = !usesBorderlessWindows
        window.hasShadow = true
        window.isMovableByWindowBackground = usesBorderlessWindows
    }
}

private enum ScreenWindowMetrics {
    static let minimumContentSize = NSSize(width: 280, height: 440)
    private static let headerHeight: CGFloat = 38

    static func preferredContentSize(device: Device, session: ScreenSessionSnapshot) -> NSSize {
        let ratio = screenAspectRatio(device: device, session: session)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let maximumScreenHeight = max(420, visibleFrame.height * 0.78 - headerHeight)
        let desiredScreenHeight: CGFloat = ratio > 1 ? min(560, maximumScreenHeight) : min(720, maximumScreenHeight)
        var screenHeight = desiredScreenHeight
        var width = screenHeight * ratio

        let maximumWidth = max(minimumContentSize.width, visibleFrame.width * 0.72)
        if width > maximumWidth {
            width = maximumWidth
            screenHeight = width / ratio
        }
        if width < minimumContentSize.width {
            width = minimumContentSize.width
            screenHeight = width / ratio
        }
        return NSSize(
            width: width.rounded(.toNearestOrAwayFromZero),
            height: max(minimumContentSize.height, screenHeight + headerHeight).rounded(.toNearestOrAwayFromZero)
        )
    }
}

/// Reserved prototype for a multi-screen workspace.
///
/// The Screens page was removed from the product navigation. Keep the prototype
/// self-contained here so it is not accidentally registered in `AppSection` or
/// `RootView`; active sessions are currently presented by scrcpy-owned windows.
struct ScreensView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScreensWorkspace(
            coordinator: appState.screenWindows,
            sessionManager: appState.screenSessions
        )
    }
}

private struct ScreensWorkspace: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var coordinator: ScreenWindowCoordinator
    @ObservedObject var sessionManager: ScreenSessionManager

    @State private var selectedDeviceIDs: Set<UUID> = []
    @State private var scale: Double = 0.9
    @State private var isDetachTargeted = false
    @State private var isCanvasTargeted = false
    @State private var workspaceFrame = CGRect.zero

    private var visibleDevices: [Device] {
        appState.visibleDeviceOffsets().map(\.element)
    }

    private var dockedDevices: [Device] {
        visibleDevices.filter { !coordinator.isDetached($0.id) }
    }

    private var allVisibleSelected: Bool {
        !visibleDevices.isEmpty && visibleDevices.allSatisfy { selectedDeviceIDs.contains($0.id) }
    }

    private var referenceAspectRatio: CGFloat {
        guard let first = visibleDevices.first else { return 9.0 / 19.5 }
        let preflightSize = sessionManager.session(for: first.id).preflight?.displaySize ?? ""
        if let measuredRatio = displayAspectRatio(from: preflightSize) {
            return measuredRatio
        }
        let options = first.scrcpyOptions
        guard options.newDisplayWidth > 0, options.newDisplayHeight > 0 else {
            return 9.0 / 19.5
        }
        let ratio = CGFloat(options.newDisplayWidth) / CGFloat(options.newDisplayHeight)
        return min(max(ratio, 0.38), 1.8)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.55)
            workspace
        }
        .background(AppTheme.background)
        .onChange(of: visibleDevices.map(\.id)) { ids in
            selectedDeviceIDs.formIntersection(ids)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            SkeletonToolbarButton(title: "screensCastSettings", icon: "slider.horizontal.3")
            SkeletonToolbarButton(title: "screensQuickActions", icon: "bolt.fill")
            SkeletonToolbarButton(title: "screensADBShell", icon: "terminal")
            SkeletonToolbarButton(title: "screensADB", icon: "chevron.left.forwardslash.chevron.right")

            Divider().frame(height: 24)

            Toggle("screensSelectAll", isOn: Binding(
                get: { allVisibleSelected },
                set: { selectAll($0) }
            ))
            .toggleStyle(.checkbox)

            Toggle("screensBorderlessWindows", isOn: $coordinator.usesBorderlessWindows)
                .toggleStyle(.checkbox)

            Spacer(minLength: 8)

            Image(systemName: "minus")
                .font(.caption)
                .foregroundColor(.secondary)
            Slider(value: $scale, in: 0.55...1.45)
                .frame(width: 120)
                .help("screensScaleHelp")
            Image(systemName: "plus")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                detachSelected()
            } label: {
                Label("screensDetachSelected", systemImage: "macwindow.on.rectangle")
            }
            .disabled(selectedDeviceIDs.isEmpty)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(AppTheme.surface.opacity(0.96))
    }

    private var workspace: some View {
        GeometryReader { proxy in
            let metrics = ScreenGridMetrics(
                availableWidth: proxy.size.width,
                scale: CGFloat(scale)
            )

            VStack(spacing: 0) {
                detachDropZone
                if visibleDevices.isEmpty {
                    emptyState
                } else if dockedDevices.isEmpty {
                    allDetachedState
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: metrics.columns,
                            alignment: .center,
                            spacing: metrics.spacing
                        ) {
                            ForEach(dockedDevices) { device in
                                ScreenTile(
                                    device: device,
                                    isReference: device.id == visibleDevices.first?.id,
                                    isSelected: selectedDeviceIDs.contains(device.id),
                                    session: sessionManager.session(for: device.id),
                                    surface: sessionManager.videoSurface(for: device.id),
                                    screenAspectRatio: referenceAspectRatio,
                                    onSelect: { toggleSelection(device.id) },
                                    onStart: { appState.startScreenSession(deviceID: device.id) },
                                    onStop: { appState.stopScreenSession(deviceID: device.id) },
                                    onDetach: { coordinator.detach(device, appState: appState) },
                                    onTitleDragEnded: { location in
                                        guard !workspaceFrame.insetBy(dx: -8, dy: -8).contains(location) else { return }
                                        coordinator.detach(device, appState: appState)
                                    }
                                )
                                .frame(width: metrics.tileWidth)
                                .appOverlay(
                                    ScreenResizeHandle(scale: $scale),
                                    alignment: .bottomTrailing
                                )
                            }
                        }
                        .padding(metrics.spacing)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(
                GeometryReader { workspaceProxy in
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isCanvasTargeted ? AppTheme.accent : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                        )
                        .padding(8)
                        .onAppear { workspaceFrame = workspaceProxy.frame(in: .global) }
                        .onChange(of: workspaceProxy.size) { _ in
                            workspaceFrame = workspaceProxy.frame(in: .global)
                        }
                }
            )
            .onDrop(
                of: [UTType.text.identifier],
                isTargeted: $isCanvasTargeted
            ) { providers in
                ScreenDrag.loadDeviceID(from: providers) { coordinator.dock($0) }
            }
        }
    }

    private var detachDropZone: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow.badge.plus")
            Text("screensDetachDropZone")
            if !coordinator.detachedScreenIDs.isEmpty {
                Text(String(format: String.localizedKey("screensDetachedCount"), coordinator.detachedScreenIDs.count))
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundColor(isDetachTargeted ? .white : .secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(isDetachTargeted ? AppTheme.accent : Color.primary.opacity(0.035))
        .animation(.easeOut(duration: 0.14), value: isDetachTargeted)
        .onDrop(
            of: [UTType.text.identifier],
            isTargeted: $isDetachTargeted
        ) { providers in
            ScreenDrag.loadDeviceID(from: providers) { deviceID in
                guard let device = appState.devices.first(where: { $0.id == deviceID }) else { return }
                coordinator.detach(device, appState: appState)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 38))
                .foregroundColor(.secondary)
            Text("screensEmptyTitle").font(.headline)
            Text("screensEmptyDetail")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allDetachedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 38))
                .foregroundColor(.secondary)
            Text("screensAllDetachedTitle").font(.headline)
            Text("screensAllDetachedDetail")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleSelection(_ id: UUID) {
        if !selectedDeviceIDs.insert(id).inserted {
            selectedDeviceIDs.remove(id)
        }
    }

    private func selectAll(_ selected: Bool) {
        if selected {
            selectedDeviceIDs.formUnion(visibleDevices.map(\.id))
        } else {
            selectedDeviceIDs.subtract(visibleDevices.map(\.id))
        }
    }

    private func detachSelected() {
        for device in visibleDevices where selectedDeviceIDs.contains(device.id) {
            coordinator.detach(device, appState: appState)
        }
    }
}

private func displayAspectRatio(from displayInfo: String) -> CGFloat? {
    let dimension = displayInfo
        .split { character in
            !character.isNumber && character != "x"
        }
        .first { $0.contains("x") }
    guard let dimension else { return nil }
    let values = dimension.split(separator: "x")
    guard values.count == 2,
          let width = Double(values[0]),
          let height = Double(values[1]),
          width > 0,
          height > 0 else {
        return nil
    }
    return min(max(CGFloat(width / height), 0.38), 1.8)
}

private func screenAspectRatio(device: Device, session: ScreenSessionSnapshot) -> CGFloat {
    if let measured = displayAspectRatio(from: session.preflight?.displaySize ?? "") {
        return measured
    }
    let options = device.scrcpyOptions
    guard options.newDisplayWidth > 0, options.newDisplayHeight > 0 else {
        return 9.0 / 19.5
    }
    return min(
        max(CGFloat(options.newDisplayWidth) / CGFloat(options.newDisplayHeight), 0.38),
        1.8
    )
}

private struct ScreenGridMetrics {
    let tileWidth: CGFloat
    let spacing: CGFloat
    let columns: [GridItem]

    init(availableWidth: CGFloat, scale: CGFloat) {
        spacing = 16
        let desiredWidth = 220 * scale
        let safeWidth = max(1, availableWidth - spacing * 2)
        let count = max(1, Int((safeWidth + spacing) / (desiredWidth + spacing)))
        tileWidth = min(desiredWidth, (safeWidth - CGFloat(count - 1) * spacing) / CGFloat(count))
        columns = Array(
            repeating: GridItem(.fixed(tileWidth), spacing: spacing, alignment: .top),
            count: count
        )
    }
}

private struct SkeletonToolbarButton: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        Button(action: {}) {
            Label(title, systemImage: icon)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .foregroundColor(.white)
                .background(RoundedRectangle(cornerRadius: 5).fill(AppTheme.accent))
        }
        .buttonStyle(.plain)
        .help("screensReservedActionHelp")
    }
}

private struct ScreenResizeHandle: View {
    @Binding var scale: Double
    @State private var dragStartScale: Double?

    var body: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white.opacity(0.8))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.56))
            )
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartScale == nil { dragStartScale = scale }
                        let initial = dragStartScale ?? scale
                        scale = min(max(initial + Double(value.translation.width / 220), 0.55), 1.45)
                    }
                    .onEnded { _ in dragStartScale = nil }
            )
            .help("screensDragResizeHelp")
    }
}

private struct ScreenTile: View {
    let device: Device
    let isReference: Bool
    let isSelected: Bool
    let session: ScreenSessionSnapshot
    @ObservedObject var surface: ScrcpyVideoSurface
    let screenAspectRatio: CGFloat
    let onSelect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onDetach: () -> Void
    let onTitleDragEnded: (CGPoint) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? AppTheme.accent : .secondary)
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(session.isRunning ? Color.green : (session.phase.isWorking ? Color.orange : Color.secondary))
                    .frame(width: 7, height: 7)
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if isReference {
                    Text("screensReferenceBadge")
                        .font(.system(size: 9, weight: .semibold))
                        .fixedSize()
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.accent.opacity(0.12)))
                }
                Spacer(minLength: 2)
                Button(action: session.isRunning || session.phase.isWorking ? onStop : onStart) {
                    Image(systemName: session.isRunning || session.phase.isWorking ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .help(session.isRunning || session.phase.isWorking ? "screenSessionStop" : "screenSessionStart")
                Button(action: onDetach) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .help("screensDetach")
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(AppTheme.surface)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onEnded { onTitleDragEnded($0.location) }
            )

            ScrcpySurfacePlaceholder(device: device, session: session, surface: surface)
                .aspectRatio(screenAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? AppTheme.accent : AppTheme.line, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 9, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if session.isRunning || session.phase.isWorking {
                Button("screenSessionStop", action: onStop)
            } else {
                Button("screenSessionStart", action: onStart)
            }
            Button("screensDetach", action: onDetach)
        }
    }
}

private struct ScrcpySurfacePlaceholder: View {
    let device: Device
    let session: ScreenSessionSnapshot
    @ObservedObject var surface: ScrcpyVideoSurface

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [device.accent.opacity(0.38), Color.black, device.accent.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                if session.phase.isWorking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: session.isRunning ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        .font(.system(size: 30, weight: .light))
                }
                Text(LocalizedStringKey(session.phase.localizationKey))
                    .font(.caption.weight(.medium))
                if !session.detail.isEmpty {
                    Text(session.detail)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Text(device.model)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.58))
            }
            .foregroundColor(.white.opacity(0.82))
            if let image = surface.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
    }
}

private struct DetachedScreenWindowView: View {
    @EnvironmentObject private var appState: AppState
    let deviceID: UUID

    var body: some View {
        DetachedScreenWindowContent(
            sessionManager: appState.screenSessions,
            deviceID: deviceID
        )
    }
}

private struct DetachedScreenWindowContent: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var coordinator: ScreenWindowCoordinator
    @ObservedObject var sessionManager: ScreenSessionManager
    let deviceID: UUID

    private var device: Device? {
        appState.devices.first(where: { $0.id == deviceID })
    }

    private var aspectRatio: CGFloat {
        guard let device else { return 9.0 / 19.5 }
        return screenAspectRatio(
            device: device,
            session: sessionManager.session(for: deviceID)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let device {
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.secondary)
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button {
                        let session = sessionManager.session(for: deviceID)
                        if session.isRunning || session.phase.isWorking {
                            appState.stopScreenSession(deviceID: deviceID)
                        } else {
                            appState.startScreenSession(deviceID: deviceID)
                        }
                    } label: {
                        let session = sessionManager.session(for: deviceID)
                        Image(systemName: session.isRunning || session.phase.isWorking ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                    Button {
                        coordinator.dock(deviceID)
                    } label: {
                        Label("screensDock", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(WindowDragArea().background(AppTheme.surface))

                ScrcpySurfacePlaceholder(
                    device: device,
                    session: sessionManager.session(for: deviceID),
                    surface: sessionManager.videoSurface(for: deviceID)
                )
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .onDrag { ScreenDrag.provider(for: deviceID) }
            }
        }
        .background(Color.black)
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragNSView() }
    func updateNSView(_ nsView: NSView, context: Context) { }
}

private final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
