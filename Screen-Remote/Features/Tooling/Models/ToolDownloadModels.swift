import Foundation
import SwiftUI

enum ToolDownloadKind: String, Identifiable {
    case adb
    case scrcpy
    case androidCLI
    case emulator
    case skins

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .adb: "ADB"
        case .scrcpy: "scrcpy"
        case .androidCLI: "Android CLI"
        case .emulator: "Android Emulator"
        case .skins: String.localizedKey("toolDownloadSkinsName")
        }
    }

    var installLocation: String {
        switch self {
        case .adb: "SDK/platform-tools/"
        case .scrcpy: "SDK/scrcpy/"
        case .androidCLI: "SDK/cmdline-tools/latest/"
        case .emulator: "SDK/emulator/"
        case .skins: "SDK/skins/"
        }
    }
}

enum ProxyKind {
    case http
    case socks

    var sdkManagerValue: String {
        switch self {
        case .http: "http"
        case .socks: "socks"
        }
    }
}

struct DownloadProxy {
    let kind: ProxyKind
    let host: String
    let port: Int
}

enum ParallelDownloadError: LocalizedError {
    case rangeUnsupported
    case invalidPart

    var errorDescription: String? {
        switch self {
        case .rangeUnsupported: String.localizedKey("toolDownloadParallelDownloadRangeUnsupported")
        case .invalidPart: String.localizedKey("toolDownloadParallelDownloadInvalidPart")
        }
    }
}

struct GitHubRelease: Decodable {
    let assets: [GitHubAsset]
}

struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

enum InstallerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(message) = self { return message }
        return nil
    }
}
