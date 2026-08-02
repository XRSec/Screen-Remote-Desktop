import Foundation

@main
struct CodecSelectionCheck {
    static func main() {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-remote-codec-cache-\(UUID().uuidString)", isDirectory: true)
        setenv("SCREEN_REMOTE_CODEC_CACHE_DIRECTORY", cacheDirectory.path, 1)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let output = """
        [server] INFO: List of video encoders:
            --video-codec=h264 --video-encoder=OMX.google.h264.encoder       (sw)
            --video-codec=h264 --video-encoder=c2.qti.avc.encoder           (hw) [vendor]
            --video-codec=h265 --video-encoder=c2.qti.hevc.encoder          (hw) [vendor]
            --video-codec=h265 --video-encoder=c2.qti.hevc.encoder.alias    (hw) [vendor] (alias for c2.qti.hevc.encoder)
            --video-codec=av1 --video-encoder='c2.qti.av1.encoder'          (hw) [vendor]
        [server] INFO: List of audio encoders:
            --audio-codec=opus --audio-encoder=c2.android.opus.encoder      (sw)
            --audio-codec=aac --audio-encoder=c2.android.aac.encoder        (sw)
        """

        let encoders = parseScrcpyRemoteEncoders(output)
        let localAudioDecoders = [
            localAudioDecoder("coreaudio.opus.test", codec: "opus"),
            localAudioDecoder("coreaudio.aac.test", codec: "aac"),
            localAudioDecoder("coreaudio.flac.test", codec: "flac"),
            localAudioDecoder("coreaudio.raw", codec: "raw")
        ]
        require(encoders.count == 7, "expected all structured encoder rows")
        require(
            encoders.first(where: { $0.name == "c2.qti.hevc.encoder.alias" })?.aliasOf
                == "c2.qti.hevc.encoder",
            "expected alias metadata"
        )

        let automatic = selectNativeVideoCodec(
            remoteEncoders: encoders,
            requestedEncoder: "",
            requestedDecoder: ""
        )
        require(
            automatic == ScrcpyCodecSelection(codec: "h265", encoder: "c2.qti.hevc.encoder"),
            "automatic selection must prefer a non-alias hardware H.265 encoder"
        )

        let requestedH264 = selectNativeVideoCodec(
            remoteEncoders: encoders,
            requestedEncoder: "",
            requestedDecoder: "videotoolbox.h264"
        )
        require(
            requestedH264 == ScrcpyCodecSelection(codec: "h264", encoder: "c2.qti.avc.encoder"),
            "an H.264 decoder route must constrain the remote encoder format"
        )

        let mismatchedRequest = selectNativeVideoCodec(
            remoteEncoders: encoders,
            requestedEncoder: "c2.qti.avc.encoder",
            requestedDecoder: "videotoolbox.hevc"
        )
        require(
            mismatchedRequest == ScrcpyCodecSelection(codec: "h265", encoder: "c2.qti.hevc.encoder"),
            "a known H.264 encoder must never be paired with an H.265 decoder route"
        )

        let reverseMismatch = selectNativeVideoCodec(
            remoteEncoders: encoders,
            requestedEncoder: "c2.qti.hevc.encoder",
            requestedDecoder: "videotoolbox.h264"
        )
        require(
            reverseMismatch == ScrcpyCodecSelection(codec: "h265", encoder: "c2.qti.hevc.encoder"),
            "an incompatible manual video pair must be ignored and reselected without either constraint"
        )

        let unsupportedAV1 = selectNativeVideoCodec(
            remoteEncoders: encoders,
            requestedEncoder: "c2.qti.av1.encoder",
            requestedDecoder: "videotoolbox.av1"
        )
        require(
            unsupportedAV1 == ScrcpyCodecSelection(codec: "h265", encoder: "c2.qti.hevc.encoder"),
            "an unimplemented AV1 route must ignore both constraints and reselect automatically"
        )

        let externalVP9 = selectNativeVideoCodec(
            remoteEncoders: encoders + [ScrcpyRemoteEncoder(
                kind: .video,
                codec: "vp9",
                name: "c2.android.vp9.encoder",
                acceleration: .software,
                isVendor: false,
                aliasOf: nil
            )],
            requestedEncoder: "c2.android.vp9.encoder",
            requestedDecoder: "",
            supportedCodecs: ["h265", "h264", "av1", "vp9", "vp8"]
        )
        require(
            externalVP9 == ScrcpyCodecSelection(codec: "vp9", encoder: "c2.android.vp9.encoder"),
            "the external scrcpy route must preserve a requested VP9 encoder"
        )

        let custom = selectNativeVideoCodec(
            remoteEncoders: [],
            requestedEncoder: "vendor.custom.avc.encoder",
            requestedDecoder: ""
        )
        require(
            custom == ScrcpyCodecSelection(codec: "h264", encoder: "vendor.custom.avc.encoder"),
            "a custom encoder may use implementation-name inference only as the final fallback"
        )

        let audio = selectNativeAudioCodec(
            remoteEncoders: encoders,
            requestedEncoder: "c2.android.opus.encoder",
            requestedDecoder: "coreaudio.opus.test",
            localDecoders: localAudioDecoders
        )
        require(
            audio == ScrcpyCodecSelection(
                codec: "opus",
                encoder: "c2.android.opus.encoder",
                decoder: "coreaudio.opus.test"
            ),
            "a compatible remote Opus encoder and local decoder must be selected"
        )

        let automaticAudio = selectNativeAudioCodec(
            remoteEncoders: encoders,
            requestedEncoder: "",
            requestedDecoder: "",
            localDecoders: localAudioDecoders
        )
        require(
            automaticAudio == ScrcpyCodecSelection(codec: "opus", encoder: "c2.android.opus.encoder"),
            "automatic audio selection must prefer Opus"
        )

        let incompatibleAudio = selectNativeAudioCodec(
            remoteEncoders: encoders,
            requestedEncoder: "c2.android.aac.encoder",
            requestedDecoder: "coreaudio.opus.test",
            localDecoders: localAudioDecoders
        )
        require(
            incompatibleAudio == ScrcpyCodecSelection(codec: "opus", encoder: "c2.android.opus.encoder"),
            "an incompatible manual audio pair must be ignored and reselected automatically"
        )

        let missingDecoderAudio = selectNativeAudioCodec(
            remoteEncoders: encoders,
            requestedEncoder: "",
            requestedDecoder: "coreaudio.opus.missing",
            localDecoders: localAudioDecoders
        )
        require(
            missingDecoderAudio == ScrcpyCodecSelection(codec: "opus", encoder: "c2.android.opus.encoder"),
            "a missing pinned audio decoder must be ignored instead of being silently treated as selected"
        )

        let rawAudio = selectNativeAudioCodec(
            remoteEncoders: [],
            requestedEncoder: "",
            requestedDecoder: "",
            localDecoders: localAudioDecoders
        )
        require(
            rawAudio == ScrcpyCodecSelection(codec: "raw", encoder: nil),
            "audio must fall back to RAW when no compressed encoder-decoder pair exists"
        )

        let videoEncoders = encoders.filter { $0.kind == .video }
        let audioEncoders = encoders.filter { $0.kind == .audio }
        ScrcpyCodecCapabilityCache.saveRemoteEncoders(videoEncoders, for: "device-1", replacing: .video)
        ScrcpyCodecCapabilityCache.saveRemoteEncoders(audioEncoders, for: "device-1", replacing: .audio)
        require(
            ScrcpyCodecCapabilityCache.remoteEncoders(for: "device-1", kind: .video) == videoEncoders,
            "video encoder cache must preserve the detected order"
        )
        require(
            ScrcpyCodecCapabilityCache.remoteEncoders(for: "device-1", kind: .audio) == audioEncoders,
            "audio encoder cache must coexist with the video cache"
        )

        let cachedVideoDecoders = [
            ScrcpyLocalVideoDecoderCapability(id: "videotoolbox.h264", hardwareAvailable: true),
            ScrcpyLocalVideoDecoderCapability(id: "videotoolbox.hevc", hardwareAvailable: false)
        ]
        ScrcpyCodecCapabilityCache.saveLocalVideoDecoders(cachedVideoDecoders)
        require(
            ScrcpyCodecCapabilityCache.localVideoDecoders() == cachedVideoDecoders,
            "local video decoder cache must round-trip"
        )
        ScrcpyCodecCapabilityCache.saveLocalAudioDecoders(localAudioDecoders)
        require(
            ScrcpyCodecCapabilityCache.localAudioDecoders() == localAudioDecoders,
            "local audio decoder cache must round-trip"
        )
        require(
            FileManager.default.fileExists(
                atPath: cacheDirectory.appendingPathComponent("codec-capabilities.json").path
            ),
            "codec capability cache must be persisted"
        )

        print("Codec selection checks passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("Codec selection check failed: \(message)\n".utf8))
            exit(1)
        }
    }

    private static func localAudioDecoder(_ id: String, codec: String) -> ScrcpyLocalAudioDecoder {
        ScrcpyLocalAudioDecoder(
            id: id,
            codec: codec,
            componentType: 0,
            componentSubType: 0,
            componentManufacturer: 0
        )
    }
}
