import AppKit
import SwiftUI

struct ScrcpyBottomControls: View {
    @EnvironmentObject private var appState: AppState
    let deviceID: UUID
    let height: CGFloat

    private var controlSize: CGFloat { min(height, 24) }
    private var iconSize: CGFloat { height < 30 ? 12.5 : 14 }

    var body: some View {
        HStack(spacing: 3) {
            ScrcpyContainerControlButton(
                icon: "arrow.uturn.backward",
                help: "screensControlBack",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                sendKeyEvent(keyCode: 4)
            }
            ScrcpyContainerControlButton(
                icon: "house",
                help: "screensControlHome",
                controlSize: controlSize,
                iconSize: iconSize,
                onLongPress: captureScreenshot
            ) {
                sendKeyEvent(keyCode: 3)
            }
            ScrcpyContainerControlButton(
                icon: "square.stack.3d.down.right",
                help: "screensControlAppSwitcher",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                sendKeyEvent(keyCode: 187)
            }
            ScrcpyContainerControlButton(
                icon: "speaker.wave.2",
                help: "screensControlVolumeUp",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                sendKeyEvent(keyCode: 24)
            }
            ScrcpyContainerControlButton(
                icon: "speaker.wave.1",
                help: "screensControlVolumeDown",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                sendKeyEvent(keyCode: 25)
            }
            ScrcpyContainerControlButton(
                icon: "power",
                help: "screensControlPower",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                sendKeyEvent(keyCode: 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func captureScreenshot() {
        if let url = appState.screenSessions.captureScreenshot(deviceID: deviceID) {
            NSWorkspace.shared.open(url)
            appState.appendSDLLog("Scrcpy screenshot saved: \(url.path)")
        } else {
            appState.appendSDLLog("Scrcpy screenshot failed: no decoded frame available")
        }
    }

    private func sendKeyEvent(keyCode: UInt32) {
        let sentDown = appState.screenSessions.sendKeyEvent(
            deviceID: deviceID,
            keyCode: keyCode,
            action: .down
        )
        let sentUp = appState.screenSessions.sendKeyEvent(
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

struct RotatedScrcpySurface: View {
    @EnvironmentObject private var appState: AppState
    let device: Device
    let session: ScreenSessionSnapshot
    @ObservedObject var surface: ScrcpyVideoSurface
    let rotation: Int

    var body: some View {
        GeometryReader { proxy in
            let sourceAspectRatio = ScreenWindowMetrics.resolvedAspectRatio(
                device: device,
                session: session,
                pixelSize: surface.pixelSize
            )
            let renderedAspectRatio = rotation % 180 == 0
                ? sourceAspectRatio
                : 1 / sourceAspectRatio
            let renderedSize = aspectFitSize(
                aspectRatio: renderedAspectRatio,
                inside: proxy.size
            )
            let sourceSize = rotation % 180 == 0
                ? renderedSize
                : CGSize(width: renderedSize.height, height: renderedSize.width)

            let inspectorState = appState.screenSessions.layoutInspectorState(for: device.id)
            ZStack {
                ScrcpySurfacePlaceholder(device: device, session: session, surface: surface)
                if inspectorState.isVisible, let snapshot = inspectorState.snapshot {
                    ScreenLayoutInspectorNodeOverlay(snapshot: snapshot)
                }
                ScrcpyInputOverlay(
                    isEnabled: session.isRunning,
                    onMouseMove: { location, buttons in
                        sendMouseMove(
                            location: location,
                            viewportSize: sourceSize,
                            buttons: buttons
                        )
                    },
                    onMouseButton: { button, isDown, location, buttons in
                        sendMouseButton(
                            button: button,
                            isDown: isDown,
                            location: location,
                            viewportSize: sourceSize,
                            buttons: buttons
                        )
                    },
                    onBack: {
                        sendBack()
                    },
                    onText: { text in
                        sendText(text)
                    },
                    onPaste: { text in
                        appState.screenSessions.setClipboardAndPaste(deviceID: device.id, text: text)
                    },
                    onCopy: { copyKey in
                        appState.screenSessions.requestClipboard(deviceID: device.id, copyKey: copyKey)
                    },
                    onKeyCommand: { keyCode in
                        sendKeyPress(keyCode)
                    },
                    onScroll: { location, horizontal, vertical, buttons in
                        sendMouseScroll(
                            location: location,
                            viewportSize: sourceSize,
                            horizontal: horizontal,
                            vertical: vertical,
                            buttons: buttons
                        )
                    }
                )
                .frame(width: sourceSize.width, height: sourceSize.height)
            }
            .frame(width: sourceSize.width, height: sourceSize.height)
            .rotationEffect(.degrees(Double(rotation)))
            .frame(width: renderedSize.width, height: renderedSize.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .preference(key: ScreenSourceViewportSizeKey.self, value: proxy.size)

            if inspectorState.isVisible {
                ScreenLayoutInspectorToolbar(
                    isLoading: inspectorState.isLoading,
                    onRefresh: { appState.refreshScreenLayoutAnalysis(deviceID: device.id) },
                    onClose: { appState.toggleScreenLayoutAnalysis(deviceID: device.id) }
                )
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if inspectorState.isVisible && inspectorState.isTargetKeyboardVisible {
                Text("screensTargetKeyboardOpen")
                    .font(AppTypography.caption.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: AppRadius.small).fill(Color.black.opacity(0.78)))
                    .padding(.bottom, 38)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            let resolutionFeedback = appState.screenSessions
                .resolutionAdjustmentState(for: device.id).feedback
            let feedback = inspectorState.feedback.isEmpty
                ? resolutionFeedback
                : inspectorState.feedback
            if !feedback.isEmpty {
                Text(feedback)
                    .font(AppTypography.caption.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .id(feedback)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            appState.screenSessions.clearToolFeedback(
                                deviceID: device.id,
                                matching: feedback
                            )
                        }
                    }
            }
        }
        .background(Color.black)
        .clipShape(
            RoundedRectangle(
                cornerRadius: ScreenWindowMetrics.screenCornerRadius,
                style: .continuous
            )
        )
    }

    private func aspectFitSize(aspectRatio: CGFloat, inside size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        if aspectRatio >= size.width / size.height {
            return CGSize(width: size.width, height: size.width / aspectRatio)
        }
        return CGSize(width: size.height * aspectRatio, height: size.height)
    }

    private func remotePoint(
        location: CGPoint,
        viewportSize: CGSize
    ) -> CGPoint? {
        let screenSize = surface.pixelSize
        guard session.isRunning,
              viewportSize.width > 0,
              viewportSize.height > 0,
              screenSize.width > 0,
              screenSize.height > 0 else { return nil }

        let normalizedX = min(max(location.x / viewportSize.width, 0), 1)
        let normalizedY = min(max(location.y / viewportSize.height, 0), 1)
        return CGPoint(
            x: min(normalizedX * screenSize.width, max(screenSize.width - 1, 0)),
            y: min(normalizedY * screenSize.height, max(screenSize.height - 1, 0))
        )
    }

    private func sendBack() {
        sendKeyPress(4)
    }

    private func sendText(_ text: String) {
        let shouldPaste = text.count > 1 || text.utf8.count > 300 || text.contains {
            !$0.isASCII || $0 == "\n" || $0 == "\r" || $0 == "\t"
        }
        if shouldPaste {
            appState.screenSessions.setClipboardAndPaste(deviceID: device.id, text: text)
        } else {
            appState.screenSessions.sendText(deviceID: device.id, text: text)
        }
    }

    private func sendKeyPress(_ keyCode: UInt32) {
        let sentDown = appState.screenSessions.sendKeyEvent(
            deviceID: device.id,
            keyCode: keyCode,
            action: .down
        )
        let sentUp = appState.screenSessions.sendKeyEvent(
            deviceID: device.id,
            keyCode: keyCode,
            action: .up
        )
        guard sentDown && sentUp else {
            appState.sendScreenKeyEvent(
                deviceID: device.id,
                keyCode: Int(keyCode),
                action: "keyCode_\(keyCode)"
            )
            return
        }
    }

    private func sendMouseMove(
        location: CGPoint,
        viewportSize: CGSize,
        buttons: UInt32
    ) {
        guard let point = remotePoint(location: location, viewportSize: viewportSize) else { return }
        let screenSize = surface.pixelSize
        appState.screenSessions.sendMouseMove(
            deviceID: device.id,
            point: point,
            screenSize: screenSize,
            buttons: buttons
        )
    }

    private func sendMouseButton(
        button: ScrcpyMouseButton,
        isDown: Bool,
        location: CGPoint,
        viewportSize: CGSize,
        buttons: UInt32
    ) {
        guard let point = remotePoint(location: location, viewportSize: viewportSize) else { return }
        let screenSize = surface.pixelSize
        appState.screenSessions.sendMouseButton(
            deviceID: device.id,
            action: isDown ? .down : .up,
            button: button,
            point: point,
            screenSize: screenSize,
            buttons: buttons
        )
    }

    private func sendMouseScroll(
        location: CGPoint,
        viewportSize: CGSize,
        horizontal: CGFloat,
        vertical: CGFloat,
        buttons: UInt32
    ) {
        guard let point = remotePoint(location: location, viewportSize: viewportSize) else { return }
        let screenSize = surface.pixelSize
        appState.screenSessions.sendMouseScroll(
            deviceID: device.id,
            point: point,
            screenSize: screenSize,
            horizontal: horizontal,
            vertical: vertical,
            buttons: buttons
        )
    }

}

private struct ScrcpyInputOverlay: NSViewRepresentable {
    let isEnabled: Bool
    let onMouseMove: (CGPoint, UInt32) -> Void
    let onMouseButton: (ScrcpyMouseButton, Bool, CGPoint, UInt32) -> Void
    let onBack: () -> Void
    let onText: (String) -> Void
    let onPaste: (String) -> Void
    let onCopy: (UInt8) -> Void
    let onKeyCommand: (UInt32) -> Void
    let onScroll: (CGPoint, CGFloat, CGFloat, UInt32) -> Void

    func makeNSView(context: Context) -> ScrcpyInputEventView {
        let view = ScrcpyInputEventView()
        update(view)
        return view
    }

    func updateNSView(_ view: ScrcpyInputEventView, context: Context) {
        update(view)
    }

    private func update(_ view: ScrcpyInputEventView) {
        view.isEnabled = isEnabled
        view.onMouseMove = onMouseMove
        view.onMouseButton = onMouseButton
        view.onBack = onBack
        view.onText = onText
        view.onPaste = onPaste
        view.onCopy = onCopy
        view.onKeyCommand = onKeyCommand
        view.onScroll = onScroll
    }
}

final class ScrcpyInputEventView: NSView {
    var isEnabled = false
    var onMouseMove: ((CGPoint, UInt32) -> Void)?
    var onMouseButton: ((ScrcpyMouseButton, Bool, CGPoint, UInt32) -> Void)?
    var onBack: (() -> Void)?
    var onText: ((String) -> Void)?
    var onPaste: ((String) -> Void)?
    var onCopy: ((UInt8) -> Void)?
    var onKeyCommand: ((UInt32) -> Void)?
    var onScroll: ((CGPoint, CGFloat, CGFloat, UInt32) -> Void)?
    var markedText: NSMutableAttributedString?
    private var scrollNormalizer = ScrollNormalizer()
    private var lastGesturePhase: NSEvent.Phase = []
    private var lastMomentumPhase: NSEvent.Phase = []

    private var trackingArea: NSTrackingArea?
    private var buttons: UInt32 = 0
    private var isForwardingSecondaryClick = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isEnabled ? super.hitTest(point) : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        sendMouseMove(event)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMouseMove(event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouseButton(.primary, isDown: true, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseButton(.primary, isDown: false, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMouseMove(event)
    }

    // Match scrcpy SDK mouse bindings: right-click is Back; Shift-right-click is forwarded.
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isForwardingSecondaryClick = event.modifierFlags.contains(.shift)
        if isForwardingSecondaryClick {
            sendMouseButton(.secondary, isDown: true, event: event)
        } else {
            onBack?()
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard isForwardingSecondaryClick else { return }
        sendMouseButton(.secondary, isDown: false, event: event)
        isForwardingSecondaryClick = false
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard isForwardingSecondaryClick else { return }
        sendMouseMove(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let button = button(for: event) else { return }
        window?.makeFirstResponder(self)
        sendMouseButton(button, isDown: true, event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let button = button(for: event) else { return }
        sendMouseButton(button, isDown: false, event: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMouseMove(event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { return }
        let normalized = scrollNormalizer.normalizedDelta(for: event)
        logScrollLifecycleIfNeeded(normalized)
        guard normalized.horizontal != 0 || normalized.vertical != 0 else { return }

        onScroll?(
            location(for: event),
            normalized.horizontal,
            normalized.vertical,
            buttons
        )
    }

    private func sendMouseMove(_ event: NSEvent) {
        guard isEnabled else { return }
        onMouseMove?(location(for: event), buttons)
    }

    private func sendMouseButton(
        _ button: ScrcpyMouseButton,
        isDown: Bool,
        event: NSEvent
    ) {
        guard isEnabled else { return }
        if isDown {
            buttons |= button.rawValue
        } else {
            buttons &= ~button.rawValue
        }
        onMouseButton?(button, isDown, location(for: event), buttons)
    }

    private func button(for event: NSEvent) -> ScrcpyMouseButton? {
        switch event.buttonNumber {
        case 2: .tertiary
        case 3: .back
        case 4: .forward
        default: nil
        }
    }

    private struct NormalizedScrollEvent {
        let horizontal: CGFloat
        let vertical: CGFloat
        let phase: NSEvent.Phase
        let momentumPhase: NSEvent.Phase
        let isPrecise: Bool
    }

    private final class ScrollNormalizer {
        private let precisionStep = 0.25
        private let noiseThreshold: CGFloat = 0.001
        private let mouseWheelScale: CGFloat = 8
        private var residualX: CGFloat = 0
        private var residualY: CGFloat = 0

        func normalizedDelta(for event: NSEvent) -> NormalizedScrollEvent {
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
            let precisionScale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : mouseWheelScale
            let rawX = event.scrollingDeltaX * direction * precisionScale
            let rawY = event.scrollingDeltaY * direction * precisionScale
            let horizontal = nextDelta(rawX, residual: &residualX)
            let vertical = nextDelta(rawY, residual: &residualY)
            return NormalizedScrollEvent(
                horizontal: horizontal,
                vertical: vertical,
                phase: event.phase,
                momentumPhase: event.momentumPhase,
                isPrecise: event.hasPreciseScrollingDeltas
            )
        }

        private func nextDelta(_ raw: CGFloat, residual: inout CGFloat) -> CGFloat {
            let total = raw + residual
            guard total != 0 else { return 0 }
            let snapped = (total / precisionStep).rounded(.towardZero) * precisionStep
            residual = total - snapped

            if abs(snapped) < noiseThreshold {
                return 0
            }
            return snapped
        }
    }

    private func logScrollLifecycleIfNeeded(_ event: NormalizedScrollEvent) {
        #if DEBUG
        let phaseChanged = event.phase != lastGesturePhase
        let momentumChanged = event.momentumPhase != lastMomentumPhase
        if !phaseChanged && !momentumChanged { return }

        lastGesturePhase = event.phase
        lastMomentumPhase = event.momentumPhase

        NSLog(
            "scroll event lifecycle: gesture=%@ momentum=%@ precise=%@",
            String(describing: event.phase),
            String(describing: event.momentumPhase),
            String(event.isPrecise)
        )
        #endif
    }

    private func location(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}

struct ScrcpyContainerControlButton: View {
    let icon: String
    let help: LocalizedStringKey
    var isActive = false
    var isLoading = false
    var controlSize: CGFloat = 28
    var iconSize: CGFloat = 12.5
    var onLongPress: (() -> Void)?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: icon)
                        .font(AppTypography.caption.weight(.semibold))
                }
            }
            .foregroundColor(isActive ? AppTheme.accent : .primary)
            .frame(width: controlSize, height: controlSize)
            .appMaterialBackground(
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous),
                isActive: isHovered || isActive
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(
                        Color.primary.opacity(isHovered || isActive ? 0.12 : 0),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .disabled(isLoading)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 2)
                .onEnded { _ in onLongPress?() }
        )
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}
