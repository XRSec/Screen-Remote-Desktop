import Foundation

enum ScrcpyCodecCapabilityProbe {
    static func remoteEncoders(
        adbPath: String,
        serial: String,
        kind: ScrcpyMediaKind? = nil,
        log: ((String) -> Void)? = nil
    ) -> [ScrcpyRemoteEncoder] {
        let result = remoteEncodersWithMetadata(
            adbPath: adbPath,
            serial: serial,
            kind: kind,
            log: log
        )
        return result.encoders
    }

    static func remoteEncodersWithMetadata(
        adbPath: String,
        serial: String,
        kind: ScrcpyMediaKind? = nil,
        log: ((String) -> Void)? = nil
    ) -> (encoders: [ScrcpyRemoteEncoder], fallbackReason: String) {
        guard !serial.isEmpty else {
            let message = "missing-serial"
            log?(
                "Codec capability source: bundled scrcpy-server | " +
                    "serial=\(serial) | " +
                    "serverVersion=\(ScrcpyServerMetadata.version) | " +
                    "encoderCount=0 | " +
                    "fallbackReason=\(message)"
            )
            return ([], message)
        }

        let adbExecutable = adbPath.isEmpty ? "/usr/bin/env" : adbPath
        let commandPrefix = adbExecutable == "/usr/bin/env" ? ["adb"] : []
        let cached = ScrcpyCodecCapabilityCache.remoteEncoders(for: serial, kind: kind)
        if let cachedMetadata = ScrcpyCodecCapabilityCache.remoteEncoderMetadata(for: serial),
           !cached.isEmpty {
            let currentFingerprint = remoteBuildFingerprint(
                adbExecutable: adbExecutable,
                commandPrefix: commandPrefix,
                serial: serial
            )
            let currentSdk = remoteBuildSdk(
                adbExecutable: adbExecutable,
                commandPrefix: commandPrefix,
                serial: serial
            )
            let reason = ScrcpyCodecCapabilityCache.cacheInvalidationReason(
                metadata: cachedMetadata,
                currentFingerprint: currentFingerprint,
                currentSdk: currentSdk
            )
            if let reason {
                log?(
                    "Codec capability cache invalid | " +
                        "serial=\(serial) | " +
                        "serverVersion=\(cachedMetadata.serverVersion) | " +
                        "reason=\(reason)"
                )
                ScrcpyCodecCapabilityCache.clearRemoteEncoders(for: serial)
            } else {
                let fingerprintMatched = cacheFingerprintMatch(
                    cached: cachedMetadata.androidFingerprint,
                    current: currentFingerprint
                )
                let ageText = cacheAgeText(capturedAt: cachedMetadata.capturedAt)
                log?(
                    "Codec capability cache hit | " +
                        "serial=\(serial) | " +
                        "serverVersion=\(cachedMetadata.serverVersion) | " +
                        "fingerprintMatched=\(fingerprintMatched) | " +
                        "age=\(ageText)"
                )
                log?(
                    "Codec capability source: bundled scrcpy-server | " +
                        "serial=\(serial) | " +
                        "serverVersion=\(ScrcpyServerMetadata.version) | " +
                        "encoderCount=\(cached.count) | " +
                        "fallbackReason=cache-hit"
                )
                return (cached, "cache-hit")
            }
        } else if !cached.isEmpty {
            log?(
                "Codec capability cache invalid | " +
                    "serial=\(serial) | " +
                    "serverVersion=\(ScrcpyServerMetadata.version) | " +
                    "reason=missing metadata"
            )
            ScrcpyCodecCapabilityCache.clearRemoteEncoders(for: serial)
        }

        let discoveredMetadata = currentDiscoveryMetadata(
            adbExecutable: adbExecutable,
            commandPrefix: commandPrefix,
            serial: serial
        )

        do {
            _ = try ScrcpyServerAsset.ensureDeployed(
                adbPath: adbExecutable,
                serial: serial
            )

            let result = try NativeProcess.run(adbExecutable, commandPrefix + [
                "-s", serial, "shell",
                "CLASSPATH=\(ScrcpyServerMetadata.remotePath)",
                "app_process", "/", "com.genymobile.scrcpy.Server", ScrcpyServerMetadata.version,
                "log_level=info", "list_encoders=true", "cleanup=false"
            ])
            let text = "\(result.output)\n\(result.error)"
            let parsed = parseScrcpyRemoteEncoders(text)

            guard result.status == 0, !parsed.isEmpty else {
                let message: String
                if result.status != 0 {
                    message = "command-failed: \(result.failureDetail)"
                } else {
                    message = "no-encoders-reported"
                }
                log?(
                    "Codec capability source: bundled scrcpy-server | " +
                        "serial=\(serial) | " +
                        "serverVersion=\(ScrcpyServerMetadata.version) | " +
                        "encoderCount=0 | " +
                        "fallbackReason=\(message)"
                )
                return ([], message)
            }

            if let kind {
                let filtered = parsed.filter { $0.kind == kind }
                let message = filtered.isEmpty ? "no-matching-kind(\(kind.rawValue))" : "ok"
                ScrcpyCodecCapabilityCache.saveRemoteEncoders(
                    parsed,
                    for: serial,
                    metadata: discoveredMetadata
                )
                if !filtered.isEmpty {
                    log?(
                        "Codec capability source: bundled scrcpy-server | " +
                            "serial=\(serial) | " +
                            "serverVersion=\(ScrcpyServerMetadata.version) | " +
                            "encoderCount=\(filtered.count) | " +
                            "fallbackReason=\(message)"
                    )
                } else {
                    log?(
                        "Codec capability source: bundled scrcpy-server | " +
                            "serial=\(serial) | " +
                            "serverVersion=\(ScrcpyServerMetadata.version) | " +
                            "encoderCount=0 | " +
                            "fallbackReason=\(message)"
                    )
                }
                return (filtered, message)
            }

            ScrcpyCodecCapabilityCache.saveRemoteEncoders(
                parsed,
                for: serial,
                metadata: discoveredMetadata
            )
            log?(
                "Codec capability source: bundled scrcpy-server | " +
                    "serial=\(serial) | " +
                    "serverVersion=\(ScrcpyServerMetadata.version) | " +
                    "encoderCount=\(parsed.count) | " +
                    "fallbackReason=ok"
            )
            return (parsed, "ok")
        } catch {
            let message = error.localizedDescription
            log?(
                "Codec capability source: bundled scrcpy-server | " +
                    "serial=\(serial) | " +
                    "serverVersion=\(ScrcpyServerMetadata.version) | " +
                    "encoderCount=0 | " +
                    "fallbackReason=\(message)"
            )
            return ([], message)
        }
    }

