import Foundation

@main
struct SessionParameterCheck {
    private enum Category {
        case applied
        case requiresRestart
        case unsupported
    }

    private struct Case {
        let parameter: SessionParameter
        let category: Category
        let mutate: (inout ScrcpyDeviceOptions) -> Void
    }

    static func main() {
        let cases: [Case] = [
            Case(parameter: .audioVolume, category: .applied) { $0.audioVolume = 2 },
            Case(parameter: .videoEncoder, category: .requiresRestart) { $0.videoEncoder = "encoder" },
            Case(parameter: .videoDecoder, category: .requiresRestart) { $0.videoDecoder = "videotoolbox.h264" },
            Case(parameter: .videoBitrate, category: .requiresRestart) { $0.videoBitrate = "8M" },
            Case(parameter: .maxSize, category: .requiresRestart) { $0.maxSize = 1080 },
            Case(parameter: .maxFPS, category: .requiresRestart) { $0.maxFPS = 90 },
            Case(parameter: .audioEncoder, category: .requiresRestart) { $0.audioEncoder = "encoder" },
            Case(parameter: .audioDecoder, category: .requiresRestart) { $0.audioDecoder = "decoder" },
            Case(parameter: .audioBitrate, category: .requiresRestart) { $0.audioBitrate = "192K" },
            Case(parameter: .enableAudio, category: .requiresRestart) { $0.enableAudio.toggle() },
            Case(parameter: .newDisplayEnabled, category: .requiresRestart) { $0.newDisplayEnabled.toggle() },
            Case(parameter: .newDisplayWidth, category: .requiresRestart) { $0.newDisplayWidth = 1920 },
            Case(parameter: .newDisplayHeight, category: .requiresRestart) { $0.newDisplayHeight = 1080 },
            Case(parameter: .newDisplayDPI, category: .requiresRestart) { $0.newDisplayDPI = 320 },
            Case(parameter: .virtualDisplaySystemDecorations, category: .requiresRestart) { $0.virtualDisplaySystemDecorations.toggle() },
            Case(parameter: .preserveVirtualDisplayContent, category: .requiresRestart) { $0.preserveVirtualDisplayContent.toggle() },
            Case(parameter: .clipboardSync, category: .requiresRestart) { $0.clipboardSync.toggle() },
            Case(parameter: .turnScreenOff, category: .requiresRestart) { $0.turnScreenOff.toggle() },
            Case(parameter: .powerOffOnClose, category: .requiresRestart) { $0.powerOffOnClose.toggle() },
            Case(parameter: .cleanupOnDisconnect, category: .requiresRestart) { $0.cleanupOnDisconnect.toggle() },
            Case(parameter: .keepControllerAwake, category: .unsupported) { $0.keepControllerAwake.toggle() },
            Case(parameter: .keepDeviceAwake, category: .requiresRestart) { $0.keepDeviceAwake.toggle() },
            Case(parameter: .ignoreVideoEncoderConstraints, category: .requiresRestart) { $0.ignoreVideoEncoderConstraints.toggle() },
            Case(parameter: .compatibilityMode, category: .applied) { $0.compatibilityMode.toggle() },
            Case(parameter: .gameMode, category: .applied) { $0.gameMode.toggle() },
            Case(parameter: .shellPassword, category: .requiresRestart) { $0.shellPassword = "password" },
            Case(parameter: .enableHardwareDecoding, category: .requiresRestart) { $0.enableHardwareDecoding.toggle() },
            Case(parameter: .startApp, category: .requiresRestart) { $0.startApp = "com.example.app" }
        ]

        let optionPropertyCount = Mirror(reflecting: ScrcpyDeviceOptions()).children.count
        require(cases.count == optionPropertyCount, "every option property must have a classification check")

        for item in cases {
            let previous = ScrcpyDeviceOptions()
            var next = previous
            item.mutate(&next)
            let plan = SessionParameterController.evaluate(previous: previous, next: next)
            let expected: [SessionParameter]
            switch item.category {
            case .applied:
                expected = plan.applied
                require(plan.requiresRestart.isEmpty && plan.unsupported.isEmpty, "\(item.parameter.rawValue) has extra classifications")
            case .requiresRestart:
                expected = plan.requiresRestart
                require(plan.applied.isEmpty && plan.unsupported.isEmpty, "\(item.parameter.rawValue) has extra classifications")
            case .unsupported:
                expected = plan.unsupported
                require(plan.applied.isEmpty && plan.requiresRestart.isEmpty, "\(item.parameter.rawValue) has extra classifications")
            }
            require(expected == [item.parameter], "\(item.parameter.rawValue) is not classified as expected")
        }

        require(
            SessionParameterController.evaluate(previous: ScrcpyDeviceOptions(), next: ScrcpyDeviceOptions()).isEmpty,
            "unchanged options must produce an empty plan"
        )
        print("Session parameter checks passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("Session parameter check failed: \(message)\n".utf8))
            exit(1)
        }
    }
}
