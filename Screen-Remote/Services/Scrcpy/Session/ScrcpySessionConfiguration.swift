import AppKit
import AudioToolbox
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

enum ScrcpyMediaKind: String, Codable, Sendable {
    case video
    case audio
}

enum ScrcpyCodecAcceleration: String, Codable, Sendable {
    case hardware = "hw"
    case software = "sw"
    case hybrid
    case unknown

    var rank: Int {
        switch self {
        case .hardware: 0
        case .hybrid: 20
        case .unknown: 40
        case .software: 60
        }
    }
}

struct ScrcpyRemoteEncoder: Codable, Hashable, Sendable {
    let kind: ScrcpyMediaKind
    let codec: String
    let name: String
    let acceleration: ScrcpyCodecAcceleration
    let isVendor: Bool
    let aliasOf: String?

    var isAlias: Bool { aliasOf != nil }
}

struct ScrcpyCodecSelection: Equatable, Sendable {
    let codec: String
    let encoder: String?
    let decoder: String?

    init(codec: String, encoder: String?, decoder: String? = nil) {
        self.codec = codec
        self.encoder = encoder
        self.decoder = decoder
    }
}

struct ScrcpyLocalAudioDecoder: Codable, Equatable, Sendable {
    let id: String
    let codec: String
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32

    var componentDescription: AudioClassDescription? {
        guard codec != "raw" else { return nil }
        return AudioClassDescription(
            mType: componentType,
            mSubType: componentSubType,
            mManufacturer: componentManufacturer
        )
    }
}

struct ScrcpyLocalVideoDecoderCapability: Codable, Equatable, Sendable {
    let id: String
    let hardwareAvailable: Bool
}

struct ScrcpyCodecCapabilityMetadata: Codable, Equatable, Sendable {
    let serverVersion: String
    let serverSHA256: String
    let androidFingerprint: String?
    let androidSdk: Int?
    let capturedAt: Date
}

private struct ScrcpyCodecCapabilityCacheFile: Codable {
    var version = 1
    var localRuntimeSignature = ""
    var remoteEncoders: [String: [ScrcpyRemoteEncoder]] = [:]
    var remoteEncoderMetadata: [String: ScrcpyCodecCapabilityMetadata] = [:]
    var localVideoDecoders: [ScrcpyLocalVideoDecoderCapability] = []
    var localAudioDecoders: [ScrcpyLocalAudioDecoder] = []
}

enum ScrcpyCodecCapabilityCache {
    private static let lock = NSLock()
    private static let remoteEncoderCacheTTL: TimeInterval = 7 * 24 * 60 * 60
    private static let directory: URL = {
        if let override = ProcessInfo.processInfo.environment["SCREEN_REMOTE_CODEC_CACHE_DIRECTORY"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Screen Remote", isDirectory: true)
    }()
    private static let url = directory.appendingPathComponent("codec-capabilities.json")
    private static var cache = load()

    static func remoteEncoders(for target: String, kind: ScrcpyMediaKind? = nil) -> [ScrcpyRemoteEncoder] {
        lock.lock()
        defer { lock.unlock() }
        let encoders = cache.remoteEncoders[target] ?? []
        return kind.map { requested in encoders.filter { $0.kind == requested } } ?? encoders
    }

    static func remoteEncoderMetadata(for target: String) -> ScrcpyCodecCapabilityMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return cache.remoteEncoderMetadata[target]
    }

    static func saveRemoteEncoders(
        _ encoders: [ScrcpyRemoteEncoder],
        for target: String,
        replacing kind: ScrcpyMediaKind? = nil,
        metadata: ScrcpyCodecCapabilityMetadata? = nil
    ) {
        guard !target.isEmpty, !encoders.isEmpty else { return }
        lock.lock()
        if let kind {
            var merged = cache.remoteEncoders[target] ?? []
            merged.removeAll { $0.kind == kind }
            merged.append(contentsOf: encoders.filter { $0.kind == kind })
            cache.remoteEncoders[target] = uniqueEncoders(merged)
        } else {
            cache.remoteEncoders[target] = uniqueEncoders(encoders)
        }
        if let metadata {
            cache.remoteEncoderMetadata[target] = metadata
        }
        persistLocked()
        lock.unlock()
    }

