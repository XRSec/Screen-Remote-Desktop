import AppKit
import AudioToolbox
import SwiftUI
import VideoToolbox

private struct ConnectionDraft: Identifiable {
    let id: UUID
    var transport: DeviceTransport = .tcp
    var host = ""
    var port = "5555"
    var serial = ""

    init(
        id: UUID = UUID(), transport: DeviceTransport = .tcp, host: String = "",
        port: String = "5555", serial: String = ""
    ) {
        self.id = id
        self.transport = transport
        self.host = host
        self.port = port
        self.serial = serial
    }

    init(_ connection: DeviceConnection) {
        self.init(
            id: connection.id, transport: connection.transport, host: connection.host,
            port: String(connection.port), serial: connection.serial
        )
    }

    var isValid: Bool {
        switch transport {
        case .tcp:
            guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = Int(port), (1...65_535).contains(value) else { return false }
            return true
        case .usb:
            return !serial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .mdns:
            return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var displayAddress: String {
        switch transport {
        case .tcp:
            let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedHost.isEmpty ? String.localizedKey("deviceConnectionAddressNotConfigured") : "\(normalizedHost):\(port)"
        case .usb:
            let normalizedSerial = serial.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedSerial.isEmpty ? String.localizedKey("deviceConnectionSerialNotConfigured") : normalizedSerial
        case .mdns:
            let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedHost.isEmpty ? String.localizedKey("deviceConnectionServiceNotConfigured") : normalizedHost
        }
    }

    var transportSymbol: String {
        switch transport {
        case .tcp: return "network"
        case .usb: return "cable.connector"
        case .mdns: return "wifi"
        }
    }

    func connection(priority: Int) -> DeviceConnection {
        DeviceConnection(
            transport: transport,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? 0,
            serial: serial.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority
        )
    }
}

private struct ConnectionDiscoveryTarget: Identifiable {
    let id = UUID()
    let transport: DeviceTransport
    let backupID: UUID?

    static func primary(_ transport: DeviceTransport) -> ConnectionDiscoveryTarget {
        ConnectionDiscoveryTarget(transport: transport, backupID: nil)
    }

    static func backup(_ id: UUID, transport: DeviceTransport) -> ConnectionDiscoveryTarget {
        ConnectionDiscoveryTarget(transport: transport, backupID: id)
    }
}

struct AddDeviceView: View {
    private enum Layout {
        static let contentMaxWidth: CGFloat = 760
        static let sectionMinimumWidth: CGFloat = 300
        static let sectionSpacing: CGFloat = 18
    }

    private enum FormSection: Int, CaseIterable, Hashable {
        case remoteDevice
        case connectionOptions
        case video
        case audio
        case otherOptions
        case virtualDisplay
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    private let editingDevice: Device?

    @State private var name = ""
    @State private var transport: DeviceTransport = .tcp
    @State private var host = ""
    @State private var port = "5555"
    @State private var serial = ""
    @State private var backupConnections: [ConnectionDraft] = []
    @State private var accentIndex = 0
    @State private var groupIDs: Set<String> = []

    @State private var maxSize = ""
    @State private var videoBitrate = "4M"
    @State private var maxFPS = "60"
    @State private var videoEncoder = ""
    @State private var videoDecoder = ""
    @State private var enableAudio = false
    @State private var clipboardSync = true
    @State private var turnScreenOff = false
    @State private var powerOffOnClose = false
    @State private var cleanupOnDisconnect = true
    @State private var keepControllerAwake = false
    @State private var keepDeviceAwake = true
    @State private var ignoreVideoEncoderConstraints = false
    @State private var compatibilityMode = false
    @State private var gameMode = false
    @State private var showFloatingBall = true
    @State private var enableHardwareDecoding = true
    @State private var useADBForward = false
    @State private var audioBitrate = "128K"
    @State private var audioEncoder = ""
    @State private var audioDecoder = ""
    @State private var audioVolume = 1.0
    @State private var newDisplayEnabled = false
    @State private var virtualDisplaySystemDecorations = true
    @State private var preserveVirtualDisplayContent = false
    @State private var startApp = ""
    @State private var newDisplayWidth = ""
    @State private var newDisplayHeight = ""
    @State private var newDisplayDPI = ""
    @State private var showingGroupSelector = false
    @State private var showingAddressEditor = false
    @State private var showingLatencyTest = false
    @State private var showingVideoEncoderSelector = false
    @State private var showingVideoDecoderSelector = false
    @State private var showingAudioEncoderSelector = false
    @State private var showingAudioDecoderSelector = false
    @State private var connectionDiscoveryTarget: ConnectionDiscoveryTarget?

    private static let accentColors: [Color] = [.appIndigo, .blue, .appCyan, .green, .orange, .purple]
    private var accentColors: [Color] { Self.accentColors }

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
        _audioVolume = State(initialValue: options.audioVolume)
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
        _useADBForward = State(initialValue: options.useADBForward)
        _newDisplayEnabled = State(initialValue: options.newDisplayEnabled)
        _virtualDisplaySystemDecorations = State(initialValue: options.virtualDisplaySystemDecorations)
        _preserveVirtualDisplayContent = State(initialValue: options.preserveVirtualDisplayContent)
        _startApp = State(initialValue: options.startApp)
        _newDisplayWidth = State(initialValue: options.newDisplayWidth == 0 ? "" : String(options.newDisplayWidth))
        _newDisplayHeight = State(initialValue: options.newDisplayHeight == 0 ? "" : String(options.newDisplayHeight))
        _newDisplayDPI = State(initialValue: options.newDisplayDPI == 0 ? "" : String(options.newDisplayDPI))
    }

    private static func closestAccentIndex(to color: Color) -> Int {
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

    private var flowingContent: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: Layout.sectionMinimumWidth,
                        maximum: Layout.sectionMinimumWidth
                    ),
                    spacing: Layout.sectionSpacing,
                    alignment: .top
                )
            ],
            alignment: .center,
            spacing: Layout.sectionSpacing
        ) {
            ForEach(FormSection.allCases, id: \.self) { section in
                formSection(section)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func formSection(_ section: FormSection) -> some View {
        switch section {
        case .remoteDevice:
            remoteNavigationSection
        case .video:
            videoSection
        case .connectionOptions:
            connectionOptionsSection
        case .audio:
            audioSection
        case .virtualDisplay:
            virtualDisplaySection
        case .otherOptions:
            otherOptionsSection
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconTile(symbol: "plus.rectangle.on.rectangle", color: AppTheme.accent, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(editingDevice == nil ? "addDeviceTitle" : "sessionEditTitle").font(.title3.bold())
                Text(editingDevice == nil ? "addDeviceSubtitle" : "sessionEditSubtitle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
            Button("commonCancel") { presentationMode.wrappedValue.dismiss() }
            Button("commonSave") { saveDevice() }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
        .padding(.horizontal, 24)
        .frame(height: 72)
    }

    private var primaryConnectionSection: some View {
        DeviceFormSection(title: "addDeviceConnectionSection", subtitle: "addDeviceConnectionSectionHint") {
            VStack(alignment: .leading, spacing: 9) {
                FormLabel(title: "addDeviceConnectionType", help: "sessionHelpConnectionType")
                Picker("addDeviceConnectionType", selection: $transport) {
                    ForEach(DeviceTransport.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .padding(14)

            FormDivider()
            connectionFields
        }
    }

    private var remoteNavigationSection: some View {
        DeviceFormSection(title: "sessionRemoteDeviceSection") {
            FormTextRow(title: "addDeviceSessionName", placeholder: "addDeviceSessionNamePlaceholder", text: $name, help: "sessionHelpName")
            FormDivider()
            FormNavigationRow(
                title: "sessionAddressTitle",
                value: currentConnections.count > 1
                    ? String(format: String.localizedKey("sessionAddressCount"), currentConnections.count)
                    : (currentConnections.first?.displayAddress ?? ""),
                help: "sessionHelpAddresses"
            ) { showingAddressEditor = true }
            FormDivider()
            FormNavigationRow(
                title: "addDeviceGroup",
                value: groupSelectionSummary,
                help: "sessionHelpGroup"
            ) { showingGroupSelector = true }
            FormDivider()
            FormNavigationRow(
                title: "sessionLatencyTest",
                value: "10 × 10",
                help: "sessionHelpLatency"
            ) { showingLatencyTest = true }
            FormDivider()
            HStack {
                FormLabel(title: "addDeviceLabelColor", help: "sessionHelpLabelColor")
                Spacer()
                AccentPickerControl(colors: accentColors, selection: $accentIndex)
            }
            .padding(14)
        }
    }

    private var groupSelectionSummary: String {
        let selectedNames = appState.flattenedGroups()
            .filter { groupIDs.contains($0.id) }
            .map(\.group.name)
        switch selectedNames.count {
        case 0:
            return String.localizedKey("sidebarAllDevices")
        case 1:
            return selectedNames[0]
        default:
            return String(
                format: String.localizedKey("sessionSelectedGroupCount"),
                selectedNames.count
            )
        }
    }

    private var connectionOptionsSection: some View {
        DeviceFormSection(title: "sessionConnectionOptionsSection") {
            FormToggleRow(title: "sessionCompatibilityMode", isOn: $compatibilityMode, help: "sessionHelpCompatibility")
                .onChange(of: compatibilityMode) { enabled in
                    if enabled {
                        enableAudio = false
                        gameMode = false
                        enableHardwareDecoding = false
                        useADBForward = false
                        clipboardSync = false
                        turnScreenOff = false
                        powerOffOnClose = false
                        keepDeviceAwake = false
                        ignoreVideoEncoderConstraints = false
                        newDisplayEnabled = false
                    }
                }
            FormDivider()
            FormToggleRow(title: "sessionGameMode", isOn: $gameMode, help: "sessionHelpGameMode", enabled: !compatibilityMode)
                .onChange(of: gameMode) { enabled in
                    if enabled { applyGameModePresets() }
                }
            FormDivider()
            FormToggleRow(title: "sessionFloatingBall", isOn: $showFloatingBall, help: "sessionHelpFloatingBall")
            FormDivider()
            FormToggleRow(title: "sessionHardwareDecoding", isOn: $enableHardwareDecoding, help: "sessionHelpHardwareDecoding", enabled: !compatibilityMode)
            FormDivider()
            FormToggleRow(title: "sessionADBForward", isOn: $useADBForward, help: "sessionHelpADBForward", enabled: !compatibilityMode)
        }
    }

    private var backupConnectionsSection: some View {
        DeviceFormSection(title: "addDeviceBackupSection", subtitle: "addDeviceBackupSectionHint") {
            if backupConnections.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .appBackground(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                    Text("addDeviceNoBackupAddress")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        appendBackupConnection()
                    } label: {
                        Label("addDeviceAddAddress", systemImage: "plus")
                    }
                }
                .padding(14)
            } else {
                ForEach(backupConnections.indices, id: \.self) { index in
                    let endpoint = backupConnections[index]
                    BackupConnectionEditor(
                        endpoint: $backupConnections[index],
                        onRemove: {
                            backupConnections.removeAll { $0.id == endpoint.id }
                        },
                        onDiscover: {
                            connectionDiscoveryTarget = .backup(endpoint.id, transport: backupConnections[index].transport)
                        }
                    )

                    if endpoint.id != backupConnections.last?.id {
                        FormDivider()
                    }
                }

                FormDivider()
                HStack {
                    Spacer()
                    Button {
                        appendBackupConnection()
                    } label: {
                        Label("addDeviceAddAnotherAddress", systemImage: "plus")
                    }
                }
                .padding(14)
            }
        }
    }

    private var videoSection: some View {
        DeviceFormSection(title: "addDeviceVideoSection", subtitle: "addDeviceVideoSectionHint") {
            PresetCustomRow(
                title: "addDeviceMaxResolution",
                value: $maxSize,
                presets: gameMode
                    ? [PresetValue("720", "720"), PresetValue("1080", "1080"), PresetValue("1920", "1920")]
                    : [
                        PresetValue("720", "720"),
                        PresetValue("1080", "1080"),
                        PresetValue("1920", "1920"),
                        PresetValue(String.localizedKey("addDeviceOriginalSize"), "")
                    ],
                customEnabled: !gameMode,
                fallback: gameMode ? "720" : "",
                help: "sessionHelpMaxSize"
            )
            FormDivider()
            PresetCustomRow(
                title: "addDeviceVideoBitrate",
                value: $videoBitrate,
                presets: (gameMode
                    ? ["1M", "2M", "4M", "8M", "12M", "20M"]
                    : ["700K", "1M", "2M", "4M", "8M", "12M", "20M", "40M", "80M", "120M"])
                    .map { PresetValue($0, $0) },
                customEnabled: !gameMode,
                units: ["K", "M"],
                defaultUnit: "M",
                fallback: gameMode ? "2M" : "4M",
                help: "sessionHelpVideoBitrate"
            )
            FormDivider()
            PresetCustomRow(
                title: "addDeviceMaxFrameRate",
                value: $maxFPS,
                presets: (gameMode ? ["60", "90", "120"] : ["15", "30", "60", "90", "120"])
                    .map { PresetValue("\($0) FPS", $0) },
                customEnabled: !gameMode,
                fallback: "60",
                help: "sessionHelpMaxFPS"
            )
            FormDivider()
            FormNavigationRow(
                title: "sessionVideoEncoder",
                value: videoEncoder.isEmpty ? String.localizedKey("sessionDefault") : videoEncoder,
                help: "sessionHelpVideoEncoder"
            ) { showingVideoEncoderSelector = true }
            FormDivider()
            FormNavigationRow(
                title: "sessionVideoDecoder",
                value: videoDecoder.isEmpty ? String.localizedKey("sessionDefault") : videoDecoder,
                help: "sessionHelpVideoDecoder"
            ) { showingVideoDecoderSelector = true }
        }
    }

    private var audioSection: some View {
        DeviceFormSection(title: "sessionAudioSection", subtitle: "sessionAudioSectionHint") {
            FormToggleRow(title: "addDeviceForwardAudio", isOn: $enableAudio, help: "sessionHelpAudio", enabled: !compatibilityMode)
            if enableAudio {
                FormDivider()
                PresetCustomRow(
                    title: "sessionAudioBitrate",
                    value: $audioBitrate,
                    presets: (gameMode ? ["64K", "128K"] : ["64K", "128K", "192K", "256K"])
                        .map { PresetValue($0, $0) },
                    customEnabled: true,
                    units: ["K", "M"],
                    defaultUnit: "K",
                    fallback: "128K",
                    help: "sessionHelpAudioBitrate"
                )
                FormDivider()
                FormNavigationRow(
                    title: "sessionAudioEncoder",
                    value: audioEncoder.isEmpty ? String.localizedKey("sessionDefault") : audioEncoder,
                    help: "sessionHelpAudioEncoder"
                ) { showingAudioEncoderSelector = true }
                FormDivider()
                FormNavigationRow(
                    title: "sessionAudioDecoder",
                    value: audioDecoder.isEmpty ? String.localizedKey("sessionDefault") : audioDecoder,
                    help: "sessionHelpAudioDecoder"
                ) { showingAudioDecoderSelector = true }
                FormDivider()
                FormSliderRow(title: "sessionAudioVolume", value: $audioVolume, help: "sessionHelpAudioVolume")
            }
        }
    }

    private var otherOptionsSection: some View {
        DeviceFormSection(title: "sessionOtherOptionsSection", subtitle: "sessionOtherOptionsHint") {
            FormToggleRow(title: "addDeviceSyncClipboard", isOn: $clipboardSync, help: "sessionHelpClipboard", enabled: !compatibilityMode)
            FormDivider()
            FormToggleRow(title: "addDeviceTurnScreenOff", isOn: $turnScreenOff, help: "sessionHelpTurnScreenOff", enabled: !compatibilityMode)
            FormDivider()
            FormToggleRow(title: "sessionCleanupOnDisconnect", isOn: $cleanupOnDisconnect, help: "sessionHelpCleanup")
                .onChange(of: cleanupOnDisconnect) { enabled in
                    if !enabled {
                        powerOffOnClose = false
                        keepDeviceAwake = false
                    }
                }
            FormDivider()
            FormToggleRow(
                title: "sessionPowerOffOnClose", isOn: $powerOffOnClose,
                help: "sessionHelpPowerOffOnClose", enabled: cleanupOnDisconnect && !compatibilityMode
            )
            FormDivider()
            FormToggleRow(title: "sessionKeepControllerAwake", isOn: $keepControllerAwake, help: "sessionHelpKeepControllerAwake")
            FormDivider()
            FormToggleRow(
                title: "addDeviceKeepAwake", isOn: $keepDeviceAwake,
                help: "sessionHelpKeepAwake", enabled: cleanupOnDisconnect && !compatibilityMode
            )
            FormDivider()
            FormToggleRow(
                title: "sessionIgnoreEncoderConstraints", isOn: $ignoreVideoEncoderConstraints,
                help: "sessionHelpIgnoreEncoderConstraints", enabled: !compatibilityMode
            )
        }
    }

    private var virtualDisplaySection: some View {
        DeviceFormSection(title: "sessionVirtualDisplaySection") {
            FormToggleRow(title: "sessionNewDisplay", isOn: $newDisplayEnabled, help: "sessionHelpNewDisplay", enabled: !compatibilityMode)
            if newDisplayEnabled {
                FormDivider()
                FormToggleRow(title: "sessionDisplaySystemUI", isOn: $virtualDisplaySystemDecorations, help: "sessionHelpDisplaySystemUI")
                FormDivider()
                FormToggleRow(title: "sessionPreserveDisplay", isOn: $preserveVirtualDisplayContent, help: "sessionHelpPreserveDisplay")
                FormDivider()
                FormTextRow(title: "sessionStartApp", placeholder: "com.example.app", text: $startApp, help: "sessionHelpStartApp")
                FormDivider()
                DisplaySizeRow(width: $newDisplayWidth, height: $newDisplayHeight, dpi: $newDisplayDPI)
            }
        }
    }

    private var saveHint: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill").foregroundColor(AppTheme.accent)
            Text("addDeviceSaveHint")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .appBackground(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var connectionFields: some View {
        switch transport {
        case .tcp:
            HStack(alignment: .top, spacing: 12) {
                FormField(title: "addDeviceIPAddress", placeholder: "192.168.1.100", text: $host, help: "sessionHelpHost")
                    .frame(maxWidth: .infinity)
                FormField(title: "addDevicePort", placeholder: "5555", text: $port, help: "sessionHelpPort")
                    .frame(width: 120)
            }
            .padding(14)
            FormDivider()
            ConnectionDiscoveryRow(transport: .tcp) {
                connectionDiscoveryTarget = .primary(.tcp)
            }
            .padding(14)
        case .usb:
            FormTextRow(title: "addDeviceUSBSerial", placeholder: "10AEAG2YZS0020P", text: $serial, help: "sessionHelpUSB")
            FormDivider()
            ConnectionDiscoveryRow(transport: .usb) {
                connectionDiscoveryTarget = .primary(.usb)
            }
            .padding(14)
        case .mdns:
            FormTextRow(title: "addDeviceMDNSServiceOrSerial", placeholder: "R5CW730QLKB", text: $host, help: "sessionHelpMDNS")
            FormDivider()
            ConnectionDiscoveryRow(transport: .mdns) {
                connectionDiscoveryTarget = .primary(.mdns)
            }
            .padding(14)
        }
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let primaryValid: Bool
        switch transport {
        case .tcp:
            primaryValid = !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && portNumber != nil
        case .usb:
            primaryValid = !serial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .mdns:
            primaryValid = !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return primaryValid && backupConnections.allSatisfy(\.isValid)
    }

    private func appendBackupConnection() {
        backupConnections.append(ConnectionDraft())
    }

    private func discoveryCurrentAddress(for target: ConnectionDiscoveryTarget) -> String {
        if let backupID = target.backupID,
           let connection = backupConnections.first(where: { $0.id == backupID }) {
            return connection.displayAddress
        }
        switch target.transport {
        case .tcp: return host.isEmpty ? "" : "\(host):\(port)"
        case .usb: return serial
        case .mdns: return host
        }
    }

    private func applyDiscoveredDevice(
        _ device: DiscoveredADBDevice,
        to target: ConnectionDiscoveryTarget
    ) {
        if let backupID = target.backupID,
           let index = backupConnections.firstIndex(where: { $0.id == backupID }) {
            backupConnections[index].transport = target.transport
            apply(device, to: &backupConnections[index])
        } else {
            transport = target.transport
            switch target.transport {
            case .tcp:
                let endpoint = splitHostPort(device.address)
                host = endpoint.host
                port = String(endpoint.port ?? 5555)
            case .usb:
                serial = device.address
            case .mdns:
                host = device.address
                port = "0"
            }
        }
        connectionDiscoveryTarget = nil
    }

    private func apply(_ device: DiscoveredADBDevice, to draft: inout ConnectionDraft) {
        switch draft.transport {
        case .tcp:
            let endpoint = splitHostPort(device.address)
            draft.host = endpoint.host
            draft.port = String(endpoint.port ?? 5555)
        case .usb:
            draft.serial = device.address
        case .mdns:
            draft.host = device.address
            draft.port = "0"
        }
    }

    private var portNumber: Int? {
        guard let value = Int(port), (1...65_535).contains(value) else { return nil }
        return value
    }

    private func applyGameModePresets() {
        maxSize = closestPreset(maxSize, values: [720, 1080, 1920], fallback: 720)
        videoBitrate = closestBitratePreset(videoBitrate, values: [1, 2, 4, 8, 12, 20], fallback: 2)
        maxFPS = closestPreset(maxFPS, values: [60, 90, 120], fallback: 60)
    }

    private var currentConnections: [DeviceConnection] {
        let primary = DeviceConnection(
            transport: transport, host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portNumber ?? 0, serial: serial.trimmingCharacters(in: .whitespacesAndNewlines), priority: 0
        )
        return [primary] + backupConnections.enumerated().map { $0.element.connection(priority: $0.offset + 1) }
    }

    private func saveDevice() {
        guard isValid else { return }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSerial = serial.trimmingCharacters(in: .whitespacesAndNewlines)

        let primaryConnection = DeviceConnection(
            transport: transport,
            host: normalizedHost,
            port: portNumber ?? 0,
            serial: normalizedSerial,
            priority: 0
        )
        let connections = [primaryConnection] + backupConnections.enumerated().map { index, draft in
            draft.connection(priority: index + 1)
        }

        let device = Device(
                id: editingDevice?.id ?? UUID(),
                name: normalizedName,
                model: editingDevice?.model ?? String.localizedKey("addDeviceDefaultModel"),
                systemVersion: editingDevice?.systemVersion ?? String.localizedKey("addDeviceWaitingToConnect"),
                battery: editingDevice?.battery ?? 0,
                accent: accentColors[accentIndex],
                isConnected: editingDevice?.isConnected ?? false,
                groupIDs: groupIDs,
                connections: connections,
                scrcpyOptions: ScrcpyDeviceOptions(
                    maxSize: Int(maxSize).flatMap { $0 > 0 ? $0 : nil } ?? 0,
                    videoBitrate: videoBitrate.isEmpty ? "4M" : videoBitrate,
                    maxFPS: Int(maxFPS).flatMap { $0 > 0 ? $0 : nil } ?? 60,
                    videoEncoder: videoEncoder,
                    videoDecoder: videoDecoder,
                    enableAudio: enableAudio,
                    audioBitrate: audioBitrate.isEmpty ? "128K" : audioBitrate,
                    audioEncoder: audioEncoder,
                    audioDecoder: audioDecoder,
                    audioVolume: audioVolume,
                    clipboardSync: clipboardSync,
                    turnScreenOff: turnScreenOff,
                    powerOffOnClose: powerOffOnClose,
                    cleanupOnDisconnect: cleanupOnDisconnect,
                    keepControllerAwake: keepControllerAwake,
                    keepDeviceAwake: keepDeviceAwake,
                    ignoreVideoEncoderConstraints: ignoreVideoEncoderConstraints,
                    compatibilityMode: compatibilityMode,
                    gameMode: gameMode,
                    showFloatingBall: showFloatingBall,
                    enableHardwareDecoding: enableHardwareDecoding,
                    useADBForward: useADBForward,
                    newDisplayEnabled: newDisplayEnabled,
                    virtualDisplaySystemDecorations: virtualDisplaySystemDecorations,
                    preserveVirtualDisplayContent: preserveVirtualDisplayContent,
                    startApp: startApp,
                    newDisplayWidth: Int(newDisplayWidth) ?? 0,
                    newDisplayHeight: Int(newDisplayHeight) ?? 0,
                    newDisplayDPI: Int(newDisplayDPI) ?? 0
                )
            )
        if editingDevice == nil { appState.addDevice(device) } else { appState.updateDevice(device) }
        presentationMode.wrappedValue.dismiss()
    }
}

private struct BackupConnectionEditor: View {
    @Binding var endpoint: ConnectionDraft
    let onRemove: () -> Void
    let onDiscover: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("addDeviceConnectionType", selection: $endpoint.transport) {
                    ForEach(DeviceTransport.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("addDeviceRemoveAddress")
            }

            switch endpoint.transport {
            case .tcp:
                HStack(spacing: 8) {
                    TextField("addDeviceIPAddress", text: $endpoint.host).textFieldStyle(.roundedBorder)
                    TextField("addDevicePort", text: $endpoint.port).textFieldStyle(.roundedBorder).frame(width: 100)
                }
            case .usb:
                TextField("addDeviceUSBSerial", text: $endpoint.serial).textFieldStyle(.roundedBorder)
            case .mdns:
                TextField("addDeviceMDNSServiceOrSerial", text: $endpoint.host).textFieldStyle(.roundedBorder)
            }

            ConnectionDiscoveryRow(transport: endpoint.transport, action: onDiscover)
        }
        .padding(14)
        .background(Color.primary.opacity(0.025))
    }
}

private struct ConnectionDiscoveryRow: View {
    let transport: DeviceTransport
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: transport == .usb ? "cable.connector" : "dot.radiowaves.left.and.right")
                    .foregroundColor(AppTheme.accent)
                Text(String.localizedKey(transport == .usb ? "sessionSelectUSBDevice" : "sessionDiscoverDevices"))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ConnectionDiscoveryPicker: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    let transport: DeviceTransport
    let currentAddress: String
    let onSelect: (DiscoveredADBDevice) -> Void

    @State private var devices: [DiscoveredADBDevice] = []
    @State private var isRefreshing = false
    @State private var statusText = String.localizedKey("deviceDiscoveryWaiting")
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String.localizedKey(transport == .usb ? "sessionSelectUSBDevice" : "sessionDiscoverDevices"))
                        .font(.headline)
                    Text(String(format: String.localizedKey("sessionDiscoveryPickerSubtitle %@"), transport.rawValue))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { refresh() } label: {
                    Label(isRefreshing ? "deviceDiscoveryRefreshing" : "commonRefresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                Button("commonClose") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: String.localizedKey("deviceDiscoveryDeviceCount"), "\(devices.count)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if devices.isEmpty && !isRefreshing {
                            ContentUnavailableViewCompat(
                                icon: transport == .usb ? "cable.connector" : "dot.radiowaves.left.and.right",
                                title: "deviceDiscoveryEmptyTitle",
                                detail: "deviceDiscoveryEmptyDetail"
                            )
                            .frame(height: 230)
                        }

                        ForEach(devices) { device in
                            Button {
                                onSelect(device)
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    AppIconTile(
                                        symbol: transport == .usb ? "cable.connector" : "wifi",
                                        color: transport == .mdns ? .appCyan : .blue,
                                        size: 34
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.primary)
                                        Text(device.address)
                                            .font(.appCaptionMonospaced)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(device.state)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if device.address.caseInsensitiveCompare(currentAddress) == .orderedSame {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppTheme.accent)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .appCard(radius: 10)
                        }
                    }
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .onAppear { refresh() }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorText = nil
        statusText = String.localizedKey("deviceDiscoveryReadingDevices")
        let adbPath = appState.adbPath

        Task {
            let deviceResult = await ADBCommandRunner.run(
                executable: adbPath,
                arguments: ["devices", "-l"]
            )
            await MainActor.run {
                statusText = String.localizedKey("deviceDiscoveryReadingMDNS")
            }
            let mdnsResult = await ADBCommandRunner.run(
                executable: adbPath,
                arguments: ["mdns", "services"]
            )
            let discovered = (parseADBDevices(deviceResult.output) + parseMDNSServices(mdnsResult.output))
                .filter { $0.transport == transport }
            var seen = Set<String>()
            let unique = discovered.filter {
                seen.insert($0.address.lowercased()).inserted
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            await MainActor.run {
                devices = unique
                isRefreshing = false
                statusText = String.localizedKey("deviceDiscoveryComplete")
                let errors = [deviceResult, mdnsResult]
                    .filter { $0.exitCode != 0 }
                    .map { $0.error.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                errorText = errors.isEmpty ? nil : errors.joined(separator: " · ")
                appState.appendSDLLog(
                    "Session address discovery complete: transport=\(transport.rawValue), devices=\(unique.count)"
                )
            }
        }
    }
}

private struct DeviceFormSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String.localizedKey(title)).font(.system(size: 13, weight: .semibold))
                if let subtitle = subtitle {
                    Text(String.localizedKey(subtitle)).font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.leading, 3)
            VStack(spacing: 0) { content }
                .appCard(radius: 12)
        }
    }
}

private struct FormDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

private struct FormTextRow: View {
    let title: LocalizedStringKey
    let placeholder: String
    @Binding var text: String
    var help: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            FormLabel(title: title, help: help)
            Spacer()
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 430)
        }
        .padding(14)
    }
}

