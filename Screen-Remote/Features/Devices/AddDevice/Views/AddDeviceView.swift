import AppKit
import AudioToolbox
import SwiftUI
import VideoToolbox

struct AddDeviceView: View {
    enum Layout {
        static let contentMaxWidth: CGFloat = 1040
        static let sectionMinimumWidth: CGFloat = 300
        static let sectionSpacing: CGFloat = 18
    }

    enum FormSection: Int, CaseIterable, Hashable {
        case remoteDevice
        case connectionOptions
        case video
        case audio
        case otherOptions
        case virtualDisplay
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    let editingDevice: Device?

    @State var name = ""
    @State var transport: DeviceTransport = .tcp
    @State var host = ""
    @State var port = "5555"
    @State var serial = ""
    @State var backupConnections: [ConnectionDraft] = []
    @State var accentIndex = 0
    @State var groupIDs: Set<String> = []

    @State var maxSize = ""
    @State var videoBitrate = "4M"
    @State var maxFPS = "60"
    @State var videoEncoder = ""
    @State var videoDecoder = ""
    @State var enableAudio = false
    @State var clipboardSync = true
    @State var turnScreenOff = false
    @State var powerOffOnClose = false
    @State var cleanupOnDisconnect = true
    @State var keepControllerAwake = false
    @State var keepDeviceAwake = true
    @State var ignoreVideoEncoderConstraints = false
    @State var compatibilityMode = false
    @State var gameMode = false
    @State var showFloatingBall = true
    @State var enableHardwareDecoding = true
    @State var audioBitrate = "128K"
    @State var audioEncoder = ""
    @State var audioDecoder = ""
    @State var audioVolume = 1.0
    @State var newDisplayEnabled = false
    @State var virtualDisplaySystemDecorations = true
    @State var preserveVirtualDisplayContent = false
    @State var startApp = ""
    @State var newDisplayWidth = ""
    @State var newDisplayHeight = ""
    @State var newDisplayDPI = ""
    @State var showingGroupSelector = false
    @State var showingAddressEditor = false
    @State var showingLatencyTest = false
    @State var showingVideoEncoderSelector = false
    @State var showingVideoDecoderSelector = false
    @State var showingAudioEncoderSelector = false
    @State var showingAudioDecoderSelector = false
    @State var connectionDiscoveryTarget: ConnectionDiscoveryTarget?

    static let accentColors: [Color] = [.appIndigo, .blue, .appCyan, .green, .orange, .purple]
    var accentColors: [Color] { Self.accentColors }

    init(editing device: Device? = nil) {
        editingDevice = device
        guard let device else { return }
        let primary = device.primaryConnection
        let options = device.scrcpyOptions
        _name = State(initialValue: device.name)
        _transport = State(initialValue: primary?.transport ?? .tcp)
        _host = State(initialValue: primary?.host ?? "")
        _port = State(initialValue: String(primary?.port ?? 5555))
        _serial = State(initialValue: primary?.serial ?? "")
        _backupConnections = State(initialValue: device.connections.sorted { $0.priority < $1.priority }.dropFirst().map(ConnectionDraft.init))
        _groupIDs = State(initialValue: device.groupIDs)
        _accentIndex = State(initialValue: Self.closestAccentIndex(to: device.accent))
        _maxSize = State(initialValue: options.maxSize > 0 ? String(options.maxSize) : "")
        _videoBitrate = State(initialValue: options.videoBitrate.isEmpty ? "4M" : options.videoBitrate)
        _maxFPS = State(initialValue: options.maxFPS > 0 ? String(options.maxFPS) : "60")
        _videoEncoder = State(initialValue: options.videoEncoder)
        _videoDecoder = State(initialValue: options.videoDecoder)
        _enableAudio = State(initialValue: options.enableAudio)
        _audioBitrate = State(initialValue: options.audioBitrate)
        _audioEncoder = State(initialValue: options.audioEncoder)
        _audioDecoder = State(initialValue: options.audioDecoder)
        _audioVolume = State(initialValue: min(max(options.audioVolume, 1), 3))
        _clipboardSync = State(initialValue: options.clipboardSync)
        _turnScreenOff = State(initialValue: options.turnScreenOff)
        _powerOffOnClose = State(initialValue: options.powerOffOnClose)
        _cleanupOnDisconnect = State(initialValue: options.cleanupOnDisconnect)
        _keepControllerAwake = State(initialValue: options.keepControllerAwake)
        _keepDeviceAwake = State(initialValue: options.keepDeviceAwake)
        _ignoreVideoEncoderConstraints = State(initialValue: options.ignoreVideoEncoderConstraints)
        _compatibilityMode = State(initialValue: options.compatibilityMode)
        _gameMode = State(initialValue: options.gameMode)
        _showFloatingBall = State(initialValue: options.showFloatingBall)
        _enableHardwareDecoding = State(initialValue: options.enableHardwareDecoding)
        _newDisplayEnabled = State(initialValue: options.newDisplayEnabled)
        _virtualDisplaySystemDecorations = State(initialValue: options.virtualDisplaySystemDecorations)
        _preserveVirtualDisplayContent = State(initialValue: options.preserveVirtualDisplayContent)
        _startApp = State(initialValue: options.startApp)
        _newDisplayWidth = State(initialValue: options.newDisplayWidth == 0 ? "" : String(options.newDisplayWidth))
        _newDisplayHeight = State(initialValue: options.newDisplayHeight == 0 ? "" : String(options.newDisplayHeight))
        _newDisplayDPI = State(initialValue: options.newDisplayDPI == 0 ? "" : String(options.newDisplayDPI))
    }

