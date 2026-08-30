import AppKit
import SwiftUI

struct ScrcpySurfacePlaceholder: View {
    let device: Device
    let session: ScreenSessionSnapshot
    @ObservedObject var surface: ScrcpyVideoSurface

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [device.accent.opacity(0.34), Color.black, device.accent.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = surface.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }

            if surface.image == nil || !session.isConnected {
                Color.black.opacity(surface.image == nil ? 0.08 : 0.52)

                VStack(spacing: AppSpacing.md) {
                    Group {
                        if session.phase.isWorking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.85)
                        } else {
                            Image(
                                systemName: session.isRunning
                                    ? "iphone.radiowaves.left.and.right"
                                    : "iphone.slash"
                            )
                            .font(.system(size: 25, weight: .medium))
                        }
                    }
                    .frame(width: 42, height: 42)

                    VStack(spacing: AppSpacing.xs) {
                        Text(LocalizedStringKey(session.phase.localizationKey))
                            .font(.caption.weight(.semibold))
                        Text(device.name)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .appBackground(
                    Color.black.opacity(0.36),
                    in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .padding(AppSpacing.lg)
            }
        }
    }
}

struct DetachedScreenWindowView: View {
    @EnvironmentObject private var appState: AppState
    let deviceID: UUID

    var body: some View {
        DetachedScreenWindowContent(
            sessionManager: appState.screenSessions,
            deviceID: deviceID
        )
        .edgesIgnoringSafeArea(.top)
    }
}

struct DetachedScreenWindowContent: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var coordinator: ScreenWindowCoordinator
    @ObservedObject var sessionManager: ScreenSessionManager
    let deviceID: UUID

    private var device: Device? {
        appState.devices.first(where: { $0.id == deviceID })
    }

    var body: some View {
        ZStack {
            if let device {
                let surface = sessionManager.videoSurface(for: deviceID)
                ScrcpyParentContainer(
                    mode: .detached,
                    device: device,
                    isReference: false,
                    isSelected: false,
                    session: sessionManager.session(for: deviceID),
                    sessionManager: sessionManager,
                    surface: surface,
                    rotation: coordinator.screenRotation(for: deviceID),
                    onSelect: {},
                    onStop: {},
                    onRotate: { coordinator.toggleScreenRotation(for: deviceID) },
                    onDetachOrDock: { coordinator.dock(deviceID) },
                    onAutoFit: {
                        let session = sessionManager.session(for: deviceID)
                        appState.screenWindows.autoFitWindowToDevice(
                            deviceID: deviceID,
                            deviceDisplay: session.preflight?.displayInfo
                        )
                    },
                    onTitleDragChanged: { _ in },
                    onTitleDragEnded: {},
                    onResizeChanged: { _, _ in },
                    onResizeEnded: {},
                    onChromeVisibilityChanged: {
                        coordinator.setChromeVisible($0, for: deviceID)
                    }
                )
                .onChange(of: surface.pixelSize) { _ in
                    coordinator.updateWindowSize(
                        deviceID: deviceID,
                        device: device,
                        session: sessionManager.session(for: deviceID),
                        surface: surface
                    )
                }
            }

            DetachedScreenShortcutMonitor { action in
                handleShortcut(action)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
        .onChange(of: sessionManager.session(for: deviceID).preflight?.displaySize) { _ in
            guard let device else { return }
            coordinator.updateWindowSize(
                deviceID: deviceID,
                device: device,
                session: sessionManager.session(for: deviceID),
                surface: sessionManager.videoSurface(for: deviceID)
            )
        }
    }

    private func handleShortcut(_ action: DetachedScreenShortcut) {
        switch action {
        case .rotateLeft:
            coordinator.rotateScreen(for: deviceID, by: -90)
        case .rotateRight:
            coordinator.rotateScreen(for: deviceID, by: 90)
        case .home:
            sendKeyEvent(keyCode: 3)
        case .back:
            sendKeyEvent(keyCode: 4)
        case .appSwitcher:
            sendKeyEvent(keyCode: 187)
        case .volumeUp:
            sendKeyEvent(keyCode: 24)
        case .volumeDown:
            sendKeyEvent(keyCode: 25)
        case .power:
            sendKeyEvent(keyCode: 26)
        }
    }

    private func sendKeyEvent(keyCode: UInt32) {
        let sentDown = sessionManager.sendKeyEvent(
            deviceID: deviceID,
            keyCode: keyCode,
            action: .down
        )
        let sentUp = sessionManager.sendKeyEvent(
            deviceID: deviceID,
            keyCode: keyCode,
            action: .up
        )
        guard sentDown && sentUp else {
            appState.sendScreenKeyEvent(
                deviceID: deviceID,
                keyCode: Int(keyCode),
                action: "keyCode_\(keyCode)"
            )
            return
        }
    }
}

struct AppVirtualScreenWindowContent: View {
    @EnvironmentObject private var appState: AppState
    let device: Device
    let sessionID: UUID

    var body: some View {
        let surface = appState.screenSessions.videoSurface(for: sessionID)
        ScrcpyParentContainer(
            mode: .detached,
            device: device,
            isReference: false,
            isSelected: false,
            session: appState.screenSessions.session(for: sessionID),
            sessionManager: appState.screenSessions,
            surface: surface,
            rotation: appState.screenWindows.screenRotation(for: sessionID),
            onSelect: {},
            onStop: { appState.screenSessions.stopNativeAppVirtualDisplay(deviceID: sessionID) },
            onRotate: { appState.screenWindows.toggleScreenRotation(for: sessionID) },
            onDetachOrDock: { appState.screenSessions.stopNativeAppVirtualDisplay(deviceID: sessionID) },
            onAutoFit: { updateWindowSize(surface: surface) },
            onTitleDragChanged: { _ in },
            onTitleDragEnded: {},
            onResizeChanged: { _, _ in },
            onResizeEnded: {},
            onChromeVisibilityChanged: { _ in true },
            showsCloseButton: true
        )
        .onAppear { updateWindowSize(surface: surface) }
        .onChange(of: surface.pixelSize) { _ in updateWindowSize(surface: surface) }
    }

    private func updateWindowSize(surface: ScrcpyVideoSurface) {
        appState.screenWindows.updateWindowSize(
            deviceID: sessionID,
            device: device,
            session: appState.screenSessions.session(for: sessionID),
            surface: surface
        )
    }
}

struct ScreenSourceViewportSizeKey: PreferenceKey {
    static var defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}

private enum DetachedScreenShortcut {
    case rotateLeft
    case rotateRight
    case home
    case back
    case appSwitcher
    case volumeUp
    case volumeDown
    case power
}

private struct DetachedScreenShortcutMonitor: NSViewRepresentable {
    let onShortcut: (DetachedScreenShortcut) -> Void

    func makeNSView(context: Context) -> DetachedScreenShortcutView {
        let view = DetachedScreenShortcutView()
        view.onShortcut = onShortcut
        return view
    }

    func updateNSView(_ nsView: DetachedScreenShortcutView, context: Context) {
        nsView.onShortcut = onShortcut
    }
}

private final class DetachedScreenShortcutView: NSView {
    var onShortcut: ((DetachedScreenShortcut) -> Void)?
    private var localEventMonitor: Any?

    deinit { removeEventMonitor() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeEventMonitor()
        guard window != nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            guard let action = self.shortcutAction(for: event) else { return event }
            self.onShortcut?(action)
            return nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func shortcutAction(for event: NSEvent) -> DetachedScreenShortcut? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.option) || modifiers.contains(.command) else { return nil }
        switch event.keyCode {
        case 123: return .rotateLeft
        case 124: return .rotateRight
        case 125: return .volumeDown
        case 126: return .volumeUp
        case 51: return .back
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "h": return .home
        case "b": return .back
        case "s": return .appSwitcher
        case "p": return .power
        default: return nil
        }
    }

    private func removeEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }
}