private struct FormField: View {
    let title: LocalizedStringKey
    let placeholder: String
    @Binding var text: String
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormLabel(title: title, help: help)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

private struct FormPickerRow<Content: View, Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    @ViewBuilder let content: Content
    let help: String?

    init(
        title: LocalizedStringKey, selection: Binding<Selection>, help: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.help = help
        self.content = content()
    }

    var body: some View {
        HStack {
            FormLabel(title: title, help: help)
            Spacer()
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .frame(width: 150)
        }
        .padding(14)
    }
}

private struct PresetValue: Hashable {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

private struct PresetCustomRow: View {
    private static let customToken = "__custom__"

    let title: LocalizedStringKey
    @Binding var value: String
    let presets: [PresetValue]
    let customEnabled: Bool
    let units: [String]
    let fallback: String
    let help: String

    @State private var editingCustom: Bool
    @State private var customDigits: String
    @State private var customUnit: String

    init(
        title: LocalizedStringKey,
        value: Binding<String>,
        presets: [PresetValue],
        customEnabled: Bool,
        units: [String] = [],
        defaultUnit: String = "",
        fallback: String,
        help: String
    ) {
        self.title = title
        self._value = value
        self.presets = presets
        self.customEnabled = customEnabled
        self.units = units
        self.fallback = fallback
        self.help = help

        let current = value.wrappedValue
        let matchesPreset = presets.contains { $0.value.caseInsensitiveCompare(current) == .orderedSame }
        let selectedUnit = units.first { current.lowercased().hasSuffix($0.lowercased()) } ?? defaultUnit
        _editingCustom = State(initialValue: customEnabled && !current.isEmpty && !matchesPreset)
        _customDigits = State(initialValue: current.filter { $0.isNumber })
        _customUnit = State(initialValue: selectedUnit)
    }

