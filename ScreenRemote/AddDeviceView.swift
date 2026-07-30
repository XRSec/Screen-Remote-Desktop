import SwiftUI

private struct ConnectionDraft: Identifiable {
    let id = UUID()
    var transport: DeviceTransport = .tcp
    var host = ""
    var port = "5555"
    var serial = ""

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

struct AddDeviceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode

    @State private var name = ""
    @State private var transport: DeviceTransport = .tcp
    @State private var host = ""
    @State private var port = "5555"
    @State private var serial = ""
    @State private var backupConnections: [ConnectionDraft] = []
    @State private var accentIndex = 0
    @State private var groupID = DeviceGroup.ungroupedID

    @State private var maxSize = 0
    @State private var videoBitrate = "8M"
    @State private var maxFPS = 60
    @State private var enableAudio = false
    @State private var clipboardSync = true
    @State private var turnScreenOff = false
    @State private var keepDeviceAwake = true
    @State private var fullscreen = false

    private let accentColors: [Color] = [.appIndigo, .blue, .appCyan, .green, .orange, .purple]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            GeometryReader { proxy in
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            Color.clear.frame(height: 0).id("add-device-top")
                            primaryConnectionSection
                            backupConnectionsSection
                            sessionOptions(wide: proxy.size.width >= 760)
                            saveHint
                        }
                        .frame(maxWidth: 860)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollProxy.scrollTo("add-device-top", anchor: .top)
                        }
                    }
                }
            }
        }
        .background(AppTheme.background)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconTile(symbol: "plus.rectangle.on.rectangle", color: AppTheme.accent, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("addDeviceTitle").font(.title3.bold())
                Text("addDeviceSubtitle")
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
            FormTextRow(title: "addDeviceSessionName", placeholder: "addDeviceSessionNamePlaceholder", text: $name)
            FormDivider()

            VStack(alignment: .leading, spacing: 9) {
                Text("addDeviceConnectionType").font(.system(size: 13, weight: .medium))
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
            FormDivider()

            HStack(spacing: 24) {
                FormPickerControl(title: "addDeviceGroup", selection: $groupID) {
                    Text("addDeviceUngrouped").tag(DeviceGroup.ungroupedID)
                    ForEach(appState.groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                AccentPickerControl(colors: accentColors, selection: $accentIndex)
            }
            .padding(14)
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
                        backupConnections.append(ConnectionDraft())
                    } label: {
                        Label("addDeviceAddAddress", systemImage: "plus")
                    }
                }
                .padding(14)
            } else {
                ForEach($backupConnections) { $endpoint in
                    BackupConnectionEditor(endpoint: $endpoint) {
                        backupConnections.removeAll { $0.id == endpoint.id }
                    }
                    if endpoint.id != backupConnections.last?.id {
                        FormDivider()
                    }
                }

                FormDivider()
                HStack {
                    Spacer()
                    Button {
                        backupConnections.append(ConnectionDraft())
                    } label: {
                        Label("addDeviceAddAnotherAddress", systemImage: "plus")
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private func sessionOptions(wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 18) {
                videoSection.frame(maxWidth: .infinity)
                controlsSection.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 18) {
                videoSection
                controlsSection
            }
        }
    }

    private var videoSection: some View {
        DeviceFormSection(title: "addDeviceVideoSection", subtitle: "addDeviceVideoSectionHint") {
            FormPickerRow(title: "addDeviceMaxResolution", selection: $maxSize) {
                Text("addDeviceOriginalSize").tag(0)
                Text("720p").tag(720)
                Text("1080p").tag(1080)
                Text("1920p").tag(1920)
            }
            FormDivider()
            FormPickerRow(title: "addDeviceVideoBitrate", selection: $videoBitrate) {
                ForEach(["1M", "2M", "4M", "8M", "12M", "20M"], id: \.self) { Text($0).tag($0) }
            }
            FormDivider()
            FormPickerRow(title: "addDeviceMaxFrameRate", selection: $maxFPS) {
                ForEach([30, 60, 90, 120], id: \.self) { Text("\($0) FPS").tag($0) }
            }
            FormDivider()
            FormToggleRow(title: "addDeviceFullscreen", isOn: $fullscreen)
        }
    }

    private var controlsSection: some View {
        DeviceFormSection(title: "addDeviceAudioControlSection", subtitle: "addDeviceAudioControlSectionHint") {
            FormToggleRow(title: "addDeviceForwardAudio", isOn: $enableAudio)
            FormDivider()
            FormToggleRow(title: "addDeviceSyncClipboard", isOn: $clipboardSync)
            FormDivider()
            FormToggleRow(title: "addDeviceTurnScreenOff", isOn: $turnScreenOff)
            FormDivider()
            FormToggleRow(title: "addDeviceKeepAwake", isOn: $keepDeviceAwake)
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
                FormField(title: "addDeviceIPAddress", placeholder: "192.168.1.100", text: $host)
                    .frame(maxWidth: .infinity)
                FormField(title: "addDevicePort", placeholder: "5555", text: $port)
                    .frame(width: 120)
            }
            .padding(14)
        case .usb:
            FormTextRow(title: "addDeviceUSBSerial", placeholder: "10AEAG2YZS0020P", text: $serial)
        case .mdns:
            FormTextRow(title: "addDeviceMDNSServiceOrSerial", placeholder: "R5CW730QLKB", text: $host)
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

    private var portNumber: Int? {
        guard let value = Int(port), (1...65_535).contains(value) else { return nil }
        return value
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

        appState.addDevice(
            Device(
                name: normalizedName,
                model: NSLocalizedString("addDeviceDefaultModel", comment: "Default model for a newly added device"),
                systemVersion: NSLocalizedString("addDeviceWaitingToConnect", comment: "Initial connection status"),
                battery: 0,
                accent: accentColors[accentIndex],
                isConnected: false,
                groupID: groupID == DeviceGroup.ungroupedID ? nil : groupID,
                connections: connections,
                scrcpyOptions: ScrcpyDeviceOptions(
                    maxSize: maxSize,
                    videoBitrate: videoBitrate,
                    maxFPS: maxFPS,
                    enableAudio: enableAudio,
                    clipboardSync: clipboardSync,
                    turnScreenOff: turnScreenOff,
                    keepDeviceAwake: keepDeviceAwake,
                    fullscreen: fullscreen
                )
            )
        )
        presentationMode.wrappedValue.dismiss()
    }
}

private struct BackupConnectionEditor: View {
    @Binding var endpoint: ConnectionDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 10) {
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
        }
        .padding(14)
        .background(Color.primary.opacity(0.025))
    }
}

private struct DeviceFormSection<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle = subtitle {
                    Text(subtitle).font(.caption2).foregroundColor(.secondary)
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
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 13, weight: .medium))
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
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

private struct FormPickerRow<Content: View, Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .frame(width: 150)
        }
        .padding(14)
    }
}

private struct FormToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .font(.system(size: 13, weight: .medium))
            .padding(14)
    }
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
        HStack(spacing: 12) {
            Text("addDeviceLabelColor").font(.system(size: 13, weight: .medium))
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
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
