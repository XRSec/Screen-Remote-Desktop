import AppKit
import SwiftUI

struct ScreenTileResizeEdges: OptionSet {
    let rawValue: Int

    static let top = ScreenTileResizeEdges(rawValue: 1 << 0)
    static let bottom = ScreenTileResizeEdges(rawValue: 1 << 1)
    static let leading = ScreenTileResizeEdges(rawValue: 1 << 2)
    static let trailing = ScreenTileResizeEdges(rawValue: 1 << 3)
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

enum ScrcpyParentContainerMode {
    case embedded
    case detached
}

struct ScrcpyParentContainer: View {
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
    var showsCloseButton = false
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
                    height: ScreenWindowMetrics.embeddedBottomControlsHeight
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

    private var screenStatusText: String {
        if session.phase.isWorking {
            return String.localizedKey(session.phase.localizationKey)
        }
        return session.batteryLevel.map { "\($0)%" }
            ?? String.localizedKey("sidebarDeviceConnected")
    }

    private var screenMetricsText: String? {
        guard surface.pixelSize.width > 0, surface.pixelSize.height > 0 else { return nil }
        let width = Int(surface.pixelSize.width.rounded())
        let height = Int(surface.pixelSize.height.rounded())
        let resolution = "\(width) × \(height)"
        var metrics = [resolution]
        let maxFPS = device.scrcpyOptions.maxFPS
        if maxFPS > 0 {
            metrics.append("≤\(maxFPS) FPS")
        }
        let videoBitrate = device.scrcpyOptions.videoBitrate
        if !videoBitrate.isEmpty {
            metrics.append(videoBitrate)
        }
        return metrics.joined(separator: " · ")
    }

    private var header: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 260
            let horizontalPadding: CGFloat = isCompact ? 4 : 10
            let contentSpacing: CGFloat = isCompact ? 3 : 6

            ZStack {
                HStack(spacing: contentSpacing) {
                    leadingControls(isCompact: isCompact)

                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(isCompact ? AppTypography.caption.weight(.semibold) : AppTypography.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if session.isConnected {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text(screenStatusText)
                                    .font(AppTypography.caption)
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                Text(String.localizedKey(session.phase.localizationKey))
                            )
                            .accessibilityValue(
                                session.batteryLevel.map { Text("\($0)%") } ?? Text("")
                            )
                        }
                        if !isCompact, let metrics = screenMetricsText {
                            Divider()
                                .frame(height: 12)
                            Text(metrics)
                                .font(AppTypography.monospacedCaption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .accessibilityLabel(Text("screensStreamMetrics"))
                                .accessibilityValue(Text(metrics))
                        }
                        if isCompact, let metrics = screenMetricsText {
                            Color.clear
                                .frame(width: 0, height: 0)
                                .accessibilityLabel(Text("screensStreamMetrics"))
                                .accessibilityValue(Text(metrics))
                        }
                    }
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
    }

}

private extension ScrcpyParentContainer {
    @ViewBuilder
    var detachedWindowDragArea: some View {
        if mode == .detached {
            WindowDragArea(isEnabled: showsChrome)
        }
    }

    @ViewBuilder
    private func leadingControls(isCompact: Bool) -> some View {
        let controlSize: CGFloat = isCompact ? 22 : 28
        let selectionLabel = String(
            format: String.localizedKey("screensDeviceScreen"),
            device.name
        )
        if mode == .embedded {
            HStack(spacing: isCompact ? 1 : 2) {
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(isCompact ? AppTypography.caption2.weight(.semibold) : AppTypography.caption.weight(.semibold))
                        .foregroundColor(isSelected ? AppTheme.accent : .secondary)
                        .frame(width: controlSize, height: controlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(selectionLabel)
                .accessibilityLabel(Text(selectionLabel))
                .accessibilityAddTraits(isSelected ? .isSelected : [])

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
            if showsCloseButton { screenCloseControl(controlSize: controlSize, iconSize: iconSize, action: onStop) }
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
            if mode == .detached { screenAlwaysOnTopControl(appState: appState, deviceID: device.id, controlSize: controlSize, iconSize: iconSize) }
            ScrcpySessionParametersMenu(
                deviceID: device.id,
                options: device.scrcpyOptions,
                remoteSerial: session.adbSerial,
                controlSize: controlSize,
                isDisabled: session.phase.isWorking
            )
        }
    }

    @ViewBuilder
    private var containerBackground: some View {
        let shape = RoundedRectangle(
            cornerRadius: ScreenWindowMetrics.containerCornerRadius,
            style: .continuous
        )
        if mode == .detached && !showsChrome {
            shape.fill(Color.clear)
        } else if showsChrome {
            Color.clear.appMaterialBackground(in: shape)
        } else {
            shape.fill(Color.black)
        }
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
            GeometryReader { proxy in
                if showsChrome || isSelected {
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
                } else {
                    RoundedRectangle(
                        cornerRadius: ScreenWindowMetrics.containerCornerRadius,
                        style: .continuous
                    )
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
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

}

private extension ScrcpyParentContainer {
    var borderColor: Color {
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

private extension ScrcpyParentContainer {
    var chromeHoverTracker: some View {
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

@MainActor
private func screenCloseControl(
    controlSize: CGFloat,
    iconSize: CGFloat,
    action: @escaping () -> Void
) -> some View {
    ScrcpyContainerControlButton(
        icon: "xmark",
        help: "commonClose",
        controlSize: controlSize,
        iconSize: iconSize,
        action: action
    )
}

@MainActor
private func screenAlwaysOnTopControl(
    appState: AppState,
    deviceID: UUID,
    controlSize: CGFloat,
    iconSize: CGFloat
) -> some View {
    let isAlwaysOnTop = appState.screenWindows.isAlwaysOnTop(deviceID)
    return ScrcpyContainerControlButton(
        icon: isAlwaysOnTop ? "pin.fill" : "pin",
        help: "screensAlwaysOnTop",
        isActive: isAlwaysOnTop,
        controlSize: controlSize,
        iconSize: iconSize,
        action: { appState.screenWindows.toggleAlwaysOnTop(for: deviceID) }
    )
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