    var body: some View {
        HStack(spacing: 12) {
            FormLabel(title: title, help: help)
            Spacer()
            if editingCustom && customEnabled {
                HStack(spacing: 5) {
                    TextField("sessionCustomValue", text: $customDigits)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: units.isEmpty ? 105 : 78)
                        .onChange(of: customDigits) { next in
                            customDigits = next.filter { $0.isNumber }
                            updateCustomValue()
                        }
                    if !units.isEmpty {
                        Picker("", selection: $customUnit) {
                            ForEach(units, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 54)
                        .onChange(of: customUnit) { _ in updateCustomValue() }
                    }
                    Button {
                        editingCustom = false
                        customDigits = ""
                        value = fallback
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.plain)
                    .help("sessionBackToPresets")
                }
            } else {
                Picker(title, selection: pickerSelection) {
                    ForEach(presets, id: \.self) { preset in
                        Text(preset.label).tag(preset.value)
                    }
                    if customEnabled {
                        Text("sessionCustom").tag(Self.customToken)
                    }
                }
                .labelsHidden()
                .frame(width: 165)
            }
        }
        .padding(14)
        .onAppear {
            if !editingCustom && value.isEmpty && !presets.contains(where: { $0.value.isEmpty }) {
                value = fallback
            }
        }
        .onDisappear {
            if value.isEmpty { value = fallback }
        }
    }

