import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

enum ScrcpyServerAsset {
    static let remotePath = "/data/local/tmp/scrcpy-server.jar"

    static func resolve(log: @escaping (String) -> Void) throws -> URL {
        guard let bundled = Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar") else {
            throw NativeScrcpyError.serverUnavailable(
                "the macOS application bundle does not contain scrcpy-server.jar; run scripts/prepare-scrcpy-server.sh and rebuild"
            )
        }
        guard verified(bundled) else {
            throw NativeScrcpyError.serverUnavailable("the bundled scrcpy-server.jar failed SHA-256 verification")
        }
        log("Using verified bundled scrcpy-server v\(NativeScrcpySession.serverVersion)")
        return bundled
    }

    private static func verified(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return sha256(data) == NativeScrcpySession.serverSHA256
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
