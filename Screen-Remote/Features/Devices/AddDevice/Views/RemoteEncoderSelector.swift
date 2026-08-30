import Foundation
import SwiftUI

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
    let isNativeMode: Bool

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
                        adbPath: targetADBPath,
                        kind: kind,
                        isNativeMode: isNativeMode
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

func codecSortRank(_ codec: String, kind: RemoteEncoderKind) -> Int {
    let order = kind == .video
        ? ["h264", "h265", "av1", "vp8", "vp9"]
        : ["opus", "aac", "flac", "raw"]
    return order.firstIndex(of: codec) ?? order.count
}

func codecDisplayName(_ codec: String) -> String {
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

func codecMIMEType(_ codec: String, kind: RemoteEncoderKind) -> String {
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
