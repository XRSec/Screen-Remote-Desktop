import AppKit
import Foundation

@MainActor
extension ScreenSessionManager {
    func layoutInspectorState(for deviceID: UUID) -> ScreenLayoutInspectorState {
        layoutInspectorStates[deviceID] ?? ScreenLayoutInspectorState()
    }

    func resolutionAdjustmentState(for deviceID: UUID) -> ScreenResolutionAdjustmentState {
        resolutionAdjustmentStates[deviceID] ?? ScreenResolutionAdjustmentState(
            currentDisplay: session(for: deviceID).preflight?.displayInfo
        )
    }

    func isResolutionAdaptedToViewport(
        deviceID: UUID,
        viewportSize: CGSize,
        backingScale: CGFloat
    ) -> Bool {
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              let original = session(for: deviceID).preflight?.displayInfo,
              let current = resolutionAdjustmentState(for: deviceID).currentDisplay else {
            return false
        }
        return sameDisplay(
            current,
            adaptedDisplay(
                viewportSize: viewportSize,
                backingScale: backingScale,
                original: original
            )
        )
    }

    func beginLayoutInspection(
        deviceID: UUID,
        adbPath: String,
        log: @escaping (String) -> Void
    ) {
        guard layoutInspectorRefreshTasks[deviceID] == nil else { return }
        var state = layoutInspectorState(for: deviceID)
        state.isEnabled = true
        state.isVisible = true
        layoutInspectorStates[deviceID] = state
        layoutInspectorRefreshTasks[deviceID] = Task { [weak self] in
            guard let self else { return }
            await self.refreshLayoutInspection(
                deviceID: deviceID,
                adbPath: adbPath,
                showOnSuccess: true,
                log: log
            )
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard self.layoutInspectorState(for: deviceID).isVisible else { break }
                Task { [weak self] in
                    await self?.refreshLayoutInspection(
                        deviceID: deviceID,
                        adbPath: adbPath,
                        showOnSuccess: false,
                        log: log
                    )
                }
            }
            self.layoutInspectorRefreshTasks[deviceID] = nil
        }
    }

    func requestLayoutInspectionRefresh(
        deviceID: UUID,
        adbPath: String,
        log: @escaping (String) -> Void
    ) {
        var state = layoutInspectorState(for: deviceID)
        state.isEnabled = true
        layoutInspectorStates[deviceID] = state
        Task { [weak self] in
            await self?.refreshLayoutInspection(
                deviceID: deviceID,
                adbPath: adbPath,
                showOnSuccess: true,
                log: log
            )
        }
    }

    func stopLayoutInspection(deviceID: UUID) {
        layoutInspectorRefreshTasks.removeValue(forKey: deviceID)?.cancel()
        var state = layoutInspectorState(for: deviceID)
        state.isEnabled = false
        state.isVisible = false
        state.isLoading = false
        state.isTargetKeyboardVisible = false
        state.feedback = ""
        layoutInspectorStates[deviceID] = state
    }

    func clearToolFeedback(deviceID: UUID, matching feedback: String) {
        var inspector = layoutInspectorState(for: deviceID)
        if inspector.feedback == feedback {
            inspector.feedback = ""
            layoutInspectorStates[deviceID] = inspector
        }
        var resolution = resolutionAdjustmentState(for: deviceID)
        if resolution.feedback == feedback {
            resolution.feedback = ""
            resolutionAdjustmentStates[deviceID] = resolution
        }
    }

    func toggleResolutionAdjustment(
        deviceID: UUID,
        viewportSize: CGSize,
        backingScale: CGFloat,
        adbPath: String,
        log: @escaping (String) -> Void,
        onSuccess: @escaping (_ restored: Bool, _ original: ScreenTargetDisplayInfo) -> Void
    ) {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            var state = resolutionAdjustmentState(for: deviceID)
            state.feedback = String.localizedKey("screensResolutionViewportUnavailable")
            state.feedbackIsError = true
            resolutionAdjustmentStates[deviceID] = state
            return
        }
        Task { [weak self] in
            await self?.performResolutionAdjustment(
                deviceID: deviceID,
                viewportSize: viewportSize,
                backingScale: backingScale,
                adbPath: adbPath,
                log: log,
                onSuccess: onSuccess
            )
        }
    }

    private func refreshLayoutInspection(
        deviceID: UUID,
        adbPath: String,
        showOnSuccess: Bool,
        log: @escaping (String) -> Void
    ) async {
        var state = layoutInspectorState(for: deviceID)
        guard !state.isLoading else { return }
        guard state.isEnabled else { return }
        guard let target = connectedTarget(deviceID: deviceID, adbPath: adbPath) else {
            state.feedback = String.localizedKey("screensToolSessionRequired")
            state.feedbackIsError = true
            layoutInspectorStates[deviceID] = state
            return
        }
        state.isLoading = true
        state.feedback = ""
        layoutInspectorStates[deviceID] = state

        let cachedDisplay = resolutionAdjustmentState(for: deviceID).currentDisplay
            ?? session(for: deviceID).preflight?.displayInfo
        let result = await SessionProcessRunner.run(
            executable: target.adbPath,
            arguments: ["-s", target.serial, "shell", ScreenSessionToolCommand.layoutDump],
            timeout: 12
        )
        var updated = layoutInspectorState(for: deviceID)
        guard updated.isEnabled else { return }
        defer {
            updated.isLoading = false
            layoutInspectorStates[deviceID] = updated
        }
        guard result.succeeded,
              let xml = extractLayoutXML(from: result.output) else {
            if updated.snapshot == nil {
                updated.isEnabled = false
                updated.isVisible = false
            }
            updated.feedback = String.localizedKey("screensLayoutAnalysisFailed")
            updated.feedbackIsError = true
            log("UI layout capture failed: \(result.failureDetail)")
            return
        }

        do {
            var snapshot = try RemoteUiLayoutParser.parseSnapshot(xml)
            let display: ScreenTargetDisplayInfo?
            if let cachedDisplay {
                display = cachedDisplay
            } else {
                display = await readTargetDisplay(target)
            }
            if let display {
                snapshot.viewportBounds = RemoteUiLayoutBounds(
                    left: 0,
                    top: 0,
                    right: display.width,
                    bottom: display.height
                )
            }
            guard layoutInspectorState(for: deviceID).isEnabled,
                  session(for: deviceID).adbSerial == target.serial else {
                updated = layoutInspectorState(for: deviceID)
                return
            }
            guard !snapshot.nodes.isEmpty else {
                updated.snapshot = snapshot
                updated.isEnabled = false
                updated.isVisible = false
                updated.feedback = String.localizedKey("screensLayoutAnalysisEmpty")
                updated.feedbackIsError = false
                layoutInspectorRefreshTasks.removeValue(forKey: deviceID)?.cancel()
                log("UI layout capture completed with no renderable nodes")
                return
            }
            updated.snapshot = snapshot
            updated.feedback = ""
            if showOnSuccess || updated.isVisible {
                updated.isVisible = true
            }
            Task { [weak self] in
                await self?.refreshTargetKeyboardVisibility(
                    deviceID: deviceID,
                    target: target
                )
            }
            log(
                "UI layout capture completed: nodes=\(snapshot.nodes.count), " +
                    "viewport=\(snapshot.viewportBounds.width)x\(snapshot.viewportBounds.height)"
            )
        } catch {
            if updated.snapshot == nil {
                updated.isEnabled = false
                updated.isVisible = false
            }
            updated.feedback = String.localizedKey("screensLayoutAnalysisFailed")
            updated.feedbackIsError = true
            log("UI layout parsing failed: \(error)")
        }
    }

    private func refreshTargetKeyboardVisibility(
        deviceID: UUID,
        target: (serial: String, adbPath: String)
    ) async {
        let isVisible = await isTargetKeyboardVisible(target)
        var state = layoutInspectorState(for: deviceID)
        guard state.isEnabled,
              session(for: deviceID).adbSerial == target.serial else { return }
        state.isTargetKeyboardVisible = isVisible
        layoutInspectorStates[deviceID] = state
    }

    private func performResolutionAdjustment(
        deviceID: UUID,
        viewportSize: CGSize,
        backingScale: CGFloat,
        adbPath: String,
        log: @escaping (String) -> Void,
        onSuccess: @escaping (_ restored: Bool, _ original: ScreenTargetDisplayInfo) -> Void
    ) async {
        var state = resolutionAdjustmentState(for: deviceID)
        guard !state.isBusy else { return }
        guard let connectedDisplay = session(for: deviceID).preflight?.displayInfo,
              let target = connectedTarget(deviceID: deviceID, adbPath: adbPath) else {
            state.feedback = String.localizedKey("screensResolutionOriginalUnavailable")
            state.feedbackIsError = true
            resolutionAdjustmentStates[deviceID] = state
            return
        }
        let original = connectedDisplay.deviceDefault
        state.isBusy = true
        state.feedback = ""
        resolutionAdjustmentStates[deviceID] = state

        let adapted = adaptedDisplay(
            viewportSize: viewportSize,
            backingScale: backingScale,
            original: original
        )
        let currentDisplay = await readTargetDisplay(target) ?? state.currentDisplay ?? original
        let shouldRestore = sameDisplay(currentDisplay, adapted)
        let command: String
        if shouldRestore {
            command = resolutionResetCommand
        } else {
            command = resolutionCommand(
                width: adapted.width,
                height: adapted.height,
                densityDPI: adapted.densityDPI
            )
        }

        let result = await SessionProcessRunner.run(
            executable: target.adbPath,
            arguments: ["-s", target.serial, "shell", command],
            timeout: 10
        )
        var updated = resolutionAdjustmentState(for: deviceID)
        updated.isBusy = false
        guard session(for: deviceID).adbSerial == target.serial else { return }
        guard result.succeeded else {
            updated.feedback = String.localizedKey("screensResolutionChangeFailed")
            updated.feedbackIsError = true
            resolutionAdjustmentStates[deviceID] = updated
            log("Target resolution change failed: \(result.failureDetail)")
            return
        }

        let refreshed = await readTargetDisplay(target)
        updated.currentDisplay = refreshed
        updated.isAdjusted = refreshed.map { !sameDisplay($0, original) } ?? !shouldRestore
        updated.feedback = String.localizedKey(
            shouldRestore ? "screensResolutionRestored" : "screensResolutionAdapted"
        )
        updated.feedbackIsError = false
        resolutionAdjustmentStates[deviceID] = updated
        onSuccess(shouldRestore, original)
        if let refreshed {
            log(
                "Target resolution \(shouldRestore ? "restored" : "adapted"): " +
                    "\(refreshed.width)x\(refreshed.height), density=\(refreshed.densityDPI ?? 0)"
            )
        }
    }

    private func connectedTarget(deviceID: UUID, adbPath: String) -> (serial: String, adbPath: String)? {
        let session = session(for: deviceID)
        guard !session.adbSerial.isEmpty else { return nil }
        return (session.adbSerial, executablePath(adbPath, fallback: .adb))
    }

    private func readTargetDisplay(
        _ target: (serial: String, adbPath: String)
    ) async -> ScreenTargetDisplayInfo? {
        let result = await SessionProcessRunner.run(
            executable: target.adbPath,
            arguments: ["-s", target.serial, "shell", ScreenSessionToolCommand.readDisplay],
            timeout: 6
        )
        return result.succeeded ? parseScreenTargetDisplayInfo(result.output) : nil
    }

    private func isTargetKeyboardVisible(
        _ target: (serial: String, adbPath: String)
    ) async -> Bool {
        let result = await SessionProcessRunner.run(
            executable: target.adbPath,
            arguments: ["-s", target.serial, "shell", "dumpsys input_method"],
            timeout: 6
        )
        guard result.succeeded else { return false }
        return [
            "mInputShown=true",
            "mWindowVisible=true",
            "mInputViewStarted=true",
            "mImeWindowVis=3"
        ].contains { result.output.contains($0) }
    }
}

