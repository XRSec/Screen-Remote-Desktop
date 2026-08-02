import AppKit
import SwiftUI

struct ScreenTileResizeEdges: OptionSet {
    let rawValue: Int

    static let top = ScreenTileResizeEdges(rawValue: 1 << 0)
    static let bottom = ScreenTileResizeEdges(rawValue: 1 << 1)
    static let leading = ScreenTileResizeEdges(rawValue: 1 << 2)
    static let trailing = ScreenTileResizeEdges(rawValue: 1 << 3)
}

struct SkeletonToolbarButton: View {
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

struct ScreenTile: View {
    static let chromeHeight = ScreenWindowMetrics.embeddedVerticalChrome
    static let horizontalChrome = ScreenWindowMetrics.containerHorizontalChrome

    let device: Device
    let isReference: Bool
    let isSelected: Bool
    let session: ScreenSessionSnapshot
    @ObservedObject var sessionManager: ScreenSessionManager
    @ObservedObject var surface: ScrcpyVideoSurface
    let rotation: Int
    let onSelect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRotate: () -> Void
    let onDetach: () -> Void
    let onAutoFit: () -> Void
    let onTitleDragChanged: (CGSize) -> Void
    let onTitleDragEnded: () -> Void
    let onResizeChanged: (ScreenTileResizeEdges, CGSize) -> Void
    let onResizeEnded: () -> Void
    let onVideoSizeChanged: (CGSize) -> Void

