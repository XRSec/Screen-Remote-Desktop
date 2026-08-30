import Foundation

extension NativeScrcpySession {
    func requestedVideoCodec() -> String? {
        if let codec = codecForVideoDecoderSelection(options.videoDecoder.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return codec
        }
        return inferVideoCodec(fromEncoderName: options.videoEncoder.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func codecFallbackPolicy() -> CodecFallbackPolicy {
        hasExplicitVideoCodecRequest ? .strict : .automatic
    }

    var hasExplicitVideoCodecRequest: Bool {
        let encoder = options.videoEncoder.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoder = options.videoDecoder.trimmingCharacters(in: .whitespacesAndNewlines)
        return !encoder.isEmpty || !decoder.isEmpty
    }

    func requestedVideoCodecLabel() -> String? {
        if let codec = requestedVideoCodec() { return codec.uppercased() }
        let encoder = options.videoEncoder.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoder = options.videoDecoder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !decoder.isEmpty { return decoder }
        if !encoder.isEmpty { return encoder }
        return nil
    }

    func fallbackNativeVideoCodec(
        remoteEncoders: [ScrcpyRemoteEncoder],
        requestedCodec: String,
        currentSelection: ScrcpyCodecSelection,
        failureReason: String?,
        policy: CodecFallbackPolicy
    ) -> ScrcpyCodecSelection? {
        guard policy == .automatic else { return nil }
        guard let failureReason, !failureReason.isEmpty else { return nil }
        guard requestedCodec == currentSelection.codec else { return nil }

        switch currentSelection.codec {
        case "h265":
            guard requestedCodec == "h265" else { return nil }
            return selectNativeVideoCodec(
                remoteEncoders: remoteEncoders,
                requestedEncoder: "",
                requestedDecoder: "videotoolbox.h264",
                supportedCodecs: ["h264"]
            )
        case "av1":
            return nil
        default:
            return nil
        }
    }

    func logCodecFallback(
        requestedCodec: String,
        appliedCodec: String,
        reason: String,
        log: @escaping (String) -> Void
    ) {
        log("Codec resolution:")
        log("Requested: \(requestedCodec.uppercased())")
        log("Applied: \(appliedCodec.uppercased())")
        log("Fallback: \(reason)")
    }

    func logExplicitCodecRequestFailed(
        requestedCodec: String,
        reason: String,
        log: @escaping (String) -> Void
    ) {
        log("Explicit codec request failed")
        log("Requested: \(requestedCodec.uppercased())")
        log("Reason: \(reason)")
    }

    static func serverCodecFailureReason(from line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("hevc decoder unavailable") || lower.contains("h265 decoder unavailable") {
            return "HEVC decoder unavailable"
        }
        if lower.contains("hevc") && lower.contains("unavailable") && lower.contains("decoder") {
            return "HEVC decoder unavailable"
        }
        if lower.contains("hevc") && lower.contains("not supported") {
            return "HEVC decoder unavailable"
        }
        if lower.contains("h265") && lower.contains("not supported") {
            return "HEVC decoder unavailable"
        }
        if lower.contains("hevc") && lower.contains("unsupported") {
            return "HEVC decoder unavailable"
        }
        return nil
    }

    static func startupCodecFailureReason(
        error: Error,
        selectedCodec: String,
        serverReason: String?
    ) -> String? {
        guard selectedCodec == "h265" else { return nil }
        if let serverReason,
           !serverReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return serverReason
        }
        if case NativeScrcpyError.unsupportedCodec(let codec) = error,
           codec == "h265" || codec == "hevc" {
            return "HEVC codec mismatch"
        }
        if case NativeScrcpyError.decoderFailed(let detail) = error {
            let lower = detail.lowercased()
            if lower.contains("h265") || lower.contains("hevc") || lower.contains("session creation") {
                return "HEVC decoder unavailable"
            }
            return "HEVC decoder unavailable"
        }
        if case NativeScrcpyError.commandFailed(let detail) = error,
           detail.lowercased().contains("hevc"), detail.lowercased().contains("unsupported") {
            return "HEVC decoder unavailable"
        }
        if case NativeScrcpyError.commandFailed(let detail) = error,
           detail.lowercased().contains("h265"), detail.lowercased().contains("unsupported") {
            return "HEVC codec mismatch"
        }
        return nil
    }

    func logSelectionFallbacks(
        video: ScrcpyCodecSelection,
        audio: ScrcpyCodecSelection,
        requestedVideoCodec: String?,
        log: @escaping (String) -> Void
    ) {
        if let requestedVideoCodec, requestedVideoCodec != video.codec {
            log("Requested video codec is \(requestedVideoCodec), resolved to \(video.codec)")
        }
        let requestedVideoEncoder = options.videoEncoder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestedVideoEncoder.isEmpty, video.encoder != requestedVideoEncoder {
            log("Requested video encoder is incompatible with the native decoder and was ignored: \(requestedVideoEncoder)")
        }
        if let requestedVideoCodec = codecForVideoDecoderSelection(options.videoDecoder),
           requestedVideoCodec != video.codec {
            log("Requested video decoder route is not implemented by the native session and was ignored: \(options.videoDecoder)")
        }
        if options.enableAudio {
            let requestedAudioEncoder = options.audioEncoder.trimmingCharacters(in: .whitespacesAndNewlines)
            if !requestedAudioEncoder.isEmpty, audio.encoder != requestedAudioEncoder {
                log("Requested audio encoder is incompatible with the local decoder and was ignored: \(requestedAudioEncoder)")
            }
            let requestedAudioDecoder = options.audioDecoder.trimmingCharacters(in: .whitespacesAndNewlines)
            if !requestedAudioDecoder.isEmpty, audio.decoder != requestedAudioDecoder {
                log("Requested audio decoder is unavailable or incompatible with the remote encoder and was ignored: \(requestedAudioDecoder)")
            }
        }
        log(
            "Native codec selection: video=\(video.codec), " +
                "videoEncoder=\(video.encoder ?? "server-default"), " +
                "audio=\(options.enableAudio ? audio.codec : "disabled"), " +
                "audioEncoder=\(audio.encoder ?? "not-applicable"), " +
                "audioDecoder=\(audio.decoder ?? (audio.codec == "raw" ? "not-applicable" : "system-default"))"
        )
    }
}
