import AppKit
import AudioToolbox
import SwiftUI
import VideoToolbox

extension AddDeviceView {
    var flowingContent: some View {
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
    func formSection(_ section: FormSection) -> some View {
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
        case .startApp:
            if !newDisplayEnabled {
                startAppSection
            }
        case .otherOptions:
            otherOptionsSection
        }
    }

    var header: some View {
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

    var primaryConnectionSection: some View {
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

    var remoteNavigationSection: some View {
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

    var groupSelectionSummary: String {
        let selectedNames = appState.flattenedGroups()
            .filter { groupIDs.contains($0.id) }
            .map { $0.group.name }
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

    var connectionOptionsSection: some View {
        DeviceFormSection(title: "sessionConnectionOptionsSection") {
            FormToggleRow(title: "sessionCompatibilityMode", isOn: $compatibilityMode, help: "sessionHelpCompatibility")
                .onChange(of: compatibilityMode) { enabled in
                    if enabled {
                        enableAudio = false
                        gameMode = false
                        enableHardwareDecoding = false
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
            FormSecureTextRow(
                title: "sessionShellPassword",
                text: $shellPassword,
                placeholder: "sessionShellPasswordPlaceholder",
                help: "sessionHelpShellPassword"
            )
            FormDivider()
            FormToggleRow(title: "sessionHardwareDecoding", isOn: $enableHardwareDecoding, help: "sessionHelpHardwareDecoding", enabled: !compatibilityMode)
        }
    }

    var backupConnectionsSection: some View {
        DeviceFormSection(title: "addDeviceBackupSection", subtitle: "addDeviceBackupSectionHint") {
            if backupConnections.isEmpty {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(AppTypography.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .appBackground(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: AppRadius.small))
                    Text("addDeviceNoBackupAddress")
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        appendBackupConnection()
                    } label: {
                        Label("addDeviceAddAddress", systemImage: "plus")
                    }
                }
                .padding(AppSpacing.md)
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

    var videoSection: some View {
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

    var audioSection: some View {
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

    var otherOptionsSection: some View {
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

    var virtualDisplaySection: some View {
        DeviceFormSection(title: "sessionVirtualDisplaySection") {
            FormToggleRow(title: "sessionNewDisplay", isOn: $newDisplayEnabled, help: "sessionHelpNewDisplay", enabled: !compatibilityMode)
            if newDisplayEnabled {
                FormDivider()
                FormToggleRow(title: "sessionDisplaySystemUI", isOn: $virtualDisplaySystemDecorations, help: "sessionHelpDisplaySystemUI")
                FormDivider()
                FormToggleRow(title: "sessionPreserveDisplay", isOn: $preserveVirtualDisplayContent, help: "sessionHelpPreserveDisplay")
                FormDivider()
                DisplaySizeRow(width: $newDisplayWidth, height: $newDisplayHeight, dpi: $newDisplayDPI)
            }
        }
    }

    var startAppSection: some View {
        DeviceFormSection(title: "sessionStartApp") {
            StartAppFormRow(
                text: $startApp,
                isSearchEnabled: editingDevice != nil,
                onSearch: { showingRemoteAppSelector = true }
            )
        }
    }

    var saveHint: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "info.circle.fill").foregroundColor(AppTheme.accent)
            Text("addDeviceSaveHint")
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .appBackground(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    @ViewBuilder
    var connectionFields: some View {
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

    var isValid: Bool {
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

    func appendBackupConnection() {
        backupConnections.append(ConnectionDraft())
    }

    func discoveryCurrentAddress(for target: ConnectionDiscoveryTarget) -> String {
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

    func applyDiscoveredDevice(
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

    func apply(_ device: DiscoveredADBDevice, to draft: inout ConnectionDraft) {
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

    var portNumber: Int? {
        guard let value = Int(port), (1...65_535).contains(value) else { return nil }
        return value
    }

    func applyGameModePresets() {
        maxSize = closestPreset(maxSize, values: [720, 1080, 1920], fallback: 720)
        videoBitrate = closestBitratePreset(videoBitrate, values: [1, 2, 4, 8, 12, 20], fallback: 2)
        maxFPS = closestPreset(maxFPS, values: [60, 90, 120], fallback: 60)
    }

    var currentConnections: [DeviceConnection] {
        let primary = DeviceConnection(
            transport: transport, host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portNumber ?? 0, serial: serial.trimmingCharacters(in: .whitespacesAndNewlines), priority: 0
        )
        return [primary] + backupConnections.enumerated().map { $0.element.connection(priority: $0.offset + 1) }
    }

    func saveDevice() {
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
                    shellPassword: shellPassword,
                    enableHardwareDecoding: enableHardwareDecoding,
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

private struct StartAppFormRow: View {
    @Binding var text: String
    let isSearchEnabled: Bool
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FormLabel(title: "sessionStartApp", help: "sessionHelpStartApp")
            Spacer()
            TextField("com.example.app", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 360)
                .accessibilityLabel(Text("sessionStartApp"))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .help("commonClear")
                .accessibilityLabel(Text("commonClear"))
            }
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(!isSearchEnabled)
            .help("sessionSelectRemoteApp")
            .accessibilityLabel(Text("sessionSelectRemoteApp"))
            .accessibilityHint(isSearchEnabled ? Text("") : Text("sessionSelectRemoteAppRequiresSavedDevice"))
        }
        .padding(14)
    }
}

struct RemoteAppSelector: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    let device: Device?
    @Binding var selection: String
    @State private var apps: [ManagedAndroidApp] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var hasLoadedAllApps = false
    @State private var errorMessage: String?

    private var filteredApps: [ManagedAndroidApp] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return apps }
        return apps.filter {
            $0.packageName.localizedCaseInsensitiveContains(keyword)
                || $0.name.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            searchBar
            Divider()
            contentGroup
        }
        .frame(minWidth: 480, idealHeight: 380, maxHeight: 620)
    }

    private var headerBar: some View {
        ZStack {
            Text("sessionSelectRemoteApp")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Spacer()
                Button("commonCancel") { presentationMode.wrappedValue.dismiss() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("appsSearchPrompt", text: $query)
                .textFieldStyle(.roundedBorder)
            Button("Q", action: search)
                .buttonStyle(.borderless)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .appBackground(AppTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: AppRadius.small))
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading)
                .accessibilityLabel("appsSearchPrompt")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var contentGroup: some View {
        Group {
            if isLoading {
                ProgressView("appsManageLoading")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let errorMessage {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(AppTypography.largeTitle)
                        .foregroundColor(.orange)
                    Text("appsManageLoadFailedTitle")
                        .font(AppTypography.headline)
                    Text(errorMessage)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                }
                .frame(maxWidth: .infinity)
            } else if !hasSearched || filteredApps.isEmpty {
                ContentUnavailableViewCompat(
                    icon: "magnifyingglass",
                    title: hasSearched ? "appsManageNoSearchResults" : "sessionSelectRemoteApp",
                    detail: "appsSearchPrompt"
                )
            } else {
                List(filteredApps) { app in
                    Button {
                        selection = app.packageName
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                Text(app.packageName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10)
                        .background(AppTheme.surface)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowBackground(Color.clear)
                }
                .listStyle(.inset)
                .frame(maxHeight: 500)
            }
        }
        .frame(minHeight: 220, maxHeight: 520)
    }

    private func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty, hasLoadedAllApps {
            hasSearched = true
            errorMessage = nil
            return
        }
        guard let device, !isLoading else { return }
        isLoading = true
        hasSearched = true
        errorMessage = nil
        let adbPath = appState.adbPath
        Task {
            do {
                let serial = try await DeviceAppADB.resolveSerial(for: device, configuredADBPath: adbPath)
                let loadedApps = try await DeviceAppADB.listApps(serial: serial, configuredADBPath: adbPath)
                await MainActor.run {
                    apps = loadedApps
                    hasLoadedAllApps = keyword.isEmpty
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