    private static func remoteBuildFingerprint(
        adbExecutable: String,
        commandPrefix: [String],
        serial: String
    ) -> String? {
        return readBuildProperty(
            adbExecutable: adbExecutable,
            commandPrefix: commandPrefix,
            serial: serial,
            property: "ro.build.fingerprint"
        )
    }

    private static func remoteBuildSdk(
        adbExecutable: String,
        commandPrefix: [String],
        serial: String
    ) -> Int? {
        guard let value = readBuildProperty(
            adbExecutable: adbExecutable,
            commandPrefix: commandPrefix,
            serial: serial,
            property: "ro.build.version.sdk"
        ) else {
            return nil
        }
        return Int(value)
    }

    private static func currentDiscoveryMetadata(
        adbExecutable: String,
        commandPrefix: [String],
        serial: String
    ) -> ScrcpyCodecCapabilityMetadata {
        let fingerprint = remoteBuildFingerprint(
            adbExecutable: adbExecutable,
            commandPrefix: commandPrefix,
            serial: serial
        )
        let sdk = remoteBuildSdk(
            adbExecutable: adbExecutable,
            commandPrefix: commandPrefix,
            serial: serial
        )
        return ScrcpyCodecCapabilityMetadata(
            serverVersion: ScrcpyServerMetadata.version,
            serverSHA256: ScrcpyServerMetadata.sha256,
            androidFingerprint: fingerprint,
            androidSdk: sdk,
            capturedAt: Date()
        )
    }

    private static func readBuildProperty(
        adbExecutable: String,
        commandPrefix: [String],
        serial: String,
        property: String
    ) -> String? {
        guard let result = try? NativeProcess.run(
            adbExecutable,
            commandPrefix + ["-s", serial, "shell", "getprop", property]
        ) else {
            return nil
        }
        guard result.status == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func cacheAgeText(capturedAt: Date) -> String {
        let ageInSeconds = max(0, Int(Date().timeIntervalSince(capturedAt)))
        let ageInDays = ageInSeconds / (24 * 60 * 60)
        return "\(ageInDays)d"
    }

    private static func cacheFingerprintMatch(cached: String?, current: String?) -> Bool {
        guard let cached = cached?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cached.isEmpty else {
            return true
        }
        guard let current = current?.trimmingCharacters(in: .whitespacesAndNewlines),
              !current.isEmpty else {
            return true
        }
        return cached == current
    }
}
