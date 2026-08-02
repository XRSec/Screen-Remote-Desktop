import SwiftUI
import Foundation
import CFNetwork

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