private enum ScreenSessionToolCommand {
    static let layoutDumpPath = "/data/local/tmp/Screen-Remote-layout.xml"
    static let layoutBegin = "__SCRCPY_UI_LAYOUT_BEGIN__"
    static let layoutEnd = "__SCRCPY_UI_LAYOUT_END__"
    static let layoutDump =
        "uiautomator dump \(layoutDumpPath) >/dev/null 2>&1 && " +
        "(echo \(layoutBegin) && cat \(layoutDumpPath) && echo \(layoutEnd))"
    static let readDisplay = "wm size; wm density"
}

private func extractLayoutXML(from output: String) -> String? {
    if let start = output.range(of: ScreenSessionToolCommand.layoutBegin),
       let end = output.range(
        of: ScreenSessionToolCommand.layoutEnd,
        range: start.upperBound..<output.endIndex
       ) {
        let xml = output[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return xml.isEmpty ? nil : xml
    }
    guard let start = output.range(of: "<?xml")?.lowerBound
        ?? output.range(of: "<hierarchy")?.lowerBound else {
        return nil
    }
    let xml = output[start...].trimmingCharacters(in: .whitespacesAndNewlines)
    return xml.isEmpty ? nil : xml
}

private func adaptedDisplay(
    viewportSize: CGSize,
    backingScale: CGFloat,
    original: ScreenTargetDisplayInfo
) -> (width: Int, height: Int, densityDPI: Int?) {
    let scale = max(backingScale, 1)
    let width = alignedVideoDimension(viewportSize.width * scale)
    let height = alignedVideoDimension(viewportSize.height * scale)
    guard let originalDensity = original.densityDPI else {
        return (width, height, nil)
    }
    let widthScale = CGFloat(width) / CGFloat(max(original.width, 1))
    let heightScale = CGFloat(height) / CGFloat(max(original.height, 1))
    let density = max(72, Int((CGFloat(originalDensity) * min(widthScale, heightScale)).rounded()))
    return (width, height, density)
}

private func alignedVideoDimension(_ value: CGFloat) -> Int {
    let pixels = max(256, Int(value.rounded(.down)))
    return max(256, pixels - pixels % 8)
}

private func resolutionCommand(width: Int, height: Int, densityDPI: Int?) -> String {
    var command = "wm size \(width)x\(height)"
    if let densityDPI, densityDPI > 0 {
        command += " && wm density \(densityDPI)"
    }
    return command
}

private let resolutionResetCommand = "wm size reset && wm density reset"

private func sameDisplay(_ lhs: ScreenTargetDisplayInfo, _ rhs: ScreenTargetDisplayInfo) -> Bool {
    lhs.width == rhs.width && lhs.height == rhs.height && lhs.densityDPI == rhs.densityDPI
}

private func sameDisplay(
    _ lhs: ScreenTargetDisplayInfo,
    _ rhs: (width: Int, height: Int, densityDPI: Int?)
) -> Bool {
    lhs.width == rhs.width && lhs.height == rhs.height && lhs.densityDPI == rhs.densityDPI
}
