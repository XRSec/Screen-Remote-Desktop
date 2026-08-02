import AppKit
import Combine
import SwiftUI

struct ScrcpyDeviceOptions: Codable, Equatable {
    var maxSize: Int = 0
    var videoBitrate: String = "4M"
    var maxFPS: Int = 60
    var videoEncoder = ""
    var videoDecoder = ""
    var enableAudio = false
    var audioBitrate = "128K"
    var audioEncoder = ""
    var audioDecoder = ""
    var audioVolume = 1.0
    var clipboardSync = true
    var turnScreenOff = false
    var powerOffOnClose = false
    var cleanupOnDisconnect = true
    var keepControllerAwake = false
    var keepDeviceAwake = true
    var ignoreVideoEncoderConstraints = false
    var compatibilityMode = false
    var gameMode = false
    var showFloatingBall = true
    var enableHardwareDecoding = true
    var newDisplayEnabled = false
    var virtualDisplaySystemDecorations = true
    var preserveVirtualDisplayContent = false
    var startApp = ""
    var newDisplayWidth = 0
    var newDisplayHeight = 0
    var newDisplayDPI = 0

    init(
        maxSize: Int = 0, videoBitrate: String = "4M", maxFPS: Int = 60,
        videoEncoder: String = "", videoDecoder: String = "",
        enableAudio: Bool = false, audioBitrate: String = "128K",
        audioEncoder: String = "", audioDecoder: String = "", audioVolume: Double = 1.0,
        clipboardSync: Bool = true, turnScreenOff: Bool = false, powerOffOnClose: Bool = false,
        cleanupOnDisconnect: Bool = true, keepControllerAwake: Bool = false,
        keepDeviceAwake: Bool = true, ignoreVideoEncoderConstraints: Bool = false,
        compatibilityMode: Bool = false, gameMode: Bool = false,
        showFloatingBall: Bool = true, enableHardwareDecoding: Bool = true,
        newDisplayEnabled: Bool = false, virtualDisplaySystemDecorations: Bool = true,
        preserveVirtualDisplayContent: Bool = false, startApp: String = "",
        newDisplayWidth: Int = 0, newDisplayHeight: Int = 0, newDisplayDPI: Int = 0
    ) {
        self.maxSize = maxSize
        self.videoBitrate = videoBitrate
        self.maxFPS = maxFPS
        self.videoEncoder = videoEncoder
        self.videoDecoder = videoDecoder
        self.enableAudio = enableAudio
        self.audioBitrate = audioBitrate
        self.audioEncoder = audioEncoder
        self.audioDecoder = audioDecoder
        self.audioVolume = audioVolume
        self.clipboardSync = clipboardSync
        self.turnScreenOff = turnScreenOff
        self.powerOffOnClose = powerOffOnClose
        self.cleanupOnDisconnect = cleanupOnDisconnect
        self.keepControllerAwake = keepControllerAwake
        self.keepDeviceAwake = keepDeviceAwake
        self.ignoreVideoEncoderConstraints = ignoreVideoEncoderConstraints
        self.compatibilityMode = compatibilityMode
        self.gameMode = gameMode
        self.showFloatingBall = showFloatingBall
        self.enableHardwareDecoding = enableHardwareDecoding
        self.newDisplayEnabled = newDisplayEnabled
        self.virtualDisplaySystemDecorations = virtualDisplaySystemDecorations
        self.preserveVirtualDisplayContent = preserveVirtualDisplayContent
        self.startApp = startApp
        self.newDisplayWidth = newDisplayWidth
        self.newDisplayHeight = newDisplayHeight
        self.newDisplayDPI = newDisplayDPI
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxSize: try values.decodeIfPresent(Int.self, forKey: .maxSize) ?? 0,
            videoBitrate: try values.decodeIfPresent(String.self, forKey: .videoBitrate) ?? "4M",
            maxFPS: try values.decodeIfPresent(Int.self, forKey: .maxFPS) ?? 60,
            videoEncoder: try values.decodeIfPresent(String.self, forKey: .videoEncoder) ?? "",
            videoDecoder: try values.decodeIfPresent(String.self, forKey: .videoDecoder) ?? "",
            enableAudio: try values.decodeIfPresent(Bool.self, forKey: .enableAudio) ?? false,
            audioBitrate: try values.decodeIfPresent(String.self, forKey: .audioBitrate) ?? "128K",
            audioEncoder: try values.decodeIfPresent(String.self, forKey: .audioEncoder) ?? "",
            audioDecoder: try values.decodeIfPresent(String.self, forKey: .audioDecoder) ?? "",
            audioVolume: min(
                max(try values.decodeIfPresent(Double.self, forKey: .audioVolume) ?? 1, 1),
                3
            ),
            clipboardSync: try values.decodeIfPresent(Bool.self, forKey: .clipboardSync) ?? true,
            turnScreenOff: try values.decodeIfPresent(Bool.self, forKey: .turnScreenOff) ?? false,
            powerOffOnClose: try values.decodeIfPresent(Bool.self, forKey: .powerOffOnClose) ?? false,
            cleanupOnDisconnect: try values.decodeIfPresent(Bool.self, forKey: .cleanupOnDisconnect) ?? true,
            keepControllerAwake: try values.decodeIfPresent(Bool.self, forKey: .keepControllerAwake) ?? false,
            keepDeviceAwake: try values.decodeIfPresent(Bool.self, forKey: .keepDeviceAwake) ?? true,
            ignoreVideoEncoderConstraints: try values.decodeIfPresent(Bool.self, forKey: .ignoreVideoEncoderConstraints) ?? false,
            compatibilityMode: try values.decodeIfPresent(Bool.self, forKey: .compatibilityMode) ?? false,
            gameMode: try values.decodeIfPresent(Bool.self, forKey: .gameMode) ?? false,
            showFloatingBall: try values.decodeIfPresent(Bool.self, forKey: .showFloatingBall) ?? true,
            enableHardwareDecoding: try values.decodeIfPresent(Bool.self, forKey: .enableHardwareDecoding) ?? true,
            newDisplayEnabled: try values.decodeIfPresent(Bool.self, forKey: .newDisplayEnabled) ?? false,
            virtualDisplaySystemDecorations: try values.decodeIfPresent(Bool.self, forKey: .virtualDisplaySystemDecorations) ?? true,
            preserveVirtualDisplayContent: try values.decodeIfPresent(Bool.self, forKey: .preserveVirtualDisplayContent) ?? false,
            startApp: try values.decodeIfPresent(String.self, forKey: .startApp) ?? "",
            newDisplayWidth: try values.decodeIfPresent(Int.self, forKey: .newDisplayWidth) ?? 0,
            newDisplayHeight: try values.decodeIfPresent(Int.self, forKey: .newDisplayHeight) ?? 0,
            newDisplayDPI: try values.decodeIfPresent(Int.self, forKey: .newDisplayDPI) ?? 0
        )
    }
}