    var body: some View {
        ScrcpyParentContainer(
            mode: .embedded,
            device: device,
            isReference: isReference,
            isSelected: isSelected,
            session: session,
            sessionManager: sessionManager,
            surface: surface,
            rotation: rotation,
            onSelect: onSelect,
            onStop: onStop,
            onRotate: onRotate,
            onDetachOrDock: onDetach,
            onAutoFit: onAutoFit,
            onTitleDragChanged: onTitleDragChanged,
            onTitleDragEnded: onTitleDragEnded,
            onResizeChanged: onResizeChanged,
            onResizeEnded: onResizeEnded,
            onChromeVisibilityChanged: { _ in true }
        )
        .contextMenu {
            if session.isRunning || session.phase.isWorking {
                Button("screenSessionStop", action: onStop)
            } else {
                Button("screenSessionStart", action: onStart)
            }
            Button("screensDetach", action: onDetach)
        }
        .onChange(of: surface.pixelSize) { onVideoSizeChanged($0) }
    }
}

private enum ScrcpyParentContainerMode {
    case embedded
    case detached
}

private struct ScrcpyParentContainer: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.displayScale) private var displayScale
    let mode: ScrcpyParentContainerMode
    let device: Device
    let isReference: Bool
    let isSelected: Bool
    let session: ScreenSessionSnapshot
    @ObservedObject var sessionManager: ScreenSessionManager
    @ObservedObject var surface: ScrcpyVideoSurface
    let rotation: Int
    let onSelect: () -> Void
    let onStop: () -> Void
    let onRotate: () -> Void
    let onDetachOrDock: () -> Void
    let onAutoFit: () -> Void
    let onTitleDragChanged: (CGSize) -> Void
    let onTitleDragEnded: () -> Void
    let onResizeChanged: (ScreenTileResizeEdges, CGSize) -> Void
    let onResizeEnded: () -> Void
    let onChromeVisibilityChanged: (Bool) -> Bool
    @State private var isChromeVisible = false
    @State private var sourceViewportSize = CGSize.zero

    private var showsChrome: Bool {
        isChromeVisible
    }

    var body: some View {
        ZStack {
            containerContent

            chromeHoverTracker
        }
        .overlay(containerBorder.allowsHitTesting(false))
        .overlay(edgeResizeOverlay)
        .onPreferenceChange(ScreenSourceViewportSizeKey.self) { sourceViewportSize = $0 }
    }

    private var chromeHoverTracker: some View {
        GeometryReader { proxy in
            let topExpansion = mode == .embedded ? ScreenWindowMetrics.headerHeight : 0
            let bottomExpansion = mode == .embedded
                ? ScreenWindowMetrics.embeddedBottomControlsHeight
                : 0

            ScrcpyContainerEdgeHoverTracker(isVisible: isChromeVisible) { visible in
                guard onChromeVisibilityChanged(visible) else { return }
                if mode == .detached {
                    withAnimation(.easeOut(duration: ScreenWindowMetrics.chromeAnimationDuration)) {
                        isChromeVisible = visible
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isChromeVisible = visible
                    }
                }
            }
            .frame(
                width: proxy.size.width
                    + (mode == .embedded
                        ? ScreenWindowMetrics.embeddedChromeHorizontalGrowth
                        : 0),
                height: proxy.size.height + topExpansion + bottomExpansion
            )
            .offset(
                x: mode == .embedded
                    ? -ScreenWindowMetrics.embeddedChromeSideExpansion
                    : 0,
                y: -topExpansion
            )
        }
    }

    @ViewBuilder
    private var containerContent: some View {
        if mode == .detached {
            VStack(spacing: 0) {
                header
                    .frame(height: ScreenWindowMetrics.headerHeight)
                    .opacity(showsChrome ? 1 : 0)
                    .allowsHitTesting(showsChrome)
                    .disabled(!showsChrome)
                    .accessibilityHidden(!showsChrome)

                RotatedScrcpySurface(
                    device: device,
                    session: session,
                    surface: surface,
                    rotation: rotation
                )
                .padding(
                    .horizontal,
                    ScreenWindowMetrics.shellSideInset
                        + ScreenWindowMetrics.detachedChromeSideExpansion
                )
                .padding(.vertical, ScreenWindowMetrics.shellVerticalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrcpyBottomControls(
                    deviceID: device.id,
                    height: ScreenWindowMetrics.detachedBottomControlsHeight
                )
                    .frame(height: ScreenWindowMetrics.detachedBottomControlsHeight)
                    .opacity(showsChrome ? 1 : 0)
                    .allowsHitTesting(showsChrome)
                    .disabled(!showsChrome)
                    .accessibilityHidden(!showsChrome)
            }
            .background(containerBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: ScreenWindowMetrics.containerCornerRadius,
                    style: .continuous
                )
            )
        } else {
            ZStack {
                RotatedScrcpySurface(
                    device: device,
                    session: session,
                    surface: surface,
                    rotation: rotation
                )
                .padding(.horizontal, ScreenWindowMetrics.shellSideInset)
                .padding(.vertical, ScreenWindowMetrics.shellVerticalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(containerBackground)
            .background(embeddedOuterShell)
            .overlay(
                header
                    .frame(height: ScreenWindowMetrics.headerHeight)
                    .padding(
                        .horizontal,
                        -ScreenWindowMetrics.embeddedChromeSideExpansion
                    )
                    .opacity(showsChrome ? 1 : 0)
                    .allowsHitTesting(showsChrome)
                    .disabled(!showsChrome)
                    .accessibilityHidden(!showsChrome)
                    .offset(y: -ScreenWindowMetrics.headerHeight),
                alignment: .top
            )
            .overlay(
                ScrcpyBottomControls(
                    deviceID: device.id,
                    height: ScreenWindowMetrics.embeddedBottomControlsHeight,
                    usesTransparentBackground: true
                )
                    .frame(height: ScreenWindowMetrics.embeddedBottomControlsHeight)
                    .padding(
                        .horizontal,
                        -ScreenWindowMetrics.embeddedChromeSideExpansion
                    )
                    .opacity(showsChrome ? 1 : 0)
                    .allowsHitTesting(showsChrome)
                    .disabled(!showsChrome)
                    .accessibilityHidden(!showsChrome)
                    .offset(y: ScreenWindowMetrics.embeddedBottomControlsHeight),
                alignment: .bottom
            )
        }
    }

    private var header: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 260
            let horizontalPadding: CGFloat = isCompact ? 4 : 10
            let contentSpacing: CGFloat = isCompact ? 3 : 6

            ZStack {
                HStack(spacing: contentSpacing) {
                    leadingControls(isCompact: isCompact)

                    Text(device.name)
                        .font(.system(size: isCompact ? 11.5 : 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(detachedWindowDragArea)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                                .onChanged { value in
                                    guard mode == .embedded else { return }
                                    onTitleDragChanged(value.translation)
                                }
                                .onEnded { _ in
                                    guard mode == .embedded else { return }
                                    onTitleDragEnded()
                                }
                        )

                    trailingControls(isCompact: isCompact)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
        .background(
            mode == .detached
                ? AppTheme.surface.opacity(0.98)
                : Color.clear
        )
    }

    @ViewBuilder
    private var detachedWindowDragArea: some View {
        if mode == .detached {
            WindowDragArea(isEnabled: showsChrome)
        }
    }

    @ViewBuilder
    private func leadingControls(isCompact: Bool) -> some View {
        let controlSize: CGFloat = isCompact ? 22 : 28
        let iconSize: CGFloat = isCompact ? 11 : 14
        if mode == .embedded {
            HStack(spacing: isCompact ? 1 : 2) {
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(isSelected ? AppTheme.accent : .secondary)
                        .frame(width: controlSize, height: controlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ScrcpyContainerControlButton(
                    icon: "stop.fill",
                    help: "screenSessionStop",
                    controlSize: controlSize,
                    iconSize: isCompact ? 10 : 12.5,
                    action: onStop
                )
            }
        } else {
            Color.clear.frame(width: isCompact ? 52 : 72, height: controlSize)
        }
    }

    private func trailingControls(isCompact: Bool) -> some View {
        let controlSize: CGFloat = isCompact ? 22 : 28
        let iconSize: CGFloat = isCompact ? 10 : 12.5
        return HStack(spacing: isCompact ? 1 : 2) {
            let inspectorState = sessionManager.layoutInspectorState(for: device.id)
            ScrcpyContainerControlButton(
                icon: "sunglasses.fill",
                help: "screensLayoutAnalysis",
                isActive: inspectorState.isVisible,
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                appState.toggleScreenLayoutAnalysis(deviceID: device.id)
            }
            ScrcpyContainerControlButton(
                icon: "rectangle.portrait.arrowtriangle.2.inward",
                help: "screensAutoResizeWindow",
                controlSize: controlSize,
                iconSize: iconSize,
                action: onAutoFit
            )
            let resolutionState = sessionManager.resolutionAdjustmentState(for: device.id)
            let backingScale = max(displayScale, 1)
            let isResolutionAdapted = sessionManager.isResolutionAdaptedToViewport(
                deviceID: device.id,
                viewportSize: sourceViewportSize,
                backingScale: backingScale
            )
            ScrcpyContainerControlButton(
                icon: "rectangle.portrait.arrowtriangle.2.outward",
                help: isResolutionAdapted
                    ? "screensRestoreResolution"
                    : "screensAdaptResolution",
                isActive: isResolutionAdapted,
                isLoading: resolutionState.isBusy,
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                appState.toggleScreenResolutionAdjustment(
                    deviceID: device.id,
                    viewportSize: sourceViewportSize,
                    backingScale: backingScale
                )
            }
            ScrcpyContainerControlButton(
                icon: "arrow.trianglehead.2.clockwise",
                help: "screensControlRotate",
                controlSize: controlSize,
                iconSize: iconSize,
                action: onRotate
            )
            ScrcpyContainerControlButton(
                icon: mode == .embedded
                    ? "arrow.up.left.and.arrow.down.right"
                    : "arrow.down.right.and.arrow.up.left",
                help: mode == .embedded ? "screensDetach" : "screensDock",
                controlSize: controlSize,
                iconSize: iconSize,
                action: onDetachOrDock
            )
            ScrcpySessionParametersMenu(
                deviceID: device.id,
                options: device.scrcpyOptions,
                remoteSerial: session.adbSerial,
                controlSize: controlSize,
                isDisabled: session.phase.isWorking
            )
        }
    }

    private var containerBackground: some View {
        RoundedRectangle(
            cornerRadius: ScreenWindowMetrics.containerCornerRadius,
            style: .continuous
        )
        .fill(
            mode == .detached && !showsChrome
                ? Color.clear
                : (showsChrome ? AppTheme.surface : Color.black)
        )
    }

    private var embeddedOuterShell: some View {
        GeometryReader { proxy in
            RoundedRectangle(
                cornerRadius: ScreenWindowMetrics.containerCornerRadius,
                style: .continuous
            )
            .fill(AppTheme.surface.opacity(0.98))
            .frame(
                width: proxy.size.width
                    + ScreenWindowMetrics.embeddedChromeHorizontalGrowth,
                height: proxy.size.height
                    + ScreenWindowMetrics.headerHeight
                    + ScreenWindowMetrics.embeddedBottomControlsHeight
            )
            .offset(
                x: -ScreenWindowMetrics.embeddedChromeSideExpansion,
                y: -ScreenWindowMetrics.headerHeight
            )
        }
        .opacity(mode == .embedded && showsChrome ? 1 : 0)
    }

    @ViewBuilder
    private var containerBorder: some View {
        if mode == .embedded {
            if showsChrome || isSelected {
                GeometryReader { proxy in
                    RoundedRectangle(
                        cornerRadius: ScreenWindowMetrics.containerCornerRadius,
                        style: .continuous
                    )
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                    .frame(
                        width: proxy.size.width
                            + (showsChrome
                                ? ScreenWindowMetrics.embeddedChromeHorizontalGrowth
                                : 0),
                        height: proxy.size.height
                            + ScreenWindowMetrics.headerHeight
                            + ScreenWindowMetrics.embeddedBottomControlsHeight
                    )
                    .offset(
                        x: showsChrome
                            ? -ScreenWindowMetrics.embeddedChromeSideExpansion
                            : 0,
                        y: -ScreenWindowMetrics.headerHeight
                    )
                }
            }
        } else {
            RoundedRectangle(
                cornerRadius: ScreenWindowMetrics.containerCornerRadius,
                style: .continuous
            )
            .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            .opacity(mode == .detached && !showsChrome ? 0 : 1)
        }
    }

    private var borderColor: Color {
        isSelected
            ? AppTheme.accent
            : (isReference ? AppTheme.accent.opacity(0.35) : AppTheme.line)
    }

    @ViewBuilder
    private var edgeResizeOverlay: some View {
        if mode == .embedded {
            ScrcpyContainerEdgeResizeOverlay(
                onResizeChanged: onResizeChanged,
                onResizeEnded: onResizeEnded
            )
        }
    }
}

private struct ScrcpyContainerEdgeResizeOverlay: View {
    let onResizeChanged: (ScreenTileResizeEdges, CGSize) -> Void
    let onResizeEnded: () -> Void
    private let edgeHitSize: CGFloat = 8
    private let cornerHitSize: CGFloat = 16

    var body: some View {
        ZStack {
            resizeRegion(edges: .leading, cursor: .resizeLeftRight)
                .frame(width: edgeHitSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            resizeRegion(edges: .trailing, cursor: .resizeLeftRight)
                .frame(width: edgeHitSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            resizeRegion(edges: .top, cursor: .resizeUpDown)
                .frame(height: edgeHitSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            resizeRegion(edges: .bottom, cursor: .resizeUpDown)
                .frame(height: edgeHitSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            cornerRegion(
                edges: [.top, .leading],
                cursor: ScreenResizeCursors.northWestSouthEast,
                alignment: .topLeading
            )
            cornerRegion(
                edges: [.top, .trailing],
                cursor: ScreenResizeCursors.northEastSouthWest,
                alignment: .topTrailing
            )
            cornerRegion(
                edges: [.bottom, .leading],
                cursor: ScreenResizeCursors.northEastSouthWest,
                alignment: .bottomLeading
            )
            cornerRegion(
                edges: [.bottom, .trailing],
                cursor: ScreenResizeCursors.northWestSouthEast,
                alignment: .bottomTrailing
            )
        }
    }

    private func cornerRegion(
        edges: ScreenTileResizeEdges,
        cursor: NSCursor,
        alignment: Alignment
    ) -> some View {
        resizeRegion(edges: edges, cursor: cursor)
            .frame(width: cornerHitSize, height: cornerHitSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func resizeRegion(edges: ScreenTileResizeEdges, cursor: NSCursor) -> some View {
        ScreenResizeCursorRegion(cursor: cursor)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onResizeChanged(edges, $0.translation) }
                    .onEnded { _ in onResizeEnded() }
            )
            .help("screensDragResizeHelp")
    }
}

private enum ScreenResizeCursors {
    static let northWestSouthEast = diagonalCursor(
        symbolName: "arrow.up.left.and.arrow.down.right"
    )
    static let northEastSouthWest = diagonalCursor(
        symbolName: "arrow.up.right.and.arrow.down.left"
    )

    private static func diagonalCursor(symbolName: String) -> NSCursor {
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        ) else {
            return .resizeLeftRight
        }
        return NSCursor(
            image: image,
            hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2)
        )
    }
}

private struct ScreenResizeCursorRegion: View {
    let cursor: NSCursor
    @State private var isCursorPushed = false

    var body: some View {
        Color.clear
            .onHover { isHovered in
                if isHovered, !isCursorPushed {
                    cursor.push()
                    isCursorPushed = true
                } else if !isHovered, isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
            .onDisappear {
                if isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
    }
}

private struct ScrcpyContainerControlButton: View {
    let icon: String
    let help: LocalizedStringKey
    var isActive = false
    var isLoading = false
    var controlSize: CGFloat = 28
    var iconSize: CGFloat = 12.5
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .semibold))
                }
            }
            .foregroundColor(isActive ? AppTheme.accent : .primary)
            .frame(width: controlSize, height: controlSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .help(Text(help))
    }
}

private struct ScrcpySessionParametersMenu: View {
    @EnvironmentObject private var appState: AppState
    let deviceID: UUID
    let options: ScrcpyDeviceOptions
    let remoteSerial: String
    let controlSize: CGFloat
    let isDisabled: Bool

    var body: some View {
        ScrcpySessionParametersMenuButton(
            appState: appState,
            deviceID: deviceID,
            options: options,
            remoteSerial: remoteSerial,
            isDisabled: isDisabled
        )
        .frame(width: controlSize, height: controlSize)
        .help("screensSessionParameters")
    }
}

private struct ScrcpySessionParametersMenuButton: NSViewRepresentable {
    let appState: AppState
    let deviceID: UUID
    let options: ScrcpyDeviceOptions
    let remoteSerial: String
    let isDisabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            appState: appState,
            deviceID: deviceID,
            options: options,
            remoteSerial: remoteSerial
        )
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        context.coordinator.update(button, options: options, isDisabled: isDisabled)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.deviceID = deviceID
        context.coordinator.remoteSerial = remoteSerial
        context.coordinator.update(button, options: options, isDisabled: isDisabled)
    }

    final class Coordinator: NSObject {
        let appState: AppState
        var deviceID: UUID
        var remoteSerial: String
        private var options: ScrcpyDeviceOptions

        init(
            appState: AppState,
            deviceID: UUID,
            options: ScrcpyDeviceOptions,
            remoteSerial: String
        ) {
            self.appState = appState
            self.deviceID = deviceID
            self.options = options
            self.remoteSerial = remoteSerial
        }

        func update(_ button: NSButton, options: ScrcpyDeviceOptions, isDisabled: Bool) {
            self.options = options
            button.image = NSImage(
                systemSymbolName: "ellipsis.circle",
                accessibilityDescription: String.localizedKey("screensSessionParameters")
            )
            button.contentTintColor = .labelColor
            button.toolTip = String.localizedKey("screensSessionParameters")
            button.isEnabled = !isDisabled
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = makeMenu()
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height),
                in: sender
            )
        }

        private enum MenuAction {
            case maxSize(Int)
            case videoBitrate(String)
            case maxFPS(Int)
            case videoEncoder(String)
            case videoDecoder(String)
            case enableAudio(Bool)
            case audioBitrate(String)
            case audioEncoder(String)
            case audioDecoder(String)
            case audioVolume(Double)
            case compatibilityMode(Bool)
            case gameMode(Bool)
            case showFloatingBall(Bool)
            case enableHardwareDecoding(Bool)
            case clipboardSync(Bool)
            case turnScreenOff(Bool)
            case cleanupOnDisconnect(Bool)
            case powerOffOnClose(Bool)
            case keepControllerAwake(Bool)
            case keepDeviceAwake(Bool)
            case ignoreVideoEncoderConstraints(Bool)
            case newDisplayEnabled(Bool)
            case virtualDisplaySystemDecorations(Bool)
            case preserveVirtualDisplayContent(Bool)
        }

        private func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            addSubmenu(
                to: menu,
                titleKey: "screensImageQuality",
                menu: makeImageQualityMenu()
            )
            addSubmenu(
                to: menu,
                titleKey: "addDeviceMaxFrameRate",
                menu: makeFrameRateMenu()
            )
            addSubmenu(
                to: menu,
                titleKey: "addDeviceVideoBitrate",
                menu: makeVideoBitrateMenu()
            )
            addSubmenu(
                to: menu,
                titleKey: "addDeviceVideoSection",
                menu: makeVideoCodecMenu()
            )
            menu.addItem(.separator())
            addSubmenu(
                to: menu,
                titleKey: "sessionAudioSection",
                menu: makeAudioMenu()
            )
            addSubmenu(
                to: menu,
                titleKey: "sessionConnectionOptionsSection",
                menu: makeConnectionOptionsMenu()
            )
            addSubmenu(
                to: menu,
                titleKey: "sessionOtherOptionsSection",
                menu: makeOtherOptionsMenu()
            )
            addSubmenu(
                to: menu,
                titleKey: "sessionVirtualDisplaySection",
                menu: makeVirtualDisplayMenu()
            )
            return menu
        }

        private func makeImageQualityMenu() -> NSMenu {
            let menu = NSMenu()
            for preset in ScreenQualityPreset.allCases {
                addChoice(
                    to: menu,
                    title: String.localizedKey(preset.localizationKey),
                    selected: options.maxSize == preset.maxSize,
                    action: .maxSize(preset.maxSize)
                )
            }
            if options.maxSize > 0 && !ScreenQualityPreset.allCases.contains(where: { $0.maxSize == options.maxSize }) {
                addChoice(
                    to: menu,
                    title: "\(options.maxSize)P",
                    selected: true,
                    action: .maxSize(options.maxSize),
                    enabled: false
                )
            }
            return menu
        }

        private func makeFrameRateMenu() -> NSMenu {
            let menu = NSMenu()
            let values = [15, 30, 60, 90, 120]
            for value in values {
                addChoice(
                    to: menu,
                    title: "\(value) FPS",
                    selected: options.maxFPS == value,
                    action: .maxFPS(value)
                )
            }
            if options.maxFPS == 0 {
                addChoice(
                    to: menu,
                    title: String.localizedKey("sessionDefault"),
                    selected: true,
                    action: .maxFPS(0)
                )
            } else if !values.contains(options.maxFPS) {
                addChoice(
                    to: menu,
                    title: "\(options.maxFPS) FPS",
                    selected: true,
                    action: .maxFPS(options.maxFPS),
                    enabled: false
                )
            }
            return menu
        }

        private func makeVideoBitrateMenu() -> NSMenu {
            let menu = NSMenu()
            let values = ["700K", "1M", "2M", "4M", "8M", "12M", "20M", "40M", "80M", "120M"]
            for value in values {
                addChoice(
                    to: menu,
                    title: value,
                    selected: options.videoBitrate.caseInsensitiveCompare(value) == .orderedSame,
                    action: .videoBitrate(value)
                )
            }
            if !options.videoBitrate.isEmpty && !values.contains(where: {
                $0.caseInsensitiveCompare(options.videoBitrate) == .orderedSame
            }) {
                addChoice(
                    to: menu,
                    title: options.videoBitrate,
                    selected: true,
                    action: .videoBitrate(options.videoBitrate),
                    enabled: false
                )
            }
            return menu
        }

        private func makeVideoCodecMenu() -> NSMenu {
            let menu = NSMenu()
            addSubmenu(
                to: menu,
                titleKey: "sessionVideoEncoder",
                menu: makeRemoteEncoderMenu(
                    kind: .video,
                    current: options.videoEncoder,
                    action: { .videoEncoder($0) }
                )
            )
            addSubmenu(
                to: menu,
                titleKey: "sessionVideoDecoder",
                menu: makeVideoDecoderMenu()
            )
            return menu
        }

        private func makeAudioMenu() -> NSMenu {
            let menu = NSMenu()
            addToggle(
                to: menu,
                titleKey: "addDeviceForwardAudio",
                selected: options.enableAudio,
                action: .enableAudio(!options.enableAudio),
                enabled: !options.compatibilityMode
            )
            addSubmenu(
                to: menu,
                titleKey: "sessionAudioBitrate",
                menu: makeAudioBitrateMenu(),
                enabled: options.enableAudio && !options.compatibilityMode
            )
            addSubmenu(
                to: menu,
                titleKey: "sessionAudioEncoder",
                menu: makeRemoteEncoderMenu(
                    kind: .audio,
                    current: options.audioEncoder,
                    action: { .audioEncoder($0) }
                ),
                enabled: options.enableAudio && !options.compatibilityMode
            )
            addSubmenu(
                to: menu,
                titleKey: "sessionAudioDecoder",
                menu: makeAudioDecoderMenu(),
                enabled: options.enableAudio && !options.compatibilityMode
            )
            addSubmenu(
                to: menu,
                titleKey: "sessionAudioVolume",
                menu: makeAudioVolumeMenu(),
                enabled: options.enableAudio && !options.compatibilityMode
            )
            return menu
        }

        private func makeAudioBitrateMenu() -> NSMenu {
            let menu = NSMenu()
            let values = ["64K", "128K", "192K", "256K"]
            for value in values {
                addChoice(
                    to: menu,
                    title: value,
                    selected: options.audioBitrate.caseInsensitiveCompare(value) == .orderedSame,
                    action: .audioBitrate(value)
                )
            }
            if !options.audioBitrate.isEmpty && !values.contains(where: {
                $0.caseInsensitiveCompare(options.audioBitrate) == .orderedSame
            }) {
                addChoice(
                    to: menu,
                    title: options.audioBitrate,
                    selected: true,
                    action: .audioBitrate(options.audioBitrate),
                    enabled: false
                )
            }
            return menu
        }

        private func makeAudioVolumeMenu() -> NSMenu {
            let menu = NSMenu()
            let values = [1.0, 1.5, 2.0, 2.5, 3.0]
            let current = min(max(options.audioVolume, 1), 3)
            for value in values {
                addChoice(
                    to: menu,
                    title: "\(Int(value * 100))%",
                    selected: abs(current - value) < 0.001,
                    action: .audioVolume(value)
                )
            }
            if !values.contains(where: { abs(current - $0) < 0.001 }) {
                addChoice(
                    to: menu,
                    title: "\(Int((current * 100).rounded()))%",
                    selected: true,
                    action: .audioVolume(current),
                    enabled: false
                )
            }
            return menu
        }

        private func makeConnectionOptionsMenu() -> NSMenu {
            let menu = NSMenu()
            addToggle(
                to: menu,
                titleKey: "sessionCompatibilityMode",
                selected: options.compatibilityMode,
                action: .compatibilityMode(!options.compatibilityMode)
            )
            addToggle(
                to: menu,
                titleKey: "sessionGameMode",
                selected: options.gameMode,
                action: .gameMode(!options.gameMode),
                enabled: !options.compatibilityMode
            )
            addToggle(
                to: menu,
                titleKey: "sessionFloatingBall",
                selected: options.showFloatingBall,
                action: .showFloatingBall(!options.showFloatingBall)
            )
            addToggle(
                to: menu,
                titleKey: "sessionHardwareDecoding",
                selected: options.enableHardwareDecoding,
                action: .enableHardwareDecoding(!options.enableHardwareDecoding),
                enabled: !options.compatibilityMode
            )
            return menu
        }

        private func makeOtherOptionsMenu() -> NSMenu {
            let menu = NSMenu()
            addToggle(
                to: menu,
                titleKey: "addDeviceSyncClipboard",
                selected: options.clipboardSync,
                action: .clipboardSync(!options.clipboardSync),
                enabled: !options.compatibilityMode
            )
            addToggle(
                to: menu,
                titleKey: "addDeviceTurnScreenOff",
                selected: options.turnScreenOff,
                action: .turnScreenOff(!options.turnScreenOff),
                enabled: !options.compatibilityMode
            )
            addToggle(
                to: menu,
                titleKey: "sessionCleanupOnDisconnect",
                selected: options.cleanupOnDisconnect,
                action: .cleanupOnDisconnect(!options.cleanupOnDisconnect)
            )
            addToggle(
                to: menu,
                titleKey: "sessionPowerOffOnClose",
                selected: options.powerOffOnClose,
                action: .powerOffOnClose(!options.powerOffOnClose),
                enabled: options.cleanupOnDisconnect && !options.compatibilityMode
            )
            addToggle(
                to: menu,
                titleKey: "sessionKeepControllerAwake",
                selected: options.keepControllerAwake,
                action: .keepControllerAwake(!options.keepControllerAwake)
            )
            addToggle(
                to: menu,
                titleKey: "addDeviceKeepAwake",
                selected: options.keepDeviceAwake,
                action: .keepDeviceAwake(!options.keepDeviceAwake),
                enabled: options.cleanupOnDisconnect && !options.compatibilityMode
            )
            addToggle(
                to: menu,
                titleKey: "sessionIgnoreEncoderConstraints",
                selected: options.ignoreVideoEncoderConstraints,
                action: .ignoreVideoEncoderConstraints(!options.ignoreVideoEncoderConstraints),
                enabled: !options.compatibilityMode
            )
            return menu
        }

        private func makeVirtualDisplayMenu() -> NSMenu {
            let menu = NSMenu()
            addToggle(
                to: menu,
                titleKey: "sessionNewDisplay",
                selected: options.newDisplayEnabled,
                action: .newDisplayEnabled(!options.newDisplayEnabled),
                enabled: !options.compatibilityMode
            )
            addToggle(
                to: menu,
                titleKey: "sessionDisplaySystemUI",
                selected: options.virtualDisplaySystemDecorations,
                action: .virtualDisplaySystemDecorations(!options.virtualDisplaySystemDecorations),
                enabled: options.newDisplayEnabled && !options.compatibilityMode
            )
            addToggle(
                to: menu,
                titleKey: "sessionPreserveDisplay",
                selected: options.preserveVirtualDisplayContent,
                action: .preserveVirtualDisplayContent(!options.preserveVirtualDisplayContent),
                enabled: options.newDisplayEnabled && !options.compatibilityMode
            )
            return menu
        }

        private func makeRemoteEncoderMenu(
            kind: ScrcpyMediaKind,
            current: String,
            action: (String) -> MenuAction
        ) -> NSMenu {
            let menu = NSMenu()
            addChoice(
                to: menu,
                title: String.localizedKey("sessionDefault"),
                selected: current.isEmpty,
                action: action("")
            )
            let supportedCodecs: Set<String> = kind == .video
                ? ["h264", "h265"]
                : ["opus", "aac", "flac"]
            let encoders = ScrcpyCodecCapabilityCache
                .remoteEncoders(for: remoteSerial, kind: kind)
                .filter { supportedCodecs.contains($0.codec) }
                .sorted {
                    if $0.codec != $1.codec { return $0.codec < $1.codec }
                    if $0.acceleration.rank != $1.acceleration.rank {
                        return $0.acceleration.rank < $1.acceleration.rank
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            var displayedNames = Set<String>()
            for encoder in encoders where displayedNames.insert(encoder.name).inserted {
                addChoice(
                    to: menu,
                    title: "\(displayCodecName(encoder.codec)) · \(encoder.name)",
                    selected: current == encoder.name,
                    action: action(encoder.name)
                )
            }
            if !current.isEmpty && !displayedNames.contains(current) {
                addChoice(
                    to: menu,
                    title: current,
                    selected: true,
                    action: action(current),
                    enabled: false
                )
            }
            return menu
        }

        private func makeVideoDecoderMenu() -> NSMenu {
            let menu = NSMenu()
            addChoice(
                to: menu,
                title: String.localizedKey("sessionDefault"),
                selected: options.videoDecoder.isEmpty,
                action: .videoDecoder("")
            )
            let decoders = [
                (id: "videotoolbox.h264", title: "VideoToolbox · H264"),
                (id: "videotoolbox.hevc", title: "VideoToolbox · H265")
            ]
            var displayedIDs = Set<String>()
            for decoder in decoders {
                displayedIDs.insert(decoder.id)
                addChoice(
                    to: menu,
                    title: decoder.title,
                    selected: options.videoDecoder == decoder.id,
                    action: .videoDecoder(decoder.id)
                )
            }
            if !options.videoDecoder.isEmpty && !displayedIDs.contains(options.videoDecoder) {
                addChoice(
                    to: menu,
                    title: options.videoDecoder,
                    selected: true,
                    action: .videoDecoder(options.videoDecoder),
                    enabled: false
                )
            }
            return menu
        }

        private func makeAudioDecoderMenu() -> NSMenu {
            let menu = NSMenu()
            addChoice(
                to: menu,
                title: String.localizedKey("sessionDefault"),
                selected: options.audioDecoder.isEmpty,
                action: .audioDecoder("")
            )
            let decoders = coreAudioDecoderCapabilities()
            var displayedIDs = Set<String>()
            for decoder in decoders {
                displayedIDs.insert(decoder.id)
                let title = decoder.codec == "raw"
                    ? "Core Audio · PCM"
                    : "Core Audio · \(decoder.codec.uppercased())"
                addChoice(
                    to: menu,
                    title: title,
                    selected: options.audioDecoder == decoder.id,
                    action: .audioDecoder(decoder.id)
                )
            }
            if !options.audioDecoder.isEmpty && !displayedIDs.contains(options.audioDecoder) {
                addChoice(
                    to: menu,
                    title: options.audioDecoder,
                    selected: true,
                    action: .audioDecoder(options.audioDecoder),
                    enabled: false
                )
            }
            return menu
        }

        private func displayCodecName(_ codec: String) -> String {
            switch codec.lowercased() {
            case "h264": return "H264"
            case "h265", "hevc": return "H265"
            case "opus": return "OPUS"
            case "aac": return "AAC"
            case "flac": return "FLAC"
            default: return codec.uppercased()
            }
        }

        private func addSubmenu(
            to menu: NSMenu,
            titleKey: String,
            menu submenu: NSMenu,
            enabled: Bool = true
        ) {
            let item = NSMenuItem(title: String.localizedKey(titleKey), action: nil, keyEquivalent: "")
            item.submenu = submenu
            item.isEnabled = enabled
            menu.addItem(item)
        }

        private func addChoice(
            to menu: NSMenu,
            title: String,
            selected: Bool,
            action: MenuAction,
            enabled: Bool = true
        ) {
            let item = NSMenuItem(title: title, action: #selector(selectItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            item.state = selected ? .on : .off
            item.isEnabled = enabled
            menu.addItem(item)
        }

        private func addToggle(
            to menu: NSMenu,
            titleKey: String,
            selected: Bool,
            action: MenuAction,
            enabled: Bool = true
        ) {
            addChoice(
                to: menu,
                title: String.localizedKey(titleKey),
                selected: selected,
                action: action,
                enabled: enabled
            )
        }

        @MainActor
        @objc private func selectItem(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? MenuAction else { return }
            appState.updateScreenOptions(deviceID: deviceID) { options in
                switch action {
                case .maxSize(let value): options.maxSize = value
                case .videoBitrate(let value): options.videoBitrate = value
                case .maxFPS(let value): options.maxFPS = value
                case .videoEncoder(let value): options.videoEncoder = value
                case .videoDecoder(let value): options.videoDecoder = value
                case .enableAudio(let value): options.enableAudio = value
                case .audioBitrate(let value): options.audioBitrate = value
                case .audioEncoder(let value): options.audioEncoder = value
                case .audioDecoder(let value): options.audioDecoder = value
                case .audioVolume(let value): options.audioVolume = value
                case .compatibilityMode(let value): options.compatibilityMode = value
                case .gameMode(let value): options.gameMode = value
                case .showFloatingBall(let value): options.showFloatingBall = value
                case .enableHardwareDecoding(let value): options.enableHardwareDecoding = value
                case .clipboardSync(let value): options.clipboardSync = value
                case .turnScreenOff(let value): options.turnScreenOff = value
                case .cleanupOnDisconnect(let value): options.cleanupOnDisconnect = value
                case .powerOffOnClose(let value): options.powerOffOnClose = value
                case .keepControllerAwake(let value): options.keepControllerAwake = value
                case .keepDeviceAwake(let value): options.keepDeviceAwake = value
                case .ignoreVideoEncoderConstraints(let value): options.ignoreVideoEncoderConstraints = value
                case .newDisplayEnabled(let value): options.newDisplayEnabled = value
                case .virtualDisplaySystemDecorations(let value): options.virtualDisplaySystemDecorations = value
                case .preserveVirtualDisplayContent(let value): options.preserveVirtualDisplayContent = value
                }
            }
        }
    }
}

private struct ScrcpyBottomControls: View {
    @EnvironmentObject private var appState: AppState
    let deviceID: UUID
    let height: CGFloat
    var usesTransparentBackground = false

    private var controlSize: CGFloat { height }
    private var iconSize: CGFloat { height < 30 ? 14 : 16 }

    var body: some View {
        HStack(spacing: 4) {
            ScrcpyContainerControlButton(
                icon: "arrow.uturn.backward.circle",
                help: "screensControlBack",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 4, action: "back")
            }
            ScrcpyContainerControlButton(
                icon: "house.circle",
                help: "screensControlHome",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 3, action: "home")
            }
            ScrcpyContainerControlButton(
                icon: "square.stack.3d.down.right",
                help: "screensControlAppSwitcher",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 187, action: "appSwitcher")
            }
            ScrcpyContainerControlButton(
                icon: "speaker.wave.2.circle",
                help: "screensControlVolumeUp",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 24, action: "volumeUp")
            }
            ScrcpyContainerControlButton(
                icon: "lock.fill",
                help: "screensControlPower",
                controlSize: controlSize,
                iconSize: iconSize
            ) {
                appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 26, action: "power")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            usesTransparentBackground
                ? Color.clear
                : AppTheme.surface.opacity(0.98)
        )
    }
}

