import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

enum ScrcpyServerAsset {
    static func resolve(log: @escaping (String) -> Void) throws -> URL {
        guard let bundled = Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar") else {
            throw NativeScrcpyError.serverUnavailable(
                "the macOS application bundle does not contain scrcpy-server.jar; run scripts/prepare-scrcpy-server.sh and rebuild"
            )
        }
        guard verified(bundled) else {
            throw NativeScrcpyError.serverUnavailable("the bundled scrcpy-server.jar failed SHA-256 verification")
        }
        log("Using verified bundled scrcpy-server v\(ScrcpyServerMetadata.version)")
        return bundled
    }

    static func ensureDeployed(
        adbPath: String,
        serial: String,
        log: ((String) -> Void)? = nil
    ) throws -> URL {
        let serverURL = try resolve(log: { _ in })
        guard !serial.isEmpty else {
            throw NativeScrcpyError.serverUnavailable("missing serial for scrcpy-server deployment")
        }

        // scrcpy may delete its remote JAR when cleanup is enabled, so a process-local
        // deployment cache cannot be the source of truth for replacement sessions.
        let adbExecutable = adbPath.isEmpty ? "/usr/bin/env" : adbPath
        let commandPrefix = adbExecutable == "/usr/bin/env" ? ["adb"] : []
        let checkResult = try NativeProcess.run(
            adbExecutable,
            commandPrefix + ["-s", serial, "shell", "sha256sum \(ScrcpyServerMetadata.remotePath)"]
        )
        if checkResult.status == 0 {
            let remoteHash = checkResult.output
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .split { $0.isWhitespace }
                .first.map(String.init)
            if remoteHash?.lowercased() == ScrcpyServerMetadata.sha256.lowercased() {
                log?(
                    "Using existing scrcpy-server deployment: serial=\(serial), " +
                        "version=\(ScrcpyServerMetadata.version)"
                )
                return serverURL
            }
        }

        log?("Deploying bundled scrcpy-server v\(ScrcpyServerMetadata.version) to serial=\(serial)")
        let pushResult = try NativeProcess.run(
            adbExecutable,
            commandPrefix + ["-s", serial, "push", serverURL.path, ScrcpyServerMetadata.remotePath]
        )
        guard pushResult.status == 0 else {
            throw NativeScrcpyError.serverUnavailable(pushResult.failureDetail)
        }
        log?("scrcpy-server deployment completed: serial=\(serial)")
        return serverURL
    }

    private static func verified(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return sha256(data) == ScrcpyServerMetadata.sha256
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