    private var pickerSelection: Binding<String> {
        Binding(
            get: {
                presets.contains(where: { $0.value.caseInsensitiveCompare(value) == .orderedSame })
                    ? value
                    : (presets.first?.value ?? fallback)
            },
            set: { next in
                if next == Self.customToken {
                    editingCustom = true
                    customDigits = ""
                    value = ""
                } else {
                    editingCustom = false
                    value = next
                }
            }
        )
    }

    private func updateCustomValue() {
        value = customDigits.isEmpty ? "" : customDigits + customUnit
    }
}

private struct FormToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    var help: String? = nil
    var enabled = true

    var body: some View {
        HStack {
            FormLabel(title: title, help: help)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().disabled(!enabled)
        }
            .toggleStyle(.switch)
            .padding(14)
    }
}

private struct FormLabel: View {
    let title: LocalizedStringKey
    let help: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(.system(size: 13, weight: .medium))
            if let help {
                HelpPopoverButton(textKey: help)
            }
        }
    }
}

private struct HelpPopoverButton: View {
    let textKey: String
    @State private var presented = false

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("sessionHelpButton")
        .popover(isPresented: $presented, arrowEdge: .trailing) {
            Text(String.localizedKey(textKey))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(14)
        }
    }
}

private struct FormNavigationRow: View {
    let title: LocalizedStringKey
    let value: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FormLabel(title: title, help: help)
                Spacer()
                Text(value).foregroundColor(.secondary).lineLimit(1)
                Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FormSliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let help: String

