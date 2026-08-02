import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class ScreenWindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var detachedScreenIDs: Set<UUID> = []
    @Published private(set) var screenRotations: [UUID: Int] = [:]

    private var windowControllers: [UUID: NSWindowController] = [:]
    private var windowDeviceIDs: [ObjectIdentifier: UUID] = [:]
    private var screenAspectRatios: [UUID: CGFloat] = [:]
    private var sourceVideoSizes: [UUID: NSSize] = [:]
    private var lastDockedVideoSizes: [UUID: NSSize] = [:]
    private var chromeVisibleDeviceIDs: Set<UUID> = []
    private var liveResizingDeviceIDs: Set<UUID> = []
    private var manuallyResizedDeviceIDs: Set<UUID> = []
    private var closingDeviceIDs: Set<UUID> = []

    func isDetached(_ deviceID: UUID) -> Bool {
        detachedScreenIDs.contains(deviceID)
    }

    func detach(_ device: Device, appState: AppState) {
        if let controller = windowControllers[device.id] {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        let session = appState.screenSessions.session(for: device.id)
        lastDockedVideoSizes.removeValue(forKey: device.id)
        let surface = appState.screenSessions.videoSurface(for: device.id)
        let visibleFrame = NSApp.keyWindow?.screen?.visibleFrame
            ?? NSApp.mainWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let sourceAspectRatio = ScreenWindowMetrics.resolvedAspectRatio(
            device: device,
            session: session,
            pixelSize: surface.pixelSize
        )
        let rotation = screenRotation(for: device.id)
        let aspectRatio = orientedAspectRatio(sourceAspectRatio, rotation: rotation)
        let minimumVideoSize = ScreenWindowMetrics.minimumScreenSize(for: aspectRatio)
        let sourceVideoSize = ScreenWindowMetrics.resolvedVideoSize(
            device: device,
            session: session,
            pixelSize: surface.pixelSize
        )
        let videoSize: NSSize
        if let sourceVideoSize {
            videoSize = ScreenWindowMetrics.preferredScreenSize(
                videoSize: orientedVideoSize(sourceVideoSize, rotation: rotation),
                minimumSize: minimumVideoSize,
                visibleFrame: visibleFrame
            )
        } else {
            videoSize = ScreenWindowMetrics.preferredScreenSize(
                aspectRatio: aspectRatio,
                minimumSize: minimumVideoSize,
                visibleFrame: visibleFrame
            )
        }
        let contentSize = contentSize(forVideoSize: videoSize)
        let content = DetachedScreenWindowView(deviceID: device.id)
            .environmentObject(appState)
            .environmentObject(self)
            .environment(\.locale, appState.resolvedLocale)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: titledStyle,
            backing: .buffered,
            defer: false
        )
        window.title = device.name
        window.contentViewController = NSHostingController(rootView: content)
        window.isReleasedWhenClosed = false
        window.delegate = self
        applySizingConstraints(to: window)
        window.acceptsMouseMovedEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        setStandardWindowControls(visible: false, in: window)
        position(window: window, contentSize: contentSize, in: visibleFrame)

        let controller = NSWindowController(window: window)
        windowControllers[device.id] = controller
        windowDeviceIDs[ObjectIdentifier(window)] = device.id
        screenAspectRatios[device.id] = sourceAspectRatio
        if let sourceVideoSize { sourceVideoSizes[device.id] = sourceVideoSize }
        detachedScreenIDs.insert(device.id)

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func dock(_ deviceID: UUID) {
        closeDetachedWindow(for: deviceID)
    }

    func lastDockedVideoSize(for deviceID: UUID) -> CGSize? {
        lastDockedVideoSizes[deviceID]
    }

    @discardableResult
    func setChromeVisible(_ visible: Bool, for deviceID: UUID) -> Bool {
        guard windowControllers[deviceID]?.window != nil else {
            return false
        }
        let wasVisible = chromeVisibleDeviceIDs.contains(deviceID)
        guard visible != wasVisible else { return true }
        if visible {
            chromeVisibleDeviceIDs.insert(deviceID)
        } else {
            chromeVisibleDeviceIDs.remove(deviceID)
        }
        if let window = windowControllers[deviceID]?.window {
            animateWindowControls(visible: visible, in: window)
        }
        return true
    }

    func screenRotation(for deviceID: UUID) -> Int {
        screenRotations[deviceID] ?? 0
    }

    func toggleScreenRotation(for deviceID: UUID) {
        rotateScreen(for: deviceID, by: 90)
    }

    func autoFitWindowToDevice(
        deviceID: UUID,
        deviceDisplay: ScreenTargetDisplayInfo? = nil
    ) {
        guard let window = windowControllers[deviceID]?.window,
              !window.inLiveResize,
              !liveResizingDeviceIDs.contains(deviceID) else {
            return
        }
        let sourceVideoSize = sourceVideoSizes[deviceID]
            ?? deviceDisplay.map { NSSize(width: $0.width, height: $0.height) }
        guard let sourceVideoSize else { return }

        let currentContentSize = window.contentView?.bounds.size ?? .zero
        let currentVideoSize = NSSize(
            width: max(
                1,
                currentContentSize.width
                    - ScreenWindowMetrics.containerHorizontalChrome
                    - ScreenWindowMetrics.detachedChromeHorizontalGrowth
            ),
            height: max(
                1,
                currentContentSize.height - ScreenWindowMetrics.containerChromeHeight
            )
        )
        let deviceVideoSize = orientedVideoSize(
            sourceVideoSize,
            rotation: screenRotation(for: deviceID)
        )
        let deviceAspectRatio = deviceVideoSize.width / max(deviceVideoSize.height, 1)
        let currentAspectRatio = currentVideoSize.width / max(currentVideoSize.height, 1)
        let targetVideoSize: NSSize
        if currentAspectRatio > deviceAspectRatio {
            targetVideoSize = NSSize(
                width: currentVideoSize.height * deviceAspectRatio,
                height: currentVideoSize.height
            )
        } else if currentAspectRatio < deviceAspectRatio {
            targetVideoSize = NSSize(
                width: currentVideoSize.width,
                height: currentVideoSize.width / deviceAspectRatio
            )
        } else {
            return
        }

        manuallyResizedDeviceIDs.remove(deviceID)
        setWindowFrame(
            window,
            toContentSize: contentSize(forVideoSize: targetVideoSize)
        )
    }

    func rotateScreen(for deviceID: UUID, by degrees: Int) {
        let rotation = (screenRotation(for: deviceID) + degrees + 360) % 360
        screenRotations[deviceID] = rotation
        updateWindowSize(for: deviceID, rotation: rotation)
    }

    func updateWindowSize(
        deviceID: UUID,
        device: Device,
        session: ScreenSessionSnapshot,
        surface: ScrcpyVideoSurface
    ) {
        guard let window = windowControllers[deviceID]?.window else { return }
        let sourceAspectRatio = ScreenWindowMetrics.resolvedAspectRatio(
            device: device,
            session: session,
            pixelSize: surface.pixelSize
        )
        screenAspectRatios[deviceID] = sourceAspectRatio
        let sourceVideoSize = ScreenWindowMetrics.resolvedVideoSize(
            device: device,
            session: session,
            pixelSize: surface.pixelSize
        )
        if let sourceVideoSize { sourceVideoSizes[deviceID] = sourceVideoSize }
        guard !window.inLiveResize,
              !liveResizingDeviceIDs.contains(deviceID),
              !manuallyResizedDeviceIDs.contains(deviceID) else {
            return
        }
        resizeWindow(
            window,
            sourceAspectRatio: sourceAspectRatio,
            sourceVideoSize: sourceVideoSize,
            rotation: screenRotation(for: deviceID)
        )
    }

    func restoreOriginalDisplayWindow(
        deviceID: UUID,
        originalDisplay: ScreenTargetDisplayInfo
    ) {
        guard let window = windowControllers[deviceID]?.window,
              originalDisplay.width > 0,
              originalDisplay.height > 0 else {
            return
        }
        let sourceVideoSize = NSSize(
            width: originalDisplay.width,
            height: originalDisplay.height
        )
        let sourceAspectRatio = sourceVideoSize.width / sourceVideoSize.height
        manuallyResizedDeviceIDs.remove(deviceID)
        screenAspectRatios[deviceID] = sourceAspectRatio
        sourceVideoSizes[deviceID] = sourceVideoSize
        resizeWindow(
            window,
            sourceAspectRatio: sourceAspectRatio,
            sourceVideoSize: sourceVideoSize,
            rotation: screenRotation(for: deviceID)
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let deviceID = windowDeviceIDs[ObjectIdentifier(sender)],
              !closingDeviceIDs.contains(deviceID) else {
            return true
        }
        closeDetachedWindow(for: deviceID)
        return false
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let deviceID = windowDeviceIDs[ObjectIdentifier(window)] else {
            return
        }
        liveResizingDeviceIDs.insert(deviceID)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let deviceID = windowDeviceIDs[ObjectIdentifier(window)] else {
            return
        }
        liveResizingDeviceIDs.remove(deviceID)
        manuallyResizedDeviceIDs.insert(deviceID)
    }

    private var titledStyle: NSWindow.StyleMask {
        [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    }

    private func updateWindowSize(for deviceID: UUID, rotation: Int) {
        guard let window = windowControllers[deviceID]?.window,
              let sourceAspectRatio = screenAspectRatios[deviceID],
              !window.inLiveResize,
              !liveResizingDeviceIDs.contains(deviceID) else {
            return
        }
        resizeWindow(
            window,
            sourceAspectRatio: sourceAspectRatio,
            sourceVideoSize: sourceVideoSizes[deviceID],
            rotation: rotation
        )
    }

    private func resizeWindow(
        _ window: NSWindow,
        sourceAspectRatio: CGFloat,
        sourceVideoSize: NSSize?,
        rotation: Int
    ) {
        let aspectRatio = orientedAspectRatio(sourceAspectRatio, rotation: rotation)
        let minimumVideoSize = ScreenWindowMetrics.minimumScreenSize(for: aspectRatio)
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let videoSize: NSSize
        if let sourceVideoSize {
            videoSize = ScreenWindowMetrics.preferredScreenSize(
                videoSize: orientedVideoSize(sourceVideoSize, rotation: rotation),
                minimumSize: minimumVideoSize,
                visibleFrame: visibleFrame
            )
        } else {
            videoSize = ScreenWindowMetrics.preferredScreenSize(
                aspectRatio: aspectRatio,
                minimumSize: minimumVideoSize,
                visibleFrame: visibleFrame
            )
        }
        setWindowFrame(
            window,
            toContentSize: contentSize(forVideoSize: videoSize)
        )
    }

    private func setWindowFrame(_ window: NSWindow, toContentSize contentSize: NSSize) {
        applySizingConstraints(to: window)
        let targetFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        guard abs(window.frame.width - targetFrameSize.width) > 1
                || abs(window.frame.height - targetFrameSize.height) > 1 else {
            return
        }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        window.setFrame(
            NSRect(
                x: center.x - targetFrameSize.width / 2,
                y: center.y - targetFrameSize.height / 2,
                width: targetFrameSize.width,
                height: targetFrameSize.height
            ),
            display: true
        )
    }

    private func orientedAspectRatio(_ sourceAspectRatio: CGFloat, rotation: Int) -> CGFloat {
        rotation % 180 == 0 ? sourceAspectRatio : 1 / sourceAspectRatio
    }

    private func orientedVideoSize(_ sourceSize: NSSize, rotation: Int) -> NSSize {
        rotation % 180 == 0
            ? sourceSize
            : NSSize(width: sourceSize.height, height: sourceSize.width)
    }

    private func applySizingConstraints(to window: NSWindow) {
        window.contentMinSize = NSSize(
            width: ScreenWindowMetrics.minimumDetachedContentSize.width
                + ScreenWindowMetrics.detachedChromeHorizontalGrowth,
            height: ScreenWindowMetrics.minimumDetachedContentSize.height
        )
    }

    private func contentSize(forVideoSize videoSize: NSSize) -> NSSize {
        return NSSize(
            width: videoSize.width
                + ScreenWindowMetrics.containerHorizontalChrome
                + ScreenWindowMetrics.detachedChromeHorizontalGrowth,
            height: videoSize.height + ScreenWindowMetrics.containerChromeHeight
        )
    }

    private func position(window: NSWindow, contentSize: NSSize, in visibleFrame: NSRect) {
        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        window.setFrame(
            NSRect(
                x: visibleFrame.midX - frameSize.width / 2,
                y: visibleFrame.midY - frameSize.height / 2,
                width: frameSize.width,
                height: frameSize.height
            ),
            display: false
        )
    }

    private func setStandardWindowControls(visible: Bool, in window: NSWindow) {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { type in
            guard let button = window.standardWindowButton(type) else { return }
            button.alphaValue = visible ? 1 : 0
            button.isEnabled = visible
            button.isHidden = !visible
        }
    }

    private func animateWindowControls(visible: Bool, in window: NSWindow) {
        let windowControls = [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].compactMap(window.standardWindowButton)
        if visible {
            windowControls.forEach { button in
                if button.isHidden {
                    button.alphaValue = 0
                    button.isHidden = false
                }
                button.isEnabled = true
            }
        } else {
            windowControls.forEach { $0.isEnabled = false }
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = ScreenWindowMetrics.chromeAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            windowControls.forEach { $0.animator().alphaValue = visible ? 1 : 0 }
        } completionHandler: { [weak self, weak window] in
            guard let self,
                  let window,
                  let deviceID = self.windowDeviceIDs[ObjectIdentifier(window)],
                  self.chromeVisibleDeviceIDs.contains(deviceID) == visible else {
                return
            }
            if !visible {
                windowControls.forEach { $0.isHidden = true }
            }
        }
    }

    private func closeDetachedWindow(for deviceID: UUID) {
        guard !closingDeviceIDs.contains(deviceID) else { return }
        closingDeviceIDs.insert(deviceID)
        if let contentSize = windowControllers[deviceID]?.window?.contentView?.bounds.size {
            lastDockedVideoSizes[deviceID] = NSSize(
                width: max(
                    1,
                    contentSize.width
                        - ScreenWindowMetrics.containerHorizontalChrome
                        - ScreenWindowMetrics.detachedChromeHorizontalGrowth
                ),
                height: max(
                    1,
                    contentSize.height - ScreenWindowMetrics.containerChromeHeight
                )
            )
        }
        detachedScreenIDs.remove(deviceID)
        liveResizingDeviceIDs.remove(deviceID)
        manuallyResizedDeviceIDs.remove(deviceID)
        chromeVisibleDeviceIDs.remove(deviceID)
        screenAspectRatios.removeValue(forKey: deviceID)
        sourceVideoSizes.removeValue(forKey: deviceID)

        let window = windowControllers.removeValue(forKey: deviceID)?.window
        if let window {
            windowDeviceIDs.removeValue(forKey: ObjectIdentifier(window))
            window.delegate = nil
            window.orderOut(nil)
            window.close()
        }
        closingDeviceIDs.remove(deviceID)
    }
}

enum ScreenWindowMetrics {
    static let headerHeight: CGFloat = 32
    private static let originalBottomControlsHeight: CGFloat = 42
    static let embeddedBottomControlsHeight = originalBottomControlsHeight * 3 / 5
    static let detachedBottomControlsHeight = originalBottomControlsHeight * 3 / 4
    static let shellSideInset: CGFloat = 0
    static let shellVerticalInset: CGFloat = 0
    static let screenCornerRadius: CGFloat = 14
    static let containerCornerRadius: CGFloat = 18
    static let embeddedChromeSideExpansion: CGFloat = 5
    static let embeddedChromeHorizontalGrowth = embeddedChromeSideExpansion * 2
    static let detachedChromeSideExpansion: CGFloat = 8
    static let detachedChromeHorizontalGrowth = detachedChromeSideExpansion * 2
    static let chromeRevealInset: CGFloat = 10
    static let chromeHideDelay: TimeInterval = 1
    static let chromeAnimationDuration: TimeInterval = 0.16
    static let detachedTopChrome = headerHeight + shellVerticalInset
    static let detachedBottomChrome = detachedBottomControlsHeight + shellVerticalInset
    static let containerChromeHeight = headerHeight
        + detachedBottomControlsHeight
        + shellVerticalInset * 2
    static let embeddedVerticalChrome = shellVerticalInset * 2
    static let containerHorizontalChrome = shellSideInset * 2
    static let minimumDetachedContentSize = NSSize(width: 180, height: 240)
    private static let minimumLongEdge: CGFloat = 440
    private static let minimumShortEdge: CGFloat = 200

    static func resolvedAspectRatio(
        device: Device,
        session: ScreenSessionSnapshot,
        pixelSize: CGSize = .zero
    ) -> CGFloat {
        if pixelSize.width > 0, pixelSize.height > 0 {
            return min(max(pixelSize.width / pixelSize.height, 0.25), 4)
        }
        return min(max(screenAspectRatio(device: device, session: session), 0.25), 4)
    }

    static func resolvedVideoSize(
        device: Device,
        session: ScreenSessionSnapshot,
        pixelSize: CGSize = .zero
    ) -> NSSize? {
        if pixelSize.width > 0, pixelSize.height > 0 {
            return NSSize(width: pixelSize.width, height: pixelSize.height)
        }
        if let displaySize = displayPixelSize(from: session.preflight?.displaySize ?? "") {
            return NSSize(width: displaySize.width, height: displaySize.height)
        }
        let options = device.scrcpyOptions
        guard options.newDisplayWidth > 0, options.newDisplayHeight > 0 else { return nil }
        return NSSize(width: options.newDisplayWidth, height: options.newDisplayHeight)
    }

    static func minimumScreenSize(for aspectRatio: CGFloat) -> NSSize {
        if aspectRatio <= 1 {
            let width = max(minimumShortEdge, minimumLongEdge * aspectRatio)
            return NSSize(width: width, height: width / aspectRatio)
        }
        let height = max(minimumShortEdge, minimumLongEdge / aspectRatio)
        return NSSize(width: height * aspectRatio, height: height)
    }

    static func preferredScreenSize(
        aspectRatio: CGFloat,
        minimumSize: NSSize,
        visibleFrame: NSRect
    ) -> NSSize {
        let maximumSize = maximumVideoSize(in: visibleFrame, minimumSize: minimumSize)
        let desiredHeight: CGFloat = aspectRatio > 1
            ? min(560, maximumSize.height)
            : min(720, maximumSize.height)
        var height = desiredHeight
        var width = height * aspectRatio
        if width > maximumSize.width {
            width = maximumSize.width
            height = width / aspectRatio
        }
        if width < minimumSize.width || height < minimumSize.height {
            width = minimumSize.width
            height = minimumSize.height
        }
        return NSSize(
            width: width.rounded(.toNearestOrAwayFromZero),
            height: height.rounded(.toNearestOrAwayFromZero)
        )
    }

    static func preferredScreenSize(
        videoSize: NSSize,
        minimumSize: NSSize,
        visibleFrame: NSRect
    ) -> NSSize {
        let maximumSize = maximumVideoSize(in: visibleFrame, minimumSize: minimumSize)
        var size = videoSize
        let scale = min(
            1,
            maximumSize.width / max(1, size.width),
            maximumSize.height / max(1, size.height)
        )
        size.width *= scale
        size.height *= scale
        if size.width < minimumSize.width || size.height < minimumSize.height {
            let minimumScale = max(
                minimumSize.width / max(1, size.width),
                minimumSize.height / max(1, size.height)
            )
            size.width *= minimumScale
            size.height *= minimumScale
        }
        return NSSize(
            width: size.width.rounded(.toNearestOrAwayFromZero),
            height: size.height.rounded(.toNearestOrAwayFromZero)
        )
    }

    private static func maximumVideoSize(
        in visibleFrame: NSRect,
        minimumSize: NSSize
    ) -> NSSize {
        let displayMargin: CGFloat = 96
        let titlebarHeight = NSWindow.frameRect(
            forContentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        ).height
        return NSSize(
            width: max(
                minimumSize.width,
                visibleFrame.width - displayMargin
            ),
            height: max(
                minimumSize.height,
                visibleFrame.height - displayMargin - titlebarHeight
            )
        )
    }
}