struct WindowDragArea: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {
        nsView.isEnabled = isEnabled
    }
}

final class WindowDragNSView: NSView {
    var isEnabled = true
    private var doubleClickMonitor: Any?

    deinit {
        removeDoubleClickMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installDoubleClickMonitorIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        if event.clickCount == 2 {
            NativeWindowInteraction.performZoom(on: window)
        } else {
            window.performDrag(with: event)
        }
    }

    private func installDoubleClickMonitorIfNeeded() {
        removeDoubleClickMonitor()
        guard let window else { return }
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self, weak window] event in
            guard let self,
                  let window,
                  self.window === window,
                  event.window === window,
                  event.clickCount == 2,
                  self.isEnabled,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
                return event
            }
            NativeWindowInteraction.performZoom(on: window)
            return nil
        }
    }

    private func removeDoubleClickMonitor() {
        if let doubleClickMonitor {
            NSEvent.removeMonitor(doubleClickMonitor)
            self.doubleClickMonitor = nil
        }
    }
}

struct ScrcpyContainerEdgeHoverTracker: NSViewRepresentable {
    let isVisible: Bool
    let onVisibilityChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ScrcpyContainerEdgeTrackingView {
        let view = ScrcpyContainerEdgeTrackingView()
        view.onVisibilityChanged = onVisibilityChanged
        view.synchronizeVisibility(isVisible)
        return view
    }

    func updateNSView(_ nsView: ScrcpyContainerEdgeTrackingView, context: Context) {
        nsView.onVisibilityChanged = onVisibilityChanged
        nsView.synchronizeVisibility(isVisible)
    }
}

final class ScrcpyContainerEdgeTrackingView: NSView {
    var onVisibilityChanged: ((Bool) -> Void)?
    private var trackingAreaReference: NSTrackingArea?
    private var hideTimer: Timer?
    private var trackedBounds = NSRect.null
    private var lastVisibility = false

    override var isFlipped: Bool { true }