    var body: some View {
        HStack(spacing: 10) {
            FormLabel(title: title, help: help)
            Slider(value: $value, in: 0.1...2, step: 0.1)
            Text(String(format: "%.1f×", value))
                .font(.caption.monospacedDigit())
                .frame(width: 34)
        }
        .padding(14)
    }
}

private struct DisplaySizeRow: View {
    @Binding var width: String
    @Binding var height: String
    @Binding var dpi: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormLabel(title: "sessionDisplaySize", help: "sessionHelpDisplaySize")
            HStack(spacing: 5) {
                metricField("sessionWidth", text: $width)
                Text("×").foregroundColor(.secondary)
                metricField("sessionHeight", text: $height)
                Text("@").foregroundColor(.secondary)
                metricField("DPI", text: $dpi)
            }
        }
        .padding(14)
    }

    private func metricField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text.wrappedValue) { text.wrappedValue = $0.filter { $0.isNumber } }
    }
}

private struct SessionGroupSelector: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    @Binding var selection: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("sessionSelectGroup").font(.headline)
                Spacer()
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            List {
                Button {
                    selection.removeAll()
                } label: {
                    HStack {
                        Image(systemName: "house.fill").foregroundColor(AppTheme.accent).frame(width: 22)
                        Text("sidebarAllDevices")
                        Spacer()
                        if selection.isEmpty {
                            Image(systemName: "checkmark").foregroundColor(AppTheme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5)

                OutlineGroup(appState.groupTree(), children: \.children) { node in
                    groupRow(group: node.group)
                }
            }
        }
    }

    private func groupRow(group: DeviceGroup) -> some View {
        Button {
            if selection.contains(group.id) {
                selection.remove(group.id)
            } else {
                selection.insert(group.id)
            }
        } label: {
            HStack {
                Image(systemName: group.symbol).foregroundColor(AppTheme.accent).frame(width: 22)
                Text(group.name)
                Spacer()
                if selection.contains(group.id) {
                    Image(systemName: "checkmark").foregroundColor(AppTheme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
    }
}

private enum RemoteEncoderKind: Sendable {
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

    var argumentName: String {
        self == .video ? "video-encoder" : "audio-encoder"
    }
}

private struct RemoteEncoderSelector: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    @Binding var selection: String
    let connections: [DeviceConnection]
    let kind: RemoteEncoderKind

    @State private var detectedEncoders: [String] = []
    @State private var isDetecting = false
    @State private var detectionMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            selectorHeader(
                title: kind.title,
                isRefreshing: isDetecting,
                onRefresh: detectEncoders
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    codecSectionTitle("sessionEncoderOptions")
                    VStack(spacing: 0) {
                        codecChoiceRow(
                            title: String.localizedKey("sessionDefault"),
                            detail: String.localizedKey("sessionDefaultEncoderDetail"),
                            selected: selection.isEmpty
                        ) { selection = "" }
                        FormDivider()
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("sessionCustomEncoder").font(.system(size: 13, weight: .medium))
                                Text("sessionCustomEncoderHint").font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            TextField("sessionCustomEncoderPlaceholder", text: $selection)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                        }
                        .padding(13)
                    }
                    .appCard(radius: 10)

                    codecSectionTitle(kind.detectedTitle)
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
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(detectedEncoders.enumerated()), id: \.element) { index, encoder in
                                codecChoiceRow(
                                    title: encoder,
                                    detail: encoderHardwareHint(encoder),
                                    selected: selection == encoder
                                ) { selection = encoder }
                                if index < detectedEncoders.count - 1 { FormDivider() }
                            }
                        }
                        .appCard(radius: 10)
                    }
                }
                .padding(18)
            }
        }
        .onAppear { detectEncoders() }
    }

    private func selectorHeader(
        title: LocalizedStringKey,
        isRefreshing: Bool,
        onRefresh: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button("sessionRefreshEncoders", action: onRefresh).disabled(isRefreshing)
            Button("commonDone") { presentationMode.wrappedValue.dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func detectEncoders() {
        guard !isDetecting else { return }
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
            } catch {
                detectedEncoders = []
                detectionMessage = error.localizedDescription
            }
            isDetecting = false
        }
    }

    private func encoderHardwareHint(_ name: String) -> String {
        let lowercased = name.lowercased()
        if lowercased.contains("google") || lowercased.contains("android") || lowercased.contains("software") {
            return String.localizedKey("sessionSoftwareEncoder")
        }
        return String.localizedKey("sessionHardwareEncoder")
    }
}

