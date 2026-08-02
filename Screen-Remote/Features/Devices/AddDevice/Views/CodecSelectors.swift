import AppKit
import AudioToolbox
import SwiftUI
import VideoToolbox

enum RemoteEncoderKind: Sendable {
    case video
    case audio

    var title: LocalizedStringKey {
        switch self {
        case .video: "sessionSelectVideoEncoder"
        case .audio: "sessionSelectAudioEncoder"
        }
    }

    var detectedTitle: LocalizedStringKey {
        switch self {
        case .video: "sessionDetectedVideoEncoders"
        case .audio: "sessionDetectedAudioEncoders"
        }
    }

    var detectingText: LocalizedStringKey {
        switch self {
        case .video: "sessionDetectingVideoEncoders"
        case .audio: "sessionDetectingAudioEncoders"
        }
    }

    var emptyText: String {
        String.localizedKey(self == .video ? "sessionNoVideoEncoders" : "sessionNoAudioEncoders")
    }

}

struct RemoteEncoderSelector: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    @Binding var selection: String
    let connections: [DeviceConnection]
    let kind: RemoteEncoderKind

    @State private var detectedEncoders: [ScrcpyRemoteEncoder] = []
    @State private var isDetecting = false
    @State private var detectionMessage = ""
    @State private var codecFilter = "all"
    @State private var encoderSearchText = ""

    private var codecFilterOptions: [String] {
        ["all"] + Array(Set(detectedEncoders.map(\.codec))).sorted {
            codecSortRank($0, kind: kind) < codecSortRank($1, kind: kind)
        }
    }

    private var filteredEncoders: [ScrcpyRemoteEncoder] {
        let query = encoderSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return detectedEncoders.filter { encoder in
            let matchesCodec = codecFilter == "all" || encoder.codec == codecFilter
            let matchesSearch = query.isEmpty
                || encoder.name.localizedCaseInsensitiveContains(query)
                || codecMIMEType(encoder.codec, kind: kind).localizedCaseInsensitiveContains(query)
                || codecDisplayName(encoder.codec).localizedCaseInsensitiveContains(query)
            return matchesCodec && matchesSearch
        }
    }

    private var mediaKind: ScrcpyMediaKind {
        kind == .video ? .video : .audio
    }

    private var configuredCacheKeys: [String] {
        resolveCandidates(connections, mdnsOutput: "").map(\.adbSerial)
    }

    var body: some View {
        VStack(spacing: 0) {
            codecSelectorHeader(
                title: kind.title,
                refreshHelp: "sessionRefreshEncoders",
                isRefreshing: isDetecting,
                onRefresh: { detectEncoders(forceRefresh: true) },
                onDone: { presentationMode.wrappedValue.dismiss() }
            )
            Divider()
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                    codecSectionTitle("sessionEncoderOptions")
                    VStack(spacing: 0) {
                        codecChoiceRow(
                            title: String.localizedKey("sessionDefault"),
                            detail: String.localizedKey("sessionDefaultEncoderDetail"),
                            selected: selection.isEmpty
                        ) { selection = "" }
                        FormDivider()
                        HStack(spacing: 12) {
                            FormLabel(
                                title: "sessionCustomEncoder",
                                help: "sessionCustomEncoderHint"
                            )
                            Spacer()
                            TextField("sessionCustomEncoderPlaceholder", text: $selection)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: min(300, max(140, geometry.size.width - 230)))
                                .layoutPriority(1)
                        }
                        .padding(13)
                    }
                    .appCard(radius: 10)

                    codecSectionTitle(kind.detectedTitle)
                    if !detectedEncoders.isEmpty {
                        encoderListControls
                    }
                    if isDetecting {
                        HStack(spacing: 10) {
                            ProgressView().scaleEffect(0.75)
                            Text(kind.detectingText).foregroundColor(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard(radius: 10)
                    } else if detectedEncoders.isEmpty {
                        Text(detectionMessage.isEmpty
                            ? kind.emptyText
                            : detectionMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard(radius: 10)
                    } else if filteredEncoders.isEmpty {
                        Text("sessionNoMatchingEncoders")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard(radius: 10)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredEncoders.enumerated()), id: \.element) { index, encoder in
                                codecChoiceRow(
                                    title: encoder.name,
                                    detail: encoderHardwareHint(encoder),
                                    selected: selection == encoder.name
                                ) { selection = encoder.name }
                                if index < filteredEncoders.count - 1 { FormDivider() }
                            }
                        }
                        .appCard(radius: 10)
                    }
                    }
                    .frame(width: max(geometry.size.width - 36, 0), alignment: .leading)
                    .padding(18)
                }
            }
        }
        .onAppear {
            clearInitialCodecSelectorFocus()
            detectEncoders(forceRefresh: false)
        }
    }

    private var encoderListControls: some View {
        HStack(spacing: 12) {
            TextField("sessionSearchEncoders", text: $encoderSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Picker("sessionCodecFilterTitle", selection: $codecFilter) {
                ForEach(codecFilterOptions, id: \.self) { codec in
                    Text(codec == "all"
                        ? String.localizedKey("sessionCodecFilterAll")
                        : codecDisplayName(codec))
                        .tag(codec)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func detectEncoders(forceRefresh: Bool) {
        guard !isDetecting else { return }
        if !forceRefresh,
           let cached = configuredCacheKeys.lazy
               .map({ ScrcpyCodecCapabilityCache.remoteEncoders(for: $0, kind: mediaKind) })
               .first(where: { !$0.isEmpty }) {
            detectedEncoders = cached
            detectionMessage = ""
            return
        }
        isDetecting = true
        detectionMessage = ""
        let executable = appState.scrcpyPath
        let adbExecutable = appState.adbPath
        Task {
            do {
                let target = try await appState.screenSessions.resolveADBTarget(
                    connections: connections,
                    adbPath: adbExecutable,
                    log: { appState.appendSDLLog($0) }
                )
                let targetSerial = target.serial
                let targetADBPath = target.adbPath
                if !forceRefresh {
                    let cached = ScrcpyCodecCapabilityCache.remoteEncoders(
                        for: targetSerial,
                        kind: mediaKind
                    )
                    if !cached.isEmpty {
                        detectedEncoders = cached
                        isDetecting = false
                        return
                    }
                }
                let result = await Task.detached(priority: .userInitiated) {
                    detectRemoteEncoders(
                        target: targetSerial,
                        scrcpyPath: executable,
                        adbPath: targetADBPath,
                        kind: kind
                    )
                }.value
                detectedEncoders = result.encoders
                detectionMessage = result.message
                if !result.encoders.isEmpty {
                    for cacheKey in Set(configuredCacheKeys + [targetSerial]) {
                        ScrcpyCodecCapabilityCache.saveRemoteEncoders(
                            result.encoders,
                            for: cacheKey,
                            replacing: mediaKind
                        )
                    }
                }
                if !codecFilterOptions.contains(codecFilter) {
                    codecFilter = "all"
                }
            } catch {
                detectedEncoders = []
                detectionMessage = error.localizedDescription
            }
            isDetecting = false
        }
    }

    private func encoderHardwareHint(_ encoder: ScrcpyRemoteEncoder) -> String {
        codecMIMEType(encoder.codec, kind: kind)
    }
}

private func codecSortRank(_ codec: String, kind: RemoteEncoderKind) -> Int {
    let order = kind == .video
        ? ["h264", "h265", "av1", "vp8", "vp9"]
        : ["opus", "aac", "flac", "raw"]
    return order.firstIndex(of: codec) ?? order.count
}

private func codecDisplayName(_ codec: String) -> String {
    switch codec.lowercased() {
    case "h264": "H264"
    case "h265", "hevc": "H265"
    case "av1": "AV1"
    case "vp8": "VP8"
    case "vp9": "VP9"
    case "opus": "OPUS"
    case "aac": "AAC"
    case "flac": "FLAC"
    case "raw", "pcm": "RAW"
    default: codec.uppercased()
    }
}

private func codecMIMEType(_ codec: String, kind: RemoteEncoderKind) -> String {
    switch (kind, codec.lowercased()) {
    case (.video, "h264"): "video/avc"
    case (.video, "h265"), (.video, "hevc"): "video/hevc"
    case (.video, "av1"): "video/av01"
    case (.video, "vp8"): "video/x-vnd.on2.vp8"
    case (.video, "vp9"): "video/x-vnd.on2.vp9"
    case (.audio, "opus"): "audio/opus"
    case (.audio, "aac"): "audio/mp4a-latm"
    case (.audio, "flac"): "audio/flac"
    case (.audio, "raw"), (.audio, "pcm"): "audio/raw"
    default: codec.lowercased()
    }
}

private struct VideoDecoderOption: Identifiable {
    let id: String
    let title: String
    let detail: String
    let codec: String
    let acceleration: ScrcpyCodecAcceleration
    let route: VideoDecoderRoute
    let isLowLatency: Bool
    let isSelectable: Bool
}

private enum DecoderAccelerationFilter: String, CaseIterable {
    case all
    case hardware
    case software
}

private enum VideoDecoderRoute: String {
    case videoToolbox
    case ffmpeg
}

private enum VideoDecoderFeatureFilter: String, CaseIterable {
    case all
    case lowLatency
    case videoToolbox
    case ffmpeg
}

private func detectedVideoDecoderOptions(forceRefresh: Bool = false) -> [VideoDecoderOption] {
    let formats: [(id: String, name: String, type: CMVideoCodecType, nativeRoute: Bool)] = [
        ("videotoolbox.h264", "VideoToolbox · H264", kCMVideoCodecType_H264, true),
        ("videotoolbox.hevc", "VideoToolbox · H265", kCMVideoCodecType_HEVC, true),
        ("videotoolbox.av1", "VideoToolbox / FFmpeg · AV1", fourCCVideoCodec("av01"), false),
        ("ffmpeg.vp8", "FFmpeg · VP8", fourCCVideoCodec("vp08"), false),
        ("ffmpeg.vp9", "FFmpeg · VP9", fourCCVideoCodec("vp09"), false)
    ]
    let cached = forceRefresh ? nil : ScrcpyCodecCapabilityCache.localVideoDecoders()
    let cachedByID = Dictionary(uniqueKeysWithValues: (cached ?? []).map { ($0.id, $0) })
    let options = formats.map { format in
        let hardwareAvailable = cachedByID[format.id]?.hardwareAvailable
            ?? VTIsHardwareDecodeSupported(format.type)
        let detail: String
        if format.nativeRoute {
            detail = hardwareAvailable
                ? String.localizedKey("sessionHardwareDecoderAvailable")
                : String.localizedKey("sessionSystemDecoderRoute")
        } else if hardwareAvailable {
            detail = String.localizedKey("sessionDecoderDetectedRoutePending")
        } else {
            detail = String.localizedKey("sessionDecoderExternalRouteAvailable")
        }
        return VideoDecoderOption(
            id: format.id,
            title: format.name,
            detail: detail,
            codec: codecForVideoDecoderIdentifier(format.id),
            acceleration: hardwareAvailable ? .hardware : .software,
            route: format.nativeRoute ? .videoToolbox : .ffmpeg,
            isLowLatency: format.nativeRoute,
            isSelectable: format.nativeRoute
        )
    }
    if forceRefresh || cached == nil {
        ScrcpyCodecCapabilityCache.saveLocalVideoDecoders(options.map {
            ScrcpyLocalVideoDecoderCapability(
                id: $0.id,
                hardwareAvailable: $0.acceleration == .hardware
            )
        })
    }
    return options
}

struct VideoDecoderSelector: View {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selection: String
    @State private var searchText = ""
    @State private var codecFilter = "all"
    @State private var accelerationFilter = DecoderAccelerationFilter.all
    @State private var featureFilter = VideoDecoderFeatureFilter.all
    @State private var decoders = detectedVideoDecoderOptions()

    private var codecFilters: [String] {
        ["all"] + Array(Set(decoders.map(\.codec))).sorted {
            codecSortRank($0, kind: .video) < codecSortRank($1, kind: .video)
        }
    }

    private var filteredDecoders: [VideoDecoderOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return decoders.filter { decoder in
            let matchesCodec = codecFilter == "all" || decoder.codec == codecFilter
            let matchesAcceleration: Bool
            switch accelerationFilter {
            case .all: matchesAcceleration = true
            case .hardware: matchesAcceleration = decoder.acceleration == .hardware
            case .software: matchesAcceleration = decoder.acceleration != .hardware
            }
            let matchesFeature: Bool
            switch featureFilter {
            case .all: matchesFeature = true
            case .lowLatency: matchesFeature = decoder.isLowLatency
            case .videoToolbox: matchesFeature = decoder.route == .videoToolbox
            case .ffmpeg: matchesFeature = decoder.route == .ffmpeg
            }
            let matchesSearch = query.isEmpty
                || decoder.title.localizedCaseInsensitiveContains(query)
                || decoder.detail.localizedCaseInsensitiveContains(query)
                || codecMIMEType(decoder.codec, kind: .video).localizedCaseInsensitiveContains(query)
            return matchesCodec && matchesAcceleration && matchesFeature && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            codecSelectorHeader(
                title: "sessionSelectVideoDecoder",
                refreshHelp: "sessionRefreshDecoders",
                onRefresh: { decoders = detectedVideoDecoderOptions(forceRefresh: true) },
                onDone: { presentationMode.wrappedValue.dismiss() }
            )
            Divider()
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("sessionDecoderOptions")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    decoderSelectionCard

                    Text("sessionLocalVideoDecoders")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    decoderFilterControls
                    if filteredDecoders.isEmpty {
                        decoderEmptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredDecoders.enumerated()), id: \.element.id) { index, decoder in
                                codecChoiceRow(
                                    title: decoder.title,
                                    detail: decoderRowDetail(decoder),
                                    selected: selection == decoder.id
                                ) { selection = decoder.id }
                                .allowsHitTesting(decoder.isSelectable)
                                if index < filteredDecoders.count - 1 { FormDivider() }
                            }
                        }
                        .appCard(radius: 10)
                    }

                    Text("sessionVideoDecoderRecommendation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(13)
                        .appBackground(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .frame(width: max(geometry.size.width - 36, 0), alignment: .leading)
                    .padding(18)
                }
            }
        }
        .onAppear { clearInitialCodecSelectorFocus() }
    }

    private var decoderSelectionCard: some View {
        VStack(spacing: 0) {
            codecChoiceRow(
                title: String.localizedKey("sessionDefault"),
                detail: String.localizedKey("sessionDefaultDecoderDetail"),
                selected: selection.isEmpty
            ) { selection = "" }
            if !selection.isEmpty {
                FormDivider()
                codecChoiceRow(
                    title: decoders.first(where: { $0.id == selection })?.title ?? selection,
                    detail: String.localizedKey("sessionSelectedDecoder"),
                    selected: true
                ) {}
            }
        }
        .appCard(radius: 10)
    }

    private var decoderFilterControls: some View {
        HStack(spacing: 12) {
            TextField("sessionSearchDecoders", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Picker("sessionCodecFilterTitle", selection: $codecFilter) {
                ForEach(codecFilters, id: \.self) { codec in
                    Text(codec == "all" ? String.localizedKey("sessionFilterAll") : codecDisplayName(codec))
                        .tag(codec)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            Picker("sessionDecoderAccelerationFilter", selection: $accelerationFilter) {
                Text("sessionFilterAll").tag(DecoderAccelerationFilter.all)
                Text("sessionHardwareFilter").tag(DecoderAccelerationFilter.hardware)
                Text("sessionSoftwareFilter").tag(DecoderAccelerationFilter.software)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            Picker("sessionDecoderFeatureFilter", selection: $featureFilter) {
                Text("sessionFilterAll").tag(VideoDecoderFeatureFilter.all)
                Text("sessionLowLatencyFilter").tag(VideoDecoderFeatureFilter.lowLatency)
                Text("VideoToolbox").tag(VideoDecoderFeatureFilter.videoToolbox)
                Text("FFmpeg").tag(VideoDecoderFeatureFilter.ffmpeg)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var decoderEmptyState: some View {
        Text("sessionNoMatchingDecoders")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(radius: 10)
    }

    private func decoderRowDetail(_ decoder: VideoDecoderOption) -> String {
        let acceleration = decoder.acceleration == .hardware
            ? String.localizedKey("sessionHardwareFilter")
            : String.localizedKey("sessionSoftwareFilter")
        return "\(codecMIMEType(decoder.codec, kind: .video)) · \(acceleration) · \(decoder.detail)"
    }
}

private func codecForVideoDecoderIdentifier(_ identifier: String) -> String {
    if identifier.contains("h264") { return "h264" }
    if identifier.contains("hevc") || identifier.contains("h265") { return "h265" }
    if identifier.contains("av1") { return "av1" }
    if identifier.contains("vp8") { return "vp8" }
    if identifier.contains("vp9") { return "vp9" }
    return identifier
}

private func fourCCVideoCodec(_ value: String) -> CMVideoCodecType {
    value.utf8.reduce(0) { ($0 << 8) | CMVideoCodecType($1) }
}

struct AudioDecoderOption: Identifiable {
    let id: String
    let title: String
    let detail: String
    let codec: String
    let acceleration: ScrcpyCodecAcceleration
}

struct AudioDecoderSelector: View {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selection: String
    @State private var searchText = ""
    @State private var codecFilter = "all"
    @State private var accelerationFilter = DecoderAccelerationFilter.all
    @State private var decoders = coreAudioDecoderOptions()

    private var codecFilters: [String] {
        ["all"] + Array(Set(decoders.map(\.codec))).sorted {
            codecSortRank($0, kind: .audio) < codecSortRank($1, kind: .audio)
        }
    }

    private var filteredDecoders: [AudioDecoderOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return decoders.filter { decoder in
            let matchesCodec = codecFilter == "all" || decoder.codec == codecFilter
            let matchesAcceleration: Bool
            switch accelerationFilter {
            case .all: matchesAcceleration = true
            case .hardware: matchesAcceleration = decoder.acceleration == .hardware
            case .software: matchesAcceleration = decoder.acceleration != .hardware
            }
            let matchesSearch = query.isEmpty
                || decoder.title.localizedCaseInsensitiveContains(query)
                || decoder.detail.localizedCaseInsensitiveContains(query)
                || codecMIMEType(decoder.codec, kind: .audio).localizedCaseInsensitiveContains(query)
            return matchesCodec && matchesAcceleration && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            codecSelectorHeader(
                title: "sessionSelectAudioDecoder",
                refreshHelp: "sessionRefreshDecoders",
                onRefresh: { decoders = coreAudioDecoderOptions(forceRefresh: true) },
                onDone: { presentationMode.wrappedValue.dismiss() }
            )
            Divider()
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("sessionDecoderOptions")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    decoderSelectionCard

                    Text("sessionLocalAudioDecoders")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    decoderFilterControls
                    if filteredDecoders.isEmpty {
                        decoderEmptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredDecoders.enumerated()), id: \.element.id) { index, decoder in
                                codecChoiceRow(
                                    title: decoder.title,
                                    detail: decoderRowDetail(decoder),
                                    selected: selection == decoder.id
                                ) { selection = decoder.id }
                                if index < filteredDecoders.count - 1 { FormDivider() }
                            }
                        }
                        .appCard(radius: 10)
                    }

                    Text("sessionAudioDecoderEnumerationNote")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(13)
                        .appBackground(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .frame(width: max(geometry.size.width - 36, 0), alignment: .leading)
                    .padding(18)
                }
            }
        }
        .onAppear { clearInitialCodecSelectorFocus() }
    }

    private var decoderSelectionCard: some View {
        VStack(spacing: 0) {
            codecChoiceRow(
                title: String.localizedKey("sessionDefault"),
                detail: String.localizedKey("sessionDefaultAudioDecoderDetail"),
                selected: selection.isEmpty
            ) { selection = "" }
            if !selection.isEmpty {
                FormDivider()
                codecChoiceRow(
                    title: decoders.first(where: { $0.id == selection })?.title ?? selection,
                    detail: String.localizedKey("sessionSelectedDecoder"),
                    selected: true
                ) {}
            }
        }
        .appCard(radius: 10)
    }

    private var decoderFilterControls: some View {
        HStack(spacing: 12) {
            TextField("sessionSearchDecoders", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Picker("sessionCodecFilterTitle", selection: $codecFilter) {
                ForEach(codecFilters, id: \.self) { codec in
                    Text(codec == "all" ? String.localizedKey("sessionFilterAll") : codecDisplayName(codec))
                        .tag(codec)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            Picker("sessionDecoderAccelerationFilter", selection: $accelerationFilter) {
                Text("sessionFilterAll").tag(DecoderAccelerationFilter.all)
                Text("sessionHardwareFilter").tag(DecoderAccelerationFilter.hardware)
                Text("sessionSoftwareFilter").tag(DecoderAccelerationFilter.software)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var decoderEmptyState: some View {
        Text("sessionNoMatchingDecoders")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(radius: 10)
    }

    private func decoderRowDetail(_ decoder: AudioDecoderOption) -> String {
        let acceleration = decoder.acceleration == .hardware
            ? String.localizedKey("sessionHardwareFilter")
            : String.localizedKey("sessionSoftwareFilter")
        return "\(codecMIMEType(decoder.codec, kind: .audio)) · \(acceleration) · \(decoder.detail)"
    }
}

private func clearInitialCodecSelectorFocus() {
    DispatchQueue.main.async {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if window?.firstResponder is NSTextView {
            window?.makeFirstResponder(nil)
        }
    }
}

private func codecSelectorHeader(
    title: LocalizedStringKey,
    refreshHelp: LocalizedStringKey,
    isRefreshing: Bool = false,
    onRefresh: @escaping () -> Void,
    onDone: @escaping () -> Void
) -> some View {
    HStack {
        Text(title).font(.headline)
        Spacer()
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(isRefreshing)
        .help(refreshHelp)
        Button("commonDone", action: onDone)
            .keyboardShortcut(.defaultAction)
    }
    .padding(16)
}

func coreAudioDecoderOptions(forceRefresh: Bool = false) -> [AudioDecoderOption] {
    coreAudioDecoderCapabilities(forceRefresh: forceRefresh).map { decoder in
        if decoder.codec == "raw" {
            return AudioDecoderOption(
                id: decoder.id,
                title: "Core Audio · PCM",
                detail: String.localizedKey("sessionNativeAudioFormat"),
                codec: "raw",
                acceleration: .software
            )
        }
        let component = [
            fourCharacterCode(decoder.componentSubType),
            fourCharacterCode(decoder.componentManufacturer)
        ].joined(separator: " · ")
        return AudioDecoderOption(
            id: decoder.id,
            title: "Core Audio · \(decoder.codec.uppercased())",
            detail: String(
                format: String.localizedKey("sessionAudioDecoderComponent"),
                component
            ),
            codec: decoder.codec,
            acceleration: .software
        )
    }
}

func fourCharacterCode(_ value: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff)
    ]
    let text = String(bytes: bytes, encoding: .macOSRoman) ?? ""
    return text.allSatisfy { $0.isASCII && !$0.isWhitespace } ? text : String(format: "0x%08X", value)
}

func codecSectionTitle(_ key: LocalizedStringKey) -> some View {
    Text(key)
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
}

func codecChoiceRow(
    title: String,
    detail: String,
    selected: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 18, height: 18)
            } else {
                Circle()
                    .stroke(Color.primary.opacity(0.32), lineWidth: 1.25)
                    .frame(width: 13, height: 13)
                    .frame(width: 18, height: 18)
            }
        }
        .padding(13)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

func closestPreset(_ value: String, values: [Int], fallback: Int) -> String {
    guard let parsed = Int(value), let closest = values.min(by: {
        abs($0 - parsed) < abs($1 - parsed)
    }) else {
        return String(fallback)
    }
    return String(closest)
}

func closestBitratePreset(_ value: String, values: [Int], fallback: Int) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let megabits: Double?
    if normalized.hasSuffix("m") {
        megabits = Double(normalized.dropLast())
    } else if normalized.hasSuffix("k") {
        megabits = Double(normalized.dropLast()).map { $0 / 1_000 }
    } else {
        megabits = Double(normalized).map { $0 / 1_000_000 }
    }
    guard let megabits, let closest = values.min(by: {
        abs(Double($0) - megabits) < abs(Double($1) - megabits)
    }) else {
        return "\(fallback)M"
    }
    return "\(closest)M"
}

struct RemoteEncoderDetectionResult {
    let encoders: [ScrcpyRemoteEncoder]
    let message: String
}

func detectRemoteEncoders(
    target: String,
    scrcpyPath: String,
    adbPath: String,
    kind: RemoteEncoderKind
) -> RemoteEncoderDetectionResult {
    guard !target.isEmpty else {
        return RemoteEncoderDetectionResult(
            encoders: [],
            message: String.localizedKey("sessionEncoderAddressRequired")
        )
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: scrcpyPath.isEmpty ? "/usr/bin/env" : scrcpyPath)
    process.arguments = (scrcpyPath.isEmpty ? ["scrcpy"] : []) + ["--serial", target, "--list-encoders"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    var environment = ProcessInfo.processInfo.environment
    if FileManager.default.isExecutableFile(atPath: adbPath) {
        environment["ADB"] = adbPath
        let platformTools = URL(fileURLWithPath: adbPath).deletingLastPathComponent().path
        environment["PATH"] = "\(platformTools):\(environment["PATH"] ?? "")"
    }
    process.environment = environment

    do {
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let mediaKind: ScrcpyMediaKind = kind == .video ? .video : .audio
        let implementedCodecs: Set<String> = kind == .video
            ? ["h264", "h265", "av1", "vp8", "vp9"]
            : Set(availableCoreAudioCodecNames()).subtracting(["raw"])
        let compatible = parseScrcpyRemoteEncoders(text).filter {
            $0.kind == mediaKind && implementedCodecs.contains($0.codec)
        }
        let encoders = Array(Set(compatible)).sorted {
            if $0.codec != $1.codec { return $0.codec < $1.codec }
            let leftRank = $0.acceleration.rank + ($0.isAlias ? 100 : 0)
            let rightRank = $1.acceleration.rank + ($1.isAlias ? 100 : 0)
            if leftRank != rightRank { return leftRank < rightRank }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if !encoders.isEmpty {
            return RemoteEncoderDetectionResult(encoders: encoders, message: "")
        }
        if kind == .audio,
           parseScrcpyRemoteEncoders(text).contains(where: { $0.kind == .audio }) {
            return RemoteEncoderDetectionResult(
                encoders: [],
                message: String.localizedKey("sessionAudioDecoderEnumerationNote")
            )
        }
        let lastMessage = text.split(separator: "\n").last.map(String.init) ?? ""
        return RemoteEncoderDetectionResult(
            encoders: [],
            message: lastMessage.isEmpty ? kind.emptyText : lastMessage
        )
    } catch {
        return RemoteEncoderDetectionResult(encoders: [], message: error.localizedDescription)
    }
}