    static func clearRemoteEncoders(for target: String) {
        lock.lock()
        cache.remoteEncoders.removeValue(forKey: target)
        cache.remoteEncoderMetadata.removeValue(forKey: target)
        persistLocked()
        lock.unlock()
    }

    static func diskUsageBytes() -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        cache = ScrcpyCodecCapabilityCacheFile()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            NSLog("Screen Remote: failed to clear codec cache: %@", error.localizedDescription)
        }
    }

    static func localVideoDecoders() -> [ScrcpyLocalVideoDecoderCapability]? {
        lock.lock()
        defer { lock.unlock() }
        guard cache.localRuntimeSignature == runtimeSignature,
              !cache.localVideoDecoders.isEmpty else { return nil }
        return cache.localVideoDecoders
    }

    static func saveLocalVideoDecoders(_ decoders: [ScrcpyLocalVideoDecoderCapability]) {
        guard !decoders.isEmpty else { return }
        lock.lock()
        prepareLocalCacheLocked()
        cache.localVideoDecoders = decoders
        persistLocked()
        lock.unlock()
    }

    static func localAudioDecoders() -> [ScrcpyLocalAudioDecoder]? {
        lock.lock()
        defer { lock.unlock() }
        guard cache.localRuntimeSignature == runtimeSignature,
              !cache.localAudioDecoders.isEmpty else { return nil }
        return cache.localAudioDecoders
    }

    static func saveLocalAudioDecoders(_ decoders: [ScrcpyLocalAudioDecoder]) {
        guard !decoders.isEmpty else { return }
        lock.lock()
        prepareLocalCacheLocked()
        cache.localAudioDecoders = decoders
        persistLocked()
        lock.unlock()
    }

    private static var runtimeSignature: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func prepareLocalCacheLocked() {
        guard cache.localRuntimeSignature != runtimeSignature else { return }
        cache.localRuntimeSignature = runtimeSignature
        cache.localVideoDecoders = []
        cache.localAudioDecoders = []
    }

    private static func uniqueEncoders(_ encoders: [ScrcpyRemoteEncoder]) -> [ScrcpyRemoteEncoder] {
        var seen = Set<ScrcpyRemoteEncoder>()
        return encoders.filter { seen.insert($0).inserted }
    }

    static func isValid(
        metadata: ScrcpyCodecCapabilityMetadata,
        currentFingerprint: String? = nil,
        currentSdk: Int? = nil
    ) -> Bool {
        return cacheInvalidationReason(
            metadata: metadata,
            currentFingerprint: currentFingerprint,
            currentSdk: currentSdk
        ) == nil
    }

    static func cacheInvalidationReason(
        metadata: ScrcpyCodecCapabilityMetadata,
        currentFingerprint: String? = nil,
        currentSdk: Int? = nil
    ) -> String? {
        if metadata.serverVersion != ScrcpyServerMetadata.version {
            return "server version changed"
        }
        if metadata.serverSHA256 != ScrcpyServerMetadata.sha256 {
            return "server hash changed"
        }
        if Date().timeIntervalSince(metadata.capturedAt) > remoteEncoderCacheTTL {
            return "cache expired"
        }
        if let cachedFingerprint = metadata.androidFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cachedFingerprint.isEmpty,
           let fingerprint = currentFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fingerprint.isEmpty,
           cachedFingerprint != fingerprint {
            return "android fingerprint changed"
        }
        if let cachedSdk = metadata.androidSdk,
           let sdk = currentSdk,
           cachedSdk != sdk {
            return "android sdk changed"
        }
        return nil
    }

    private static func persistLocked() {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(cache).write(to: url, options: .atomic)
        } catch {
            NSLog("Screen Remote: failed to save codec capability cache: %@", error.localizedDescription)
        }
    }

    private static func load() -> ScrcpyCodecCapabilityCacheFile {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(ScrcpyCodecCapabilityCacheFile.self, from: data),
              value.version == 1 else {
            return ScrcpyCodecCapabilityCacheFile()
        }
        return value
    }
}

