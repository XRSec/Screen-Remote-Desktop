import Foundation

enum SessionParameter: String, CaseIterable {
    case audioVolume
    case videoEncoder
    case videoDecoder
    case videoBitrate
    case maxSize
    case maxFPS
    case audioEncoder
    case audioDecoder
    case audioBitrate
    case enableAudio
    case newDisplayEnabled
    case newDisplayWidth
    case newDisplayHeight
    case newDisplayDPI
    case virtualDisplaySystemDecorations
    case preserveVirtualDisplayContent
    case clipboardSync
    case turnScreenOff
    case powerOffOnClose
    case cleanupOnDisconnect
    case keepControllerAwake
    case keepDeviceAwake
    case ignoreVideoEncoderConstraints
    case compatibilityMode
    case gameMode
    case shellPassword
    case enableHardwareDecoding
    case startApp

    // Not yet modelled in ScrcpyDeviceOptions:
    // orientation / crop / mouseSensitivity / keyboardMode / touchMode
    // remain explicit placeholders for future feature work.
    case orientation
    case crop
    case mouseSensitivity
    case keyboardMode
    case touchMode
}

enum SessionParameterUpdateResult {
    case applied([SessionParameter])
    case requiresRestart([SessionParameter])
    case unsupported([SessionParameter])
}

struct SessionParameterUpdatePlan {
    let applied: [SessionParameter]
    let requiresRestart: [SessionParameter]
    let unsupported: [SessionParameter]

    static var empty: Self {
        SessionParameterUpdatePlan(applied: [], requiresRestart: [], unsupported: [])
    }

    var isEmpty: Bool {
        applied.isEmpty && requiresRestart.isEmpty && unsupported.isEmpty
    }
}

enum SessionParameterController {
    static func evaluate(previous: ScrcpyDeviceOptions, next: ScrcpyDeviceOptions) -> SessionParameterUpdatePlan {
        guard previous != next else { return .empty }
        return SessionParameterUpdatePlan(
            applied: appliedParameters(previous: previous, next: next),
            requiresRestart: restartParameters(previous: previous, next: next),
            unsupported: unsupportedParameters(previous: previous, next: next)
        )
    }

    private static func appliedParameters(
        previous: ScrcpyDeviceOptions,
        next: ScrcpyDeviceOptions
    ) -> [SessionParameter] {
        var result: [SessionParameter] = []
        if previous.audioVolume != next.audioVolume { result.append(.audioVolume) }
        if previous.compatibilityMode != next.compatibilityMode { result.append(.compatibilityMode) }
        if previous.gameMode != next.gameMode { result.append(.gameMode) }
        return result
    }

    private static func restartParameters(
        previous: ScrcpyDeviceOptions,
        next: ScrcpyDeviceOptions
    ) -> [SessionParameter] {
        var result: [SessionParameter] = []
        let comparisons: [(Bool, SessionParameter)] = [
            (previous.videoEncoder != next.videoEncoder, .videoEncoder),
            (previous.videoDecoder != next.videoDecoder, .videoDecoder),
            (previous.videoBitrate != next.videoBitrate, .videoBitrate),
            (previous.maxSize != next.maxSize, .maxSize),
            (previous.maxFPS != next.maxFPS, .maxFPS),
            (previous.audioEncoder != next.audioEncoder, .audioEncoder),
            (previous.audioDecoder != next.audioDecoder, .audioDecoder),
            (previous.audioBitrate != next.audioBitrate, .audioBitrate),
            (previous.enableAudio != next.enableAudio, .enableAudio),
            (previous.shellPassword != next.shellPassword, .shellPassword),
            (previous.newDisplayEnabled != next.newDisplayEnabled, .newDisplayEnabled),
            (previous.newDisplayWidth != next.newDisplayWidth, .newDisplayWidth),
            (previous.newDisplayHeight != next.newDisplayHeight, .newDisplayHeight),
            (previous.newDisplayDPI != next.newDisplayDPI, .newDisplayDPI),
            (previous.virtualDisplaySystemDecorations != next.virtualDisplaySystemDecorations, .virtualDisplaySystemDecorations),
            (previous.preserveVirtualDisplayContent != next.preserveVirtualDisplayContent, .preserveVirtualDisplayContent),
            (previous.clipboardSync != next.clipboardSync, .clipboardSync),
            (previous.turnScreenOff != next.turnScreenOff, .turnScreenOff),
            (previous.powerOffOnClose != next.powerOffOnClose, .powerOffOnClose),
            (previous.cleanupOnDisconnect != next.cleanupOnDisconnect, .cleanupOnDisconnect),
            (previous.keepDeviceAwake != next.keepDeviceAwake, .keepDeviceAwake),
            (previous.ignoreVideoEncoderConstraints != next.ignoreVideoEncoderConstraints, .ignoreVideoEncoderConstraints),
            (previous.enableHardwareDecoding != next.enableHardwareDecoding, .enableHardwareDecoding),
            (previous.startApp != next.startApp, .startApp)
        ]
        for (changed, parameter) in comparisons where changed { result.append(parameter) }
        return result
    }

    private static func unsupportedParameters(
        previous: ScrcpyDeviceOptions,
        next: ScrcpyDeviceOptions
    ) -> [SessionParameter] {
        previous.keepControllerAwake != next.keepControllerAwake ? [.keepControllerAwake] : []
    }
}
