import Foundation

enum SDLLogTag: String, CaseIterable, Codable, Identifiable {
    case connection
    case adb
    case scrcpyServer = "scrcpy_server"
    case video
    case audio
    case control
    case socks
    case render
    case apps
    case files
    case device
    case other

    var id: String { rawValue }
}

struct SDLLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: String
    let tag: SDLLogTag
    let message: String

    init(id: UUID = UUID(), timestamp: String, tag: SDLLogTag, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.tag = tag
        self.message = message
    }

    var line: String {
        "\(timestamp)  [\(tag.rawValue)]  \(message)"
    }
}
