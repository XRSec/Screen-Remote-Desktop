import AppKit
import SwiftUI

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
    @State private var workspaceFrame = CGRect.zero
    @State private var workspaceSize = CGSize.zero
    @State private var tileFrames: [UUID: ScreenTileFrame] = [:]
    @State private var autoArrangedPixelSizes: [UUID: CGSize] = [:]
    @State private var dragStartOrigins: [UUID: CGPoint] = [:]
    @State private var resizeStartFrames: [UUID: ScreenTileFrame] = [:]

    private var connectedDevices: [Device] {
        appState.visibleDeviceOffsets()
            .map(\.element)
            .filter { device in
                let session = sessionManager.session(for: device.id)
                return session.isConnected || session.phase.isWorking
            }
    }

    private var dockedDevices: [Device] {
        connectedDevices.filter { !coordinator.isDetached($0.id) }
    }

    private var allVisibleSelected: Bool {
        !connectedDevices.isEmpty && connectedDevices.allSatisfy { selectedDeviceIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.55)
            workspace
        }
        .background(AppTheme.background)
        .onChange(of: connectedDevices.map(\.id)) { ids in
            selectedDeviceIDs.formIntersection(ids)
            tileFrames = tileFrames.filter { ids.contains($0.key) }
            autoArrangedPixelSizes = autoArrangedPixelSizes.filter { ids.contains($0.key) }
            arrangeTiles(for: connectedDevices)
            syncLastDockedTileSizes(in: workspaceSize)
        }
        .onChange(of: coordinator.detachedScreenIDs) { _ in
            syncLastDockedTileSizes(in: workspaceSize)
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

            Spacer(minLength: 8)

            Button {
                arrangeTiles(for: connectedDevices)
            } label: {
                Label("screensAutoArrange", systemImage: "rectangle.3.group")
            }
            .help("screensAutoArrangeHelp")

        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var workspace: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if connectedDevices.isEmpty {
                    emptyState
                } else if dockedDevices.isEmpty {
                    allDetachedState
                } else {
                    ForEach(dockedDevices) { device in
                        if let frame = tileFrames[device.id] {
                            ScreenTile(
                                device: device,
                                isReference: device.id == connectedDevices.first?.id,
                                isSelected: selectedDeviceIDs.contains(device.id),
                                session: sessionManager.session(for: device.id),
                                sessionManager: sessionManager,
                                surface: sessionManager.videoSurface(for: device.id),
                                rotation: coordinator.screenRotation(for: device.id),
                                onSelect: { toggleSelection(device.id) },
                                onStart: { appState.startScreenSession(deviceID: device.id) },
                                onStop: { appState.stopScreenSession(deviceID: device.id) },
                                onRotate: {
                                    coordinator.toggleScreenRotation(for: device.id)
                                    arrangeTiles(for: connectedDevices)
                                },
                                onDetach: { coordinator.detach(device, appState: appState) },
                                onAutoFit: {
                                    autoFitTileToDevice(device.id, in: proxy.size)
                                },
                                onTitleDragChanged: { translation in
                                    moveTile(device.id, by: translation, in: proxy.size)
                                },
                                onTitleDragEnded: {
                                    dragStartOrigins.removeValue(forKey: device.id)
                                },
                                onResizeChanged: { edges, translation in
                                    resizeTile(
                                        device.id,
                                        edges: edges,
                                        by: translation,
                                        in: proxy.size
                                    )
                                },
                                onResizeEnded: {
                                    resizeStartFrames.removeValue(forKey: device.id)
                                },
                                onVideoSizeChanged: { pixelSize in
                                    guard pixelSize.width > 0, pixelSize.height > 0,
                                          autoArrangedPixelSizes[device.id] != pixelSize else {
                                        return
                                    }
                                    autoArrangedPixelSizes[device.id] = pixelSize
                                    arrangeTiles(for: connectedDevices)
                                }
                            )
                            .frame(width: frame.size.width, height: frame.size.height)
                            .position(
                                x: frame.origin.x + frame.size.width / 2,
                                y: frame.origin.y + frame.size.height / 2
                            )
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(
                GeometryReader { workspaceProxy in
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                        )
                        .padding(8)
                        .onAppear {
                            workspaceFrame = workspaceProxy.frame(in: .global)
                            workspaceSize = workspaceProxy.size
                            arrangeTiles(for: connectedDevices)
                            syncLastDockedTileSizes(in: workspaceProxy.size)
                        }
                        .onChange(of: workspaceProxy.size) { _ in
                            workspaceFrame = workspaceProxy.frame(in: .global)
                            workspaceSize = workspaceProxy.size
                        }
                }
            )
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        workspaceState(
            icon: "rectangle.on.rectangle.slash",
            title: "screensEmptyTitle",
            detail: "screensEmptyDetail"
        )
    }

    private var allDetachedState: some View {
        workspaceState(
            icon: "macwindow.on.rectangle",
            title: "screensAllDetachedTitle",
            detail: "screensAllDetachedDetail"
        )
    }

    private func workspaceState(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        VStack(spacing: AppSpacing.lg) {
            AppIconTile(symbol: icon, color: AppTheme.accent, size: 52)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.title)
                Text(detail)
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: 420)
        .appCard(radius: AppRadius.large)
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private extension ScreensWorkspace {
    func toggleSelection(_ id: UUID) {
        if !selectedDeviceIDs.insert(id).inserted {
            selectedDeviceIDs.remove(id)
        }
    }

    private func selectAll(_ selected: Bool) {
        if selected {
            selectedDeviceIDs.formUnion(connectedDevices.map(\.id))
        } else {
            selectedDeviceIDs.subtract(connectedDevices.map(\.id))
        }
    }

    private func arrangeTiles(for devices: [Device]) {
        let layoutDevices = devices
            .filter { !coordinator.isDetached($0.id) }
            .sorted {
                resolvedScreenAspectRatio(for: $0) < resolvedScreenAspectRatio(for: $1)
            }
        guard !layoutDevices.isEmpty else { return }
        guard workspaceSize.width > 32, workspaceSize.height > 32 else { return }

        let availableWidth = workspaceSize.width - 32
        let availableHeight = workspaceSize.height
            - 32
            - ScreenWindowMetrics.headerHeight
            - ScreenWindowMetrics.embeddedBottomControlsHeight
        let horizontalSpacing: CGFloat = 16
        let rowSpacing = horizontalSpacing
            + ScreenWindowMetrics.headerHeight
            + ScreenWindowMetrics.embeddedBottomControlsHeight
        tileFrames = tileFrames.filter { entry in
            devices.contains(where: { device in device.id == entry.key })
        }

        let rowCounts = layoutRowCounts(for: layoutDevices.count)
        var bestFrames: [UUID: ScreenTileFrame] = [:]
        var bestScore = -CGFloat.greatestFiniteMagnitude

        for counts in rowCounts {
            var rows: [[Device]] = []
            var cursor = 0
            for count in counts {
                rows.append(Array(layoutDevices[cursor..<(cursor + count)]))
                cursor += count
            }

            let rowRatios = rows.map { row in
                row.map(resolvedScreenAspectRatio(for:))
            }
            let naturalVideoHeights = rowRatios.map { ratios in
                let totalHorizontalSpacing = CGFloat(max(0, ratios.count - 1))
                    * horizontalSpacing
                let containerChrome = CGFloat(ratios.count) * ScreenTile.horizontalChrome
                return max(1, availableWidth - totalHorizontalSpacing - containerChrome)
                    / max(ratios.reduce(0, +), 0.25)
            }
            let verticalSpacing = CGFloat(max(0, rows.count - 1)) * rowSpacing
            let availableVideoHeight = availableHeight
                - CGFloat(rows.count) * ScreenTile.chromeHeight
                - verticalSpacing
            guard availableVideoHeight > 0 else { continue }
            let heightScale = min(
                1,
                availableVideoHeight / max(naturalVideoHeights.reduce(0, +), 1)
            )
            let videoHeights = naturalVideoHeights.map { $0 * heightScale }
            let score = rowRatios.enumerated().reduce(CGFloat.zero) { result, entry in
                result + entry.element.reduce(0, +) * videoHeights[entry.offset] * videoHeights[entry.offset]
            }

            guard score > bestScore else { continue }
            bestScore = score
            bestFrames.removeAll(keepingCapacity: true)

            var verticalOffset = 16 + ScreenWindowMetrics.headerHeight
            for (rowIndex, row) in rows.enumerated() {
                let videoHeight = videoHeights[rowIndex]
                let height = ScreenTile.chromeHeight + videoHeight
                let widths = rowRatios[rowIndex].map {
                    $0 * videoHeight + ScreenTile.horizontalChrome
                }
                let rowContentWidth = widths.reduce(0, +)
                    + horizontalSpacing * CGFloat(max(0, widths.count - 1))
                let xOffset = 16 + max(0, (availableWidth - rowContentWidth) / 2)
                var horizontalOffset = xOffset
                for column in row.indices {
                    let device = row[column]
                    let width = widths[column]
                    bestFrames[device.id] = ScreenTileFrame(
                        origin: CGPoint(x: horizontalOffset, y: verticalOffset),
                        size: CGSize(width: width, height: height)
                    )
                    horizontalOffset += width + horizontalSpacing
                }
                verticalOffset += height + rowSpacing
            }
        }

        tileFrames.merge(bestFrames) { _, new in new }
    }

    private func resolvedScreenAspectRatio(for device: Device) -> CGFloat {
        let sourceAspectRatio = ScreenWindowMetrics.resolvedAspectRatio(
            device: device,
            session: sessionManager.session(for: device.id),
            pixelSize: sessionManager.videoSurface(for: device.id).pixelSize
        )
        return coordinator.screenRotation(for: device.id) % 180 == 0
            ? sourceAspectRatio
            : 1 / sourceAspectRatio
    }

    private func layoutRowCounts(for deviceCount: Int) -> [[Int]] {
        guard deviceCount > 0 else { return [] }
        var layouts = [[deviceCount]]
        if deviceCount > 1 {
            layouts += (1..<deviceCount).map { [$0, deviceCount - $0] }
        }
        if deviceCount > 2 {
            for first in 1..<deviceCount {
                for second in 1..<(deviceCount - first) {
                    layouts.append([first, second, deviceCount - first - second])
                }
            }
        }
        return layouts
    }

    private func defaultTileFrame(for device: Device, index: Int) -> ScreenTileFrame {
        let width: CGFloat = 220
        let ratio = resolvedScreenAspectRatio(for: device)
        let videoWidth = max(1, width - ScreenTile.horizontalChrome)
        let height = ScreenTile.chromeHeight + videoWidth / max(ratio, 0.25)
        let column = index % 3
        let row = index / 3
        let rowSpacing: CGFloat = 16
            + ScreenWindowMetrics.headerHeight
            + ScreenWindowMetrics.embeddedBottomControlsHeight
        return ScreenTileFrame(
            origin: CGPoint(
                x: 16 + CGFloat(column) * (width + 16),
                y: 16
                    + ScreenWindowMetrics.headerHeight
                    + CGFloat(row) * (height + rowSpacing)
            ),
            size: CGSize(width: width, height: height)
        )
    }

    private func moveTile(_ id: UUID, by translation: CGSize, in containerSize: CGSize) {
        guard var frame = tileFrames[id] else { return }
        if dragStartOrigins[id] == nil { dragStartOrigins[id] = frame.origin }
        let start = dragStartOrigins[id] ?? frame.origin
        frame.origin = CGPoint(
            x: min(max(0, start.x + translation.width), max(0, containerSize.width - frame.size.width)),
            y: min(max(0, start.y + translation.height), max(0, containerSize.height - frame.size.height))
        )
        tileFrames[id] = frame
    }

    private func resizeTile(
        _ id: UUID,
        edges: ScreenTileResizeEdges,
        by translation: CGSize,
        in containerSize: CGSize
    ) {
        guard var frame = tileFrames[id] else { return }
        if resizeStartFrames[id] == nil { resizeStartFrames[id] = frame }
        let start = resizeStartFrames[id] ?? frame
        let minimumWidth: CGFloat = 180
        let minimumHeight: CGFloat = 180

        if edges.contains(.leading) {
            let right = start.origin.x + start.size.width
            frame.origin.x = min(
                max(0, start.origin.x + translation.width),
                right - minimumWidth
            )
            frame.size.width = right - frame.origin.x
        } else if edges.contains(.trailing) {
            let right = min(
                max(start.origin.x + minimumWidth, start.origin.x + start.size.width + translation.width),
                containerSize.width
            )
            frame.size.width = right - start.origin.x
        }

        if edges.contains(.top) {
            let bottom = start.origin.y + start.size.height
            frame.origin.y = min(
                max(0, start.origin.y + translation.height),
                bottom - minimumHeight
            )
            frame.size.height = bottom - frame.origin.y
        } else if edges.contains(.bottom) {
            let bottom = min(
                max(start.origin.y + minimumHeight, start.origin.y + start.size.height + translation.height),
                containerSize.height
            )
            frame.size.height = bottom - start.origin.y
        }
        tileFrames[id] = frame
    }

    private func autoFitTileToDevice(_ id: UUID, in containerSize: CGSize) {
        guard var frame = tileFrames[id],
              let device = connectedDevices.first(where: { $0.id == id }),
              containerSize.width > 0,
              containerSize.height > 0 else {
            return
        }

        let deviceAspectRatio = resolvedScreenAspectRatio(for: device)
        let currentVideoSize = CGSize(
            width: max(1, frame.size.width - ScreenTile.horizontalChrome),
            height: max(1, frame.size.height - ScreenTile.chromeHeight)
        )
        let currentAspectRatio = currentVideoSize.width
            / max(currentVideoSize.height, 1)
        let targetVideoSize: CGSize

        if currentAspectRatio > deviceAspectRatio {
            targetVideoSize = CGSize(
                width: currentVideoSize.height * deviceAspectRatio,
                height: currentVideoSize.height
            )
        } else if currentAspectRatio < deviceAspectRatio {
            targetVideoSize = CGSize(
                width: currentVideoSize.width,
                height: currentVideoSize.width / deviceAspectRatio
            )
        } else {
            return
        }

        let desiredSize = CGSize(
            width: targetVideoSize.width + ScreenTile.horizontalChrome,
            height: targetVideoSize.height + ScreenTile.chromeHeight
        )
        let fitScale = min(
            1,
            containerSize.width / max(desiredSize.width, 1),
            containerSize.height / max(desiredSize.height, 1)
        )
        frame.size = CGSize(
            width: max(180, desiredSize.width * fitScale),
            height: max(180, desiredSize.height * fitScale)
        )
        frame.origin.x = min(
            max(0, frame.origin.x),
            max(0, containerSize.width - frame.size.width)
        )
        frame.origin.y = min(
            max(0, frame.origin.y),
            max(0, containerSize.height - frame.size.height)
        )
        tileFrames[id] = frame
    }

    private func syncLastDockedTileSizes(in containerSize: CGSize) {
        guard containerSize.width > 0, containerSize.height > 0 else { return }
        for (index, device) in connectedDevices.enumerated()
        where !coordinator.isDetached(device.id) {
            guard let videoSize = coordinator.lastDockedVideoSize(for: device.id) else {
                continue
            }
            var frame = tileFrames[device.id]
                ?? defaultTileFrame(for: device, index: index)
            let desiredSize = CGSize(
                width: max(180, videoSize.width + ScreenTile.horizontalChrome),
                height: max(180, videoSize.height + ScreenTile.chromeHeight)
            )
            let fitScale = min(
                1,
                containerSize.width / desiredSize.width,
                containerSize.height / desiredSize.height
            )
            frame.size.width = max(
                min(180, containerSize.width),
                desiredSize.width * fitScale
            )
            frame.size.height = max(
                min(180, containerSize.height),
                desiredSize.height * fitScale
            )
            frame.origin.x = min(
                max(0, frame.origin.x),
                max(0, containerSize.width - frame.size.width)
            )
            frame.origin.y = min(
                max(0, frame.origin.y),
                max(0, containerSize.height - frame.size.height)
            )
            tileFrames[device.id] = frame
        }
    }
}

private struct ScreenTileFrame {
    var origin: CGPoint
    var size: CGSize
}

private func displayAspectRatio(from displayInfo: String) -> CGFloat? {
    guard let size = displayPixelSize(from: displayInfo), size.height > 0 else {
        return nil
    }
    return min(max(size.width / size.height, 0.38), 1.8)
}

func displayPixelSize(from displayInfo: String) -> CGSize? {
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
    return CGSize(width: width, height: height)
}

func screenAspectRatio(device: Device, session: ScreenSessionSnapshot) -> CGFloat {
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