private struct VideoDecoderSelector: View {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selection: String

    private var decoders: [(id: String, title: String, detail: String)] {
        var values = [(
            id: "",
            title: String.localizedKey("sessionDefault"),
            detail: String.localizedKey("sessionDefaultDecoderDetail")
        )]
        let formats: [(id: String, name: String, type: CMVideoCodecType)] = [
            ("videotoolbox.h264", "VideoToolbox · H.264", kCMVideoCodecType_H264),
            ("videotoolbox.hevc", "VideoToolbox · HEVC", kCMVideoCodecType_HEVC),
            ("videotoolbox.av1", "VideoToolbox · AV1", kCMVideoCodecType_AV1),
            ("videotoolbox.vp9", "VideoToolbox · VP9", kCMVideoCodecType_VP9),
            ("videotoolbox.vp8", "VideoToolbox · VP8", CMVideoCodecType(0x7670_3038))
        ]
        values.append(contentsOf: formats.map { format in
            (
                id: format.id,
                title: format.name,
                detail: VTIsHardwareDecodeSupported(format.type)
                    ? String.localizedKey("sessionHardwareDecoderAvailable")
                    : String.localizedKey("sessionSystemDecoderRoute")
            )
        })
        return values
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("sessionSelectVideoDecoder").font(.headline)
                Spacer()
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("sessionLocalVideoDecoders")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(decoders.enumerated()), id: \.element.id) { index, decoder in
                            codecChoiceRow(
                                title: decoder.title,
                                detail: decoder.detail,
                                selected: selection == decoder.id
                            ) { selection = decoder.id }
                            if index < decoders.count - 1 { FormDivider() }
                        }
                    }
                    .appCard(radius: 10)

                    Text("sessionVideoDecoderRecommendation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(13)
                        .appBackground(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(18)
            }
        }
    }
}