func parseScrcpyRemoteEncoders(_ output: String) -> [ScrcpyRemoteEncoder] {
    let pattern = #"--(video|audio)-codec=([^\s]+)\s+--(?:video|audio)-encoder=['\"]?([^'\"\s]+)['\"]?(?:\s+\((hw|sw|hybrid)\))?(?:\s+\[vendor\])?(?:\s+\(alias for ([^)]+)\))?"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

    return output.split(whereSeparator: \.isNewline).compactMap { rawLine in
        let line = String(rawLine)
        let fullRange = NSRange(line.startIndex..., in: line)
        guard let match = expression.firstMatch(in: line, range: fullRange),
              let kindRange = Range(match.range(at: 1), in: line),
              let codecRange = Range(match.range(at: 2), in: line),
              let nameRange = Range(match.range(at: 3), in: line),
              let kind = ScrcpyMediaKind(rawValue: String(line[kindRange])) else {
            return nil
        }
        let acceleration = Range(match.range(at: 4), in: line)
            .flatMap { ScrcpyCodecAcceleration(rawValue: String(line[$0])) } ?? .unknown
        let aliasOf = Range(match.range(at: 5), in: line).map {
            String(line[$0]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ScrcpyRemoteEncoder(
            kind: kind,
            codec: String(line[codecRange]).lowercased(),
            name: String(line[nameRange]),
            acceleration: acceleration,
            isVendor: line.contains("[vendor]"),
            aliasOf: aliasOf
        )
    }
}

func codecForVideoDecoderSelection(_ selection: String) -> String? {
    switch selection.lowercased() {
    case "videotoolbox.h264": "h264"
    case "videotoolbox.hevc", "videotoolbox.h265": "h265"
    case "videotoolbox.av1": "av1"
    case "videotoolbox.vp9": "vp9"
    case "videotoolbox.vp8": "vp8"
    default: nil
    }
}

func codecForAudioDecoderSelection(_ selection: String) -> String? {
    let normalized = selection.lowercased()
    if normalized.contains("opus") { return "opus" }
    if normalized.contains("aac") { return "aac" }
    if normalized.contains("flac") { return "flac" }
    if normalized.contains("pcm") || normalized.contains("raw") { return "raw" }
    return nil
}

func inferVideoCodec(fromEncoderName name: String) -> String? {
    let normalized = name.lowercased()
    if normalized.contains("h265") || normalized.contains("hevc") { return "h265" }
    if normalized.contains("h264") || normalized.contains("avc") { return "h264" }
    if normalized.contains("av1") || normalized.contains("av01") { return "av1" }
    if normalized.contains("vp9") { return "vp9" }
    if normalized.contains("vp8") { return "vp8" }
    return nil
}

func inferAudioCodec(fromEncoderName name: String) -> String? {
    let normalized = name.lowercased()
    if normalized.contains("opus") { return "opus" }
    if normalized.contains("aac") || normalized.contains("mp4a") { return "aac" }
    if normalized.contains("flac") { return "flac" }
    if normalized.contains("pcm") || normalized.contains("raw") { return "raw" }
    return nil
}

func selectNativeVideoCodec(
    remoteEncoders: [ScrcpyRemoteEncoder],
    requestedEncoder: String,
    requestedDecoder: String,
    supportedCodecs: [String] = ["h265", "h264"]
) -> ScrcpyCodecSelection {
    let remote = remoteEncoders.filter { $0.kind == .video }
    let requestedEncoder = requestedEncoder.trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedDecoder = requestedDecoder.trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedCodec = codecForVideoDecoderSelection(requestedDecoder)

    func select(encoder requestedEncoder: String, codec requestedCodec: String?) -> ScrcpyCodecSelection? {
        let eligibleCodecs = requestedCodec.map { supportedCodecs.contains($0) ? [$0] : [] } ?? supportedCodecs
        let namedEncoders = remote.filter { $0.name == requestedEncoder }
        if !requestedEncoder.isEmpty,
           let encoder = bestRemoteEncoder(namedEncoders.filter { eligibleCodecs.contains($0.codec) }) {
            return ScrcpyCodecSelection(codec: encoder.codec, encoder: encoder.name)
        }
        if !requestedEncoder.isEmpty, namedEncoders.isEmpty,
           let inferredCodec = inferVideoCodec(fromEncoderName: requestedEncoder),
           requestedCodec == nil || requestedCodec == inferredCodec,
           eligibleCodecs.contains(inferredCodec) {
            return ScrcpyCodecSelection(codec: inferredCodec, encoder: requestedEncoder)
        }
        if requestedEncoder.isEmpty {
            for codec in eligibleCodecs {
                if let encoder = bestRemoteEncoder(remote.filter { $0.codec == codec }) {
                    return ScrcpyCodecSelection(codec: codec, encoder: encoder.name)
                }
            }
        }
        return nil
    }

    if (requestedDecoder.isEmpty || requestedCodec != nil),
       let requested = select(encoder: requestedEncoder, codec: requestedCodec) {
        return requested
    }
    if !requestedEncoder.isEmpty || !requestedDecoder.isEmpty,
       let automatic = select(encoder: "", codec: nil) {
        return automatic
    }

    // Encoder probing may fail on unusual devices. H.264 is scrcpy's stable
    // baseline and is implemented by the native decoder, so it is the only
    // safe unprobed fallback.
    return ScrcpyCodecSelection(codec: "h264", encoder: nil)
}

func selectNativeAudioCodec(
    remoteEncoders: [ScrcpyRemoteEncoder],
    requestedEncoder: String,
    requestedDecoder: String,
    localDecoders: [ScrcpyLocalAudioDecoder] = coreAudioDecoderCapabilities()
) -> ScrcpyCodecSelection {
    let remote = remoteEncoders.filter { $0.kind == .audio }
    let requestedEncoder = requestedEncoder.trimmingCharacters(in: .whitespacesAndNewlines)
    let requestedDecoder = requestedDecoder.trimmingCharacters(in: .whitespacesAndNewlines)
    let fixedDecoder = localDecoders.first { $0.id == requestedDecoder }
    let requestedCodec = fixedDecoder?.codec
    let codecOrder = ["opus", "aac", "flac", "raw"]
    let supportedCodecs = codecOrder.filter { codec in localDecoders.contains { $0.codec == codec } }

    func select(
        encoder: String,
        codec: String?,
        decoder fixedDecoder: ScrcpyLocalAudioDecoder?
    ) -> ScrcpyCodecSelection? {
        let eligibleCodecs = codec.map { supportedCodecs.contains($0) ? [$0] : [] } ?? supportedCodecs
        for candidate in eligibleCodecs {
            if candidate == "raw" {
                if encoder.isEmpty {
                    return ScrcpyCodecSelection(codec: "raw", encoder: nil, decoder: nil)
                }
                continue
            }
            let hasDecoder = fixedDecoder?.codec == candidate ||
                (fixedDecoder == nil && localDecoders.contains { $0.codec == candidate })
            guard hasDecoder else { continue }
            let candidates: [ScrcpyRemoteEncoder]
            if encoder.isEmpty {
                candidates = remote.filter { $0.codec == candidate }
            } else {
                let named = remote.filter { $0.name == encoder }
                if named.isEmpty, inferAudioCodec(fromEncoderName: encoder) == candidate {
                    return ScrcpyCodecSelection(
                        codec: candidate,
                        encoder: encoder,
                        decoder: fixedDecoder?.id
                    )
                }
                candidates = named.filter { $0.codec == candidate }
            }
            if let selected = bestRemoteEncoder(candidates) {
                return ScrcpyCodecSelection(
                    codec: candidate,
                    encoder: selected.name,
                    decoder: fixedDecoder?.id
                )
            }
        }
        return nil
    }

    if (requestedDecoder.isEmpty || fixedDecoder != nil),
       let requested = select(
           encoder: requestedEncoder,
           codec: requestedCodec,
           decoder: fixedDecoder
       ) {
        return requested
    }
    if !requestedEncoder.isEmpty || !requestedDecoder.isEmpty,
       let automatic = select(encoder: "", codec: nil, decoder: nil) {
        return automatic
    }
    return ScrcpyCodecSelection(codec: "raw", encoder: nil)
}

func coreAudioDecoderCapabilities(forceRefresh: Bool = false) -> [ScrcpyLocalAudioDecoder] {
    if !forceRefresh, let cached = ScrcpyCodecCapabilityCache.localAudioDecoders() {
        return cached
    }
    let compressed: [(String, AudioFormatID)] = [
        ("opus", kAudioFormatOpus),
        ("aac", kAudioFormatMPEG4AAC),
        ("flac", kAudioFormatFLAC)
    ]
    let available = compressed.flatMap { codec, formatID -> [ScrcpyLocalAudioDecoder] in
        var formatID = formatID
        var byteCount: UInt32 = 0
        let infoStatus = withUnsafePointer(to: &formatID) { pointer in
            AudioFormatGetPropertyInfo(
                kAudioFormatProperty_Decoders,
                UInt32(MemoryLayout<AudioFormatID>.size),
                pointer,
                &byteCount
            )
        }
        guard infoStatus == noErr, byteCount >= MemoryLayout<AudioClassDescription>.size else { return [] }
        var descriptions = [AudioClassDescription](
            repeating: AudioClassDescription(),
            count: Int(byteCount) / MemoryLayout<AudioClassDescription>.size
        )
        let getStatus = withUnsafePointer(to: &formatID) { pointer in
            descriptions.withUnsafeMutableBytes { bytes in
                AudioFormatGetProperty(
                    kAudioFormatProperty_Decoders,
                    UInt32(MemoryLayout<AudioFormatID>.size),
                    pointer,
                    &byteCount,
                    bytes.baseAddress
                )
            }
        }
        guard getStatus == noErr else { return [] }
        return descriptions.map { description in
            let type = UInt32(description.mType)
            let subtype = UInt32(description.mSubType)
            let manufacturer = UInt32(description.mManufacturer)
            return ScrcpyLocalAudioDecoder(
                id: String(
                    format: "coreaudio.%@.%08X-%08X-%08X",
                    codec,
                    type,
                    subtype,
                    manufacturer
                ),
                codec: codec,
                componentType: type,
                componentSubType: subtype,
                componentManufacturer: manufacturer
            )
        }
    }
    let decoders = available + [ScrcpyLocalAudioDecoder(
        id: "coreaudio.raw",
        codec: "raw",
        componentType: 0,
        componentSubType: 0,
        componentManufacturer: 0
    )]
    ScrcpyCodecCapabilityCache.saveLocalAudioDecoders(decoders)
    return decoders
}

func availableCoreAudioCodecNames() -> [String] {
    let available = Set(coreAudioDecoderCapabilities().map(\.codec))
    return ["opus", "aac", "flac", "raw"].filter(available.contains)
}

func coreAudioDecoderCapability(identifier: String) -> ScrcpyLocalAudioDecoder? {
    coreAudioDecoderCapabilities().first { $0.id == identifier }
}

private func bestRemoteEncoder(_ encoders: [ScrcpyRemoteEncoder]) -> ScrcpyRemoteEncoder? {
    encoders.min {
        let leftRank = $0.acceleration.rank + ($0.isAlias ? 100 : 0)
        let rightRank = $1.acceleration.rank + ($1.isAlias ? 100 : 0)
        if leftRank != rightRank { return leftRank < rightRank }
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
}

func parseBitrate(_ value: String, fallback: Int) -> Int {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let last = normalized.last else { return fallback }
    let multiplier: Double
    let number: String
    switch last {
    case "K": multiplier = 1_000; number = String(normalized.dropLast())
    case "M": multiplier = 1_000_000; number = String(normalized.dropLast())
    case "G": multiplier = 1_000_000_000; number = String(normalized.dropLast())
    default: multiplier = 1; number = normalized
    }
    guard let parsed = Double(number), parsed > 0 else { return fallback }
    return Int(min(parsed * multiplier, Double(Int32.max)))
}
