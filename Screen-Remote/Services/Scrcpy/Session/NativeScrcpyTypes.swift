import Foundation

enum CodecFallbackPolicy {
    case automatic
    case strict
}

enum NativeScrcpyError: LocalizedError {
    case serverUnavailable(String)
    case commandFailed(String)
    case invalidForwardPort(String)
    case socketFailed(String)
    case invalidProtocol(String)
    case unsupportedCodec(String)
    case decoderFailed(String)
    case audioFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverUnavailable(let detail): "scrcpy-server is unavailable: \(detail)"
        case .commandFailed(let detail): "scrcpy command failed: \(detail)"
        case .invalidForwardPort(let detail): "ADB returned an invalid forward port: \(detail)"
        case .socketFailed(let detail): "scrcpy socket failed: \(detail)"
        case .invalidProtocol(let detail): "Invalid scrcpy protocol data: \(detail)"
        case .unsupportedCodec(let codec): "Unsupported native video codec: \(codec)"
        case .decoderFailed(let detail): "VideoToolbox decoder failed: \(detail)"
        case .audioFailed(let detail): "Core Audio playback failed: \(detail)"
        }
    }
}

enum ScrcpyTouchAction: UInt8 {
    case down = 0
    case up = 1
    case move = 2
    case hoverMove = 7
}

enum ScrcpyKeyAction: UInt8 {
    case down = 0
    case up = 1
}

enum ScrcpyMouseButton: UInt32 {
    case primary = 1
    case secondary = 2
    case tertiary = 4
    case back = 8
    case forward = 16
}