    static func closestAccentIndex(to color: Color) -> Int {
        let target = NSColor(color).usingColorSpace(.sRGB) ?? .systemIndigo
        return accentColors.indices.min { lhs, rhs in
            func distance(_ candidate: Color) -> CGFloat {
                let value = NSColor(candidate).usingColorSpace(.sRGB) ?? .systemIndigo
                return pow(value.redComponent - target.redComponent, 2)
                    + pow(value.greenComponent - target.greenComponent, 2)
                    + pow(value.blueComponent - target.blueComponent, 2)
            }
            return distance(accentColors[lhs]) < distance(accentColors[rhs])
        } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            GeometryReader { _ in
                ScrollView {
                    VStack(spacing: 20) {
                        flowingContent
                        saveHint
                    }
                    .frame(maxWidth: Layout.contentMaxWidth)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .sheet(isPresented: $showingGroupSelector) {
                        SessionGroupSelector(selection: $groupIDs)
                            .environmentObject(appState)
                            .environment(\.locale, appState.resolvedLocale)
                            .appPresentationWidth(relativeTo: appState.appWindowWidth)
                            .appPresentationHeight(relativeTo: appState.appWindowHeight)
                    }
                    .sheet(isPresented: $showingAddressEditor) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("sessionAddressTitle").font(.headline)
                                Spacer()
                                Button("commonDone") { showingAddressEditor = false }
                                    .keyboardShortcut(.defaultAction)
                            }
                            .padding(16)
                            Divider()
                            ScrollView {
                                VStack(spacing: 18) {
                                    primaryConnectionSection
                                    backupConnectionsSection
                                }
                                .padding(18)
                            }
                        }
                        .environment(\.locale, appState.resolvedLocale)
                        .appPresentationWidth(relativeTo: appState.appWindowWidth)
                        .appPresentationHeight(relativeTo: appState.appWindowHeight)
                        .sheet(item: $connectionDiscoveryTarget) { target in
                            ConnectionDiscoveryPicker(
                                transport: target.transport,
                                currentAddress: discoveryCurrentAddress(for: target),
                                onSelect: { applyDiscoveredDevice($0, to: target) }
                            )
                            .environmentObject(appState)
                            .environment(\.locale, appState.resolvedLocale)
                            .appPresentationWidth(relativeTo: appState.appWindowWidth)
                            .appPresentationHeight(relativeTo: appState.appWindowHeight)
                        }
                    }
                    .sheet(isPresented: $showingLatencyTest) {
                        ConnectionLatencyTestView(connections: currentConnections)
                            .environmentObject(appState)
                            .environment(\.locale, appState.resolvedLocale)
                            .appPresentationWidth(relativeTo: appState.appWindowWidth)
                            .appPresentationHeight(relativeTo: appState.appWindowHeight)
                    }
                    .sheet(isPresented: $showingVideoEncoderSelector) {
                        RemoteEncoderSelector(
                            selection: $videoEncoder,
                            connections: currentConnections,
                            kind: .video
                        )
                        .environmentObject(appState)
                        .environment(\.locale, appState.resolvedLocale)
                        .appPresentationWidth(relativeTo: appState.appWindowWidth)
                        .appPresentationHeight(relativeTo: appState.appWindowHeight)
                    }
                    .sheet(isPresented: $showingVideoDecoderSelector) {
                        VideoDecoderSelector(selection: $videoDecoder)
                            .environment(\.locale, appState.resolvedLocale)
                            .appPresentationWidth(relativeTo: appState.appWindowWidth)
                            .appPresentationHeight(relativeTo: appState.appWindowHeight)
                    }
                    .sheet(isPresented: $showingAudioDecoderSelector) {
                        AudioDecoderSelector(selection: $audioDecoder)
                            .environment(\.locale, appState.resolvedLocale)
                            .appPresentationWidth(relativeTo: appState.appWindowWidth)
                            .appPresentationHeight(relativeTo: appState.appWindowHeight)
                    }
                    .sheet(isPresented: $showingAudioEncoderSelector) {
                        RemoteEncoderSelector(
                            selection: $audioEncoder,
                            connections: currentConnections,
                            kind: .audio
                        )
                        .environmentObject(appState)
                        .environment(\.locale, appState.resolvedLocale)
                        .appPresentationWidth(relativeTo: appState.appWindowWidth)
                        .appPresentationHeight(relativeTo: appState.appWindowHeight)
                    }
                }
            }
        }
        .background(AppTheme.background)
    }
}