    deinit {
        hideTimer?.invalidate()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingAreaReference == nil || trackedBounds != bounds else { return }

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        trackingAreaReference = nil
        trackedBounds = bounds

        guard bounds.width > 0, bounds.height > 0 else { return }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .enabledDuringMouseDrag
        ]
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        synchronizeVisibilityWithPointer()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) {
        updateVisibility(with: event)
    }

    override func mouseMoved(with event: NSEvent) { updateVisibility(with: event) }
    override func mouseExited(with event: NSEvent) { scheduleHide() }

    func synchronizeVisibility(_ visible: Bool) {
        guard visible != lastVisibility else { return }
        lastVisibility = visible
        if !visible {
            cancelPendingHide()
        }
    }

    private func scheduleHide() {
        guard lastVisibility, hideTimer == nil else { return }
        let timer = Timer(timeInterval: ScreenWindowMetrics.chromeHideDelay, repeats: false) {
            [weak self] _ in
            guard let self else { return }
            self.hideTimer = nil
            guard !self.isPointerInRevealRegion else { return }
            self.publish(false)
        }
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelPendingHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func publish(_ visible: Bool) {
        guard visible != lastVisibility else { return }
        lastVisibility = visible
        if !visible {
            cancelPendingHide()
        }
        onVisibilityChanged?(visible)
    }

    private func updateVisibility(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isInRevealRegion(point) {
            cancelPendingHide()
            publish(true)
        } else {
            scheduleHide()
        }
    }

    private func synchronizeVisibilityWithPointer() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if isInRevealRegion(point) {
            cancelPendingHide()
            publish(true)
        } else {
            scheduleHide()
        }
    }

    private var isPointerInRevealRegion: Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return isInRevealRegion(point)
    }

    private func isInRevealRegion(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        let topHeight = min(
            bounds.height,
            ScreenWindowMetrics.headerHeight + ScreenWindowMetrics.detachedTopChrome
        )
        let bottomHeight = min(
            bounds.height,
            ScreenWindowMetrics.detachedBottomControlsHeight
                + ScreenWindowMetrics.detachedBottomChrome
        )
        let sideWidth = min(ScreenWindowMetrics.chromeRevealInset, bounds.width / 2)
        return point.y <= bounds.minY + topHeight
            || point.y >= bounds.maxY - bottomHeight
            || point.x <= bounds.minX + sideWidth
            || point.x >= bounds.maxX - sideWidth
    }
}

private struct ScrcpyDebugInfoLine: Identifiable {
    let label: LocalizedStringKey
    let value: String
    var id: String { "\(label)-\(value)" }
}

struct ScrcpyConnectionDebugWindow: View {
    @EnvironmentObject private var appState: AppState
    let deviceID: UUID

    private var device: Device? {
        appState.devices.first(where: { $0.id == deviceID })
    }

    private var session: ScreenSessionSnapshot {
        appState.screenSessions.session(for: deviceID)
    }

    private var remoteDeviceName: String {
        let deviceInformationName = appState.deviceInformationCache[deviceID]?.value(.model) ?? ""
        if !deviceInformationName.isEmpty { return deviceInformationName }
        let preflightName = session.preflight?.model ?? ""
        return preflightName.isEmpty ? "-" : preflightName
    }

    private var lines: [ScrcpyDebugInfoLine] {
        let options = device?.scrcpyOptions
        return [
            line("screensDebugTransport", session.transport?.rawValue ?? "-"),
            line("screensDebugADBSerial", session.adbSerial),
            line("screensDebugPhase", String.localizedKey(session.phase.localizationKey)),
            line("screensDebugDeviceName", remoteDeviceName),
            line("screensDebugProcess", session.processIdentifier.map(String.init) ?? "-"),
            line(
                "screensDebugControlChannel",
                session.isRunning
                    ? String.localizedKey("screensDebugConnected")
                    : String.localizedKey("screensDebugUnavailable")
            ),
            line("screensDebugDisplay", session.preflight?.displaySize ?? ""),
            line("screensDebugAudio", options?.enableAudio == true ? "Enabled" : "Disabled"),
            line("screensDebugVirtualDisplay", options?.newDisplayEnabled == true ? "Enabled" : "Disabled"),
            line("screensDebugStartApp", options?.startApp ?? "")
        ].compactMap { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    AppIconTile(symbol: "ladybug.fill", color: AppTheme.accent, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(remoteDeviceName)
                            .font(.headline)
                        Text("screensDebugDescription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(LocalizedStringKey(session.phase.localizationKey))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(session.isRunning ? .green : AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .padding(16)
                .appCard()

                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 16) {
                            Text(item.label)
                                .foregroundColor(.secondary)
                                .frame(width: 132, alignment: .leading)
                            Text(item.value)
                                .font(.system(size: 11.5, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        if index < lines.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .appCard()
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .frame(minWidth: 400, minHeight: 300)
    }

    private func line(_ label: LocalizedStringKey, _ value: String) -> ScrcpyDebugInfoLine? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : ScrcpyDebugInfoLine(label: label, value: value)
    }
}