private struct RotatedScrcpySurface: View {
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.78)))
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .padding(10)
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
        view.onScroll = onScroll
    }
}

private final class ScrcpyInputEventView: NSView {
    var isEnabled = false
    var onMouseMove: ((CGPoint, UInt32) -> Void)?
    var onMouseButton: ((ScrcpyMouseButton, Bool, CGPoint, UInt32) -> Void)?
    var onScroll: ((CGPoint, CGFloat, CGFloat, UInt32) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var buttons: UInt32 = 0

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

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouseButton(.secondary, isDown: true, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouseButton(.secondary, isDown: false, event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
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
        onScroll?(
            location(for: event),
            event.scrollingDeltaX,
            event.scrollingDeltaY,
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

    private func location(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}

struct ScrcpySurfacePlaceholder: View {
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
            appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 3, action: "home")
        case .back:
            appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 4, action: "back")
        case .appSwitcher:
            appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 187, action: "appSwitcher")
        case .volumeUp:
            appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 24, action: "volumeUp")
        case .volumeDown:
            appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 25, action: "volumeDown")
        case .power:
            appState.sendScreenKeyEvent(deviceID: deviceID, keyCode: 26, action: "power")
        }
    }
}

private struct ScreenSourceViewportSizeKey: PreferenceKey {
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

private struct ScrcpyContainerEdgeHoverTracker: NSViewRepresentable {
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

private final class ScrcpyContainerEdgeTrackingView: NSView {
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