private struct AudioDecoderOption: Identifiable {
    let id: String
    let title: String
    let detail: String
}

private struct AudioDecoderSelector: View {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selection: String

    private var decoders: [AudioDecoderOption] {
        [AudioDecoderOption(
            id: "",
            title: String.localizedKey("sessionDefault"),
            detail: String.localizedKey("sessionDefaultAudioDecoderDetail")
        )] + coreAudioDecoderOptions()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("sessionSelectAudioDecoder").font(.headline)
                Spacer()
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("sessionLocalAudioDecoders")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(decoders.enumerated()), id: \.element.id) { index, decoder in
                            codecChoiceRow(
                                title: decoder.title,
                                detail: decoder.detail,
                                selected: selection == decoder.id
                            ) { selection = decoder.id }
                            if index < decoders.count - 1 { FormDivider() }
                        }
                    }
                    .appCard(radius: 10)

                    Text("sessionAudioDecoderEnumerationNote")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(13)
                        .appBackground(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(18)
            }
        }
    }
}

private func coreAudioDecoderOptions() -> [AudioDecoderOption] {
    let formats: [(name: String, id: AudioFormatID)] = [
        ("Opus", kAudioFormatOpus),
        ("AAC", kAudioFormatMPEG4AAC),
        ("FLAC", kAudioFormatFLAC),
        ("PCM", kAudioFormatLinearPCM)
    ]

    return formats.flatMap { format -> [AudioDecoderOption] in
        var formatID = format.id
        var byteCount: UInt32 = 0
        let infoStatus = withUnsafePointer(to: &formatID) { pointer in
            AudioFormatGetPropertyInfo(
                kAudioFormatProperty_Decoders,
                UInt32(MemoryLayout<AudioFormatID>.size),
                pointer,
                &byteCount
            )
        }

        if infoStatus != noErr || byteCount == 0 {
            if format.id == kAudioFormatLinearPCM {
                return [AudioDecoderOption(
                    id: "coreaudio.pcm",
                    title: "Core Audio · PCM",
                    detail: String.localizedKey("sessionNativeAudioFormat")
                )]
            }
            return []
        }

        let count = Int(byteCount) / MemoryLayout<AudioClassDescription>.size
        var descriptions = [AudioClassDescription](
            repeating: AudioClassDescription(),
            count: count
        )
        let getStatus = withUnsafePointer(to: &formatID) { formatPointer in
            descriptions.withUnsafeMutableBytes { buffer in
                AudioFormatGetProperty(
                    kAudioFormatProperty_Decoders,
                    UInt32(MemoryLayout<AudioFormatID>.size),
                    formatPointer,
                    &byteCount,
                    buffer.baseAddress
                )
            }
        }
        guard getStatus == noErr else { return [] }

        return descriptions.enumerated().map { index, description in
            let component = [
                fourCharacterCode(description.mSubType),
                fourCharacterCode(description.mManufacturer)
            ].joined(separator: " · ")
            return AudioDecoderOption(
                id: "coreaudio.\(format.name.lowercased()).\(index)",
                title: "Core Audio · \(format.name)",
                detail: String(
                    format: String.localizedKey("sessionAudioDecoderComponent"),
                    component
                )
            )
        }
    }
}

private func fourCharacterCode(_ value: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff)
    ]
    let text = String(bytes: bytes, encoding: .macOSRoman) ?? ""
    return text.allSatisfy { $0.isASCII && !$0.isWhitespace } ? text : String(format: "0x%08X", value)
}

private func codecSectionTitle(_ key: LocalizedStringKey) -> some View {
    Text(key)
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
}

private func codecChoiceRow(
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
                Image(systemName: "checkmark.circle.fill").foregroundColor(AppTheme.accent)
            }
        }
        .padding(13)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

private func closestPreset(_ value: String, values: [Int], fallback: Int) -> String {
    guard let parsed = Int(value), let closest = values.min(by: {
        abs($0 - parsed) < abs($1 - parsed)
    }) else {
        return String(fallback)
    }
    return String(closest)
}

private func closestBitratePreset(_ value: String, values: [Int], fallback: Int) -> String {
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

private struct RemoteEncoderDetectionResult {
    let encoders: [String]
    let message: String
}

private func detectRemoteEncoders(
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
        let patterns = [#"\#(kind.argumentName)=\s*['"]?([^'"\s]+)"#]
        var matches: [String] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in expression.matches(in: text, range: range) {
                let capture = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                if let swiftRange = Range(capture, in: text) {
                    matches.append(String(text[swiftRange]))
                }
            }
        }
        let encoders = Array(Set(matches)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if !encoders.isEmpty {
            return RemoteEncoderDetectionResult(encoders: encoders, message: "")
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

private struct LatencyResult: Identifiable {
    let id = UUID()
    let label: String
    let samples: [Double]
    let failures: Int

    var average: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }
}

private struct ConnectionLatencyTestView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    let connections: [DeviceConnection]
    @State private var results: [LatencyResult] = []
    @State private var running = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("sessionLatencyTest").font(.headline)
                    Text("sessionLatencyTestCaption").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(running ? "sessionStopTest" : "sessionRunAgain") { runTests() }
                    .disabled(running)
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
            }
            .padding(16)
            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    if results.isEmpty && running {
                        ProgressView("sessionTesting").padding(30)
                    }
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.label).font(.system(size: 13, weight: .semibold))
                            Text(String(
                                format: String.localizedKey("sessionLatencySummary"),
                                result.average, result.samples.count, result.failures
                            ))
                            .font(.caption)
                            .foregroundColor(result.samples.isEmpty ? .red : .secondary)
                            if !result.samples.isEmpty {
                                Text(result.samples.map { String(format: "%.1f", $0) }.joined(separator: " · ") + " ms")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(13)
                        .appCard(radius: 10)
                    }
                }
                .padding(16)
            }
        }
        .onAppear { runTests() }
    }

    private func runTests() {
        guard !running else { return }
        running = true
        results = []
        let endpoints = connections
        let adbPath = appState.adbPath
        Task {
            let measured = await Task.detached(priority: .userInitiated) {
                endpoints.map { measure($0, adbPath: adbPath) }
            }.value
            results = measured
            running = false
        }
    }
}

private func measure(_ connection: DeviceConnection, adbPath: String) -> LatencyResult {
    var samples: [Double] = []
    var failures = 0
    for _ in 0..<10 {
        let start = CFAbsoluteTimeGetCurrent()
        let process = Process()
        if connection.transport == .tcp {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = ["-z", "-G", "2", connection.host, String(connection.port)]
        } else {
            process.executableURL = URL(fileURLWithPath: adbPath.isEmpty ? "/usr/bin/env" : adbPath)
            let target = connection.transport == .usb ? connection.serial : connection.host
            process.arguments = (adbPath.isEmpty ? ["adb"] : []) + ["-s", target, "shell", "echo", "ok"]
        }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                samples.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
            } else {
                failures += 1
            }
        } catch {
            failures += 1
        }
    }
    return LatencyResult(label: connection.displayAddress, samples: samples, failures: failures)
}

private struct FormPickerControl<Content: View, Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .medium))
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .frame(width: 150)
        }
    }
}

private struct AccentPickerControl: View {
    let colors: [Color]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 9) {
            ForEach(colors.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Circle()
                        .fill(colors[index])
                        .frame(width: 20, height: 20)
                        .appOverlay(Circle().stroke(Color.white, lineWidth: selection == index ? 2 : 0).padding(3))
                        .appOverlay(Circle().stroke(colors[index].opacity(0.45), lineWidth: selection == index ? 3 : 0))
                }
                .buttonStyle(.plain)
                .help("addDeviceChooseLabelColor")
            }
        }
    }
}
