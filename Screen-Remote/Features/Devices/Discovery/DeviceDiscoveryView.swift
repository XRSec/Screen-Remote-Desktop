import Network
import SwiftUI

struct DiscoveredADBDevice: Identifiable, Hashable {
    enum Source: String {
        case devices = "ADB"
        case mdns = "mDNS"
    }

    let id: String
    let name: String
    let address: String
    let state: String
    let source: Source
    let transport: DeviceTransport
    let requiresPairing: Bool
}

struct DeviceDiscoveryEmptyView: View {
    let icon: String

    var body: some View {
        ContentUnavailableViewCompat(
            icon: icon,
            title: "deviceDiscoveryEmptyTitle",
            detail: "deviceDiscoveryEmptyDetail"
        )
    }
}

private final class ADBMDNSBrowser: ObservableObject {
    @Published private(set) var devices: [DiscoveredADBDevice] = []
    @Published private(set) var isReady = false

    private let queue = DispatchQueue(label: "com.screenremote.mdns-discovery")
    private var browsers: [NWBrowser] = []
    private var devicesByServiceType: [String: [DiscoveredADBDevice]] = [:]
    private var readyServiceTypes: Set<String> = []
    private var isRunning = false

    func start() {
        guard browsers.isEmpty else { return }
        isRunning = true
        startBrowser(serviceType: "_adb-tls-connect._tcp", stateKey: "deviceDiscoveryConnectable")
        startBrowser(serviceType: "_adb-tls-pairing._tcp", stateKey: "deviceDiscoveryPairable")
    }

    func stop() {
        isRunning = false
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        devicesByServiceType.removeAll()
        readyServiceTypes.removeAll()
        devices = []
        isReady = false
    }

    private func startBrowser(serviceType: String, stateKey: String) {
        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: .tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let discovered = results.compactMap { result -> DiscoveredADBDevice? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                let address = mdnsDeviceSerial(name)
                return DiscoveredADBDevice(
                    id: "mdns:\(DeviceTransport.mdns.rawValue):\(serviceType):\(name)",
                    name: name,
                    address: address,
                    state: String.localizedKey(stateKey),
                    source: .mdns,
                    transport: .mdns,
                    requiresPairing: serviceType.localizedCaseInsensitiveContains("pairing")
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.devicesByServiceType[serviceType] = discovered
                self.devices = self.devicesByServiceType.values
                    .flatMap { $0 }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                switch state {
                case .ready:
                    self.readyServiceTypes.insert(serviceType)
                case .failed, .cancelled:
                    self.readyServiceTypes.remove(serviceType)
                default:
                    break
                }
                self.isReady = self.readyServiceTypes.count == 2
            }
        }
        browsers.append(browser)
        browser.start(queue: queue)
    }
}

struct DeviceDiscoveryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var mdnsBrowser = ADBMDNSBrowser()
    @State private var commandDevices: [DiscoveredADBDevice] = []
    @State private var isRefreshing = false
    @State private var statusText = String.localizedKey("deviceDiscoveryWaiting")
    @State private var errorText: String?

    private var devices: [DiscoveredADBDevice] {
        let commandResults = mdnsBrowser.isReady
            ? commandDevices.filter { $0.source != .mdns || $0.transport == .tcp }
            : commandDevices
        return Array(Dictionary(grouping: commandResults + mdnsBrowser.devices, by: \.id).compactMap { $0.value.first })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("deviceDiscoveryTitle").font(.title2.bold())
                    Text("deviceDiscoverySubtitle").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { refresh() } label: {
                    Label(isRefreshing ? "deviceDiscoveryRefreshing" : "commonRefresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                Button("commonClose") { presentationMode.wrappedValue.dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    if isRefreshing { ProgressView().controlSize(.small) }
                    Text(statusText).font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: String.localizedKey("deviceDiscoveryDeviceCount"), "\(devices.count)")).font(.caption).foregroundColor(Color.secondary.opacity(0.65))
                }

                ScrollView {
                    LazyVStack(spacing: 9) {
                        if devices.isEmpty && !isRefreshing {
                            DeviceDiscoveryEmptyView(icon: "dot.radiowaves.left.and.right")
                                .frame(height: 220)
                        }

                        ForEach(devices) { device in
                            DiscoveredDeviceRow(device: device) {
                                add(device)
                            }
                        }
                    }
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.caption)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.md)
                        .appBackground(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: AppRadius.small))
                }

                HStack(spacing: 10) {
                    Image(systemName: "network")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("deviceDiscoveryPortScanTitle").font(.subheadline.weight(.medium))
                        Text("deviceDiscoveryPortScanDetail").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Label("deviceDiscoveryPortScanUnavailable", systemImage: "info.circle")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                }
                .padding(13)
                .appCard(radius: 10)
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .onAppear {
            mdnsBrowser.start()
            refresh()
        }
        .onDisappear { mdnsBrowser.stop() }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorText = nil
        statusText = String.localizedKey("deviceDiscoveryReadingDevices")
        let adbPath = appState.adbPath

        Task {
            let deviceResult = await ADBCommandRunner.run(executable: adbPath, arguments: ["devices", "-l"])
            await MainActor.run { statusText = String.localizedKey("deviceDiscoveryReadingMDNS") }
            let mdnsResult = await ADBCommandRunner.run(executable: adbPath, arguments: ["mdns", "services"])
            let parsed = parseADBDevices(deviceResult.output) + parseMDNSServices(mdnsResult.output)
            let unique = Array(Dictionary(grouping: parsed, by: \.id).compactMap { $0.value.first }).sorted { $0.name < $1.name }

            await MainActor.run {
                commandDevices = unique
                isRefreshing = false
                statusText = String.localizedKey("deviceDiscoveryComplete")
                let errors = [deviceResult, mdnsResult]
                    .filter { $0.exitCode != 0 }
                    .map { $0.error.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                errorText = errors.isEmpty ? nil : errors.joined(separator: " · ")
                appState.appendSDLLog("ADB device discovery complete: devices=\(parseADBDevices(deviceResult.output).count), mdns=\(parseMDNSServices(mdnsResult.output).count)")
            }
        }
    }

    private func add(_ discovered: DiscoveredADBDevice) {
        guard !discovered.requiresPairing else {
            errorText = String.localizedKey("deviceDiscoveryPairingRequiredDetail")
            return
        }
        guard !appState.devices.contains(where: { device in
            device.connections.contains { $0.displayAddress.caseInsensitiveCompare(discovered.address) == .orderedSame }
        }) else {
            errorText = String.localizedKey("deviceDiscoveryAlreadyAdded")
            return
        }

        let connection: DeviceConnection
        switch discovered.transport {
        case .usb:
            connection = DeviceConnection(transport: .usb, serial: discovered.address)
        case .mdns:
            connection = DeviceConnection(transport: .mdns, host: discovered.address)
        case .tcp:
            let parts = splitHostPort(discovered.address)
            connection = DeviceConnection(transport: .tcp, host: parts.host, port: parts.port ?? 5555)
        }

        appState.addDevice(
            Device(
                name: discovered.name,
                model: String.localizedKey("deviceDiscoveryAndroidDevice"),
                systemVersion: String.localizedKey("deviceDiscoveryWaitingToConnect"),
                battery: 0,
                accent: discovered.source == .mdns ? .appCyan : .blue,
                isConnected: discovered.state == "device",
                connections: [connection],
                scrcpyOptions: ScrcpyDeviceOptions()
            )
        )
    }
}

private struct DiscoveredDeviceRow: View {
    let device: DiscoveredADBDevice
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconTile(symbol: device.source == .mdns ? "wifi" : "cable.connector", color: device.source == .mdns ? .appCyan : .blue, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name).font(.subheadline.weight(.semibold))
                Text(device.address).font(.appCaptionMonospaced).foregroundColor(.secondary)
            }
            Spacer()
            Text(device.source.rawValue).font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            Text(device.state).font(.caption).foregroundColor(device.state == "device" ? .green : .orange)
            if device.requiresPairing {
                Label("deviceDiscoveryPairingRequired", systemImage: "lock.fill")
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                    .help("deviceDiscoveryPairingRequiredDetail")
            } else {
                Button("commonAdd", action: onAdd)
            }
        }
        .padding(13)
        .appCard(radius: 11)
    }
}

func parseADBDevices(_ output: String) -> [DiscoveredADBDevice] {
    output.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2 else { return nil }
        let serial = fields[0]
        let state = fields[1]
        let model = fields.first { $0.hasPrefix("model:") }?.dropFirst(6).replacingOccurrences(of: "_", with: " ")
        let transport: DeviceTransport
        let address: String
        if splitHostPort(serial).port != nil {
            transport = .tcp
            address = serial
        } else if serial.localizedCaseInsensitiveContains("_adb") {
            transport = .mdns
            address = mdnsDeviceSerial(serial)
        } else {
            transport = .usb
            address = serial
        }
        return DiscoveredADBDevice(
            id: "devices:\(serial)",
            name: model?.isEmpty == false ? model! : serial,
            address: address,
            state: state,
            source: .devices,
            transport: transport,
            requiresPairing: false
        )
    }
}

func parseMDNSServices(_ output: String) -> [DiscoveredADBDevice] {
    output.split(whereSeparator: \.isNewline).compactMap { line in
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2, !line.lowercased().contains("list of discovered") else { return nil }
        let serviceName = fields[0]
        let serviceType = fields.first { $0.contains("_adb") } ?? "mDNS"
        let endpoint = fields.last { splitHostPort($0).port != nil }
        let isLegacyTCP = serviceType.localizedCaseInsensitiveContains("_adb._tcp")
        let transport: DeviceTransport = isLegacyTCP ? .tcp : .mdns
        let address = isLegacyTCP ? (endpoint ?? serviceName) : mdnsDeviceSerial(serviceName)
        let requiresPairing = serviceType.localizedCaseInsensitiveContains("pairing")
        return DiscoveredADBDevice(
            id: "mdns:\(transport.rawValue):\(serviceName):\(address)",
            name: serviceName,
            address: address,
            state: requiresPairing
                ? String.localizedKey("deviceDiscoveryPairable")
                : String.localizedKey("deviceDiscoveryConnectable"),
            source: .mdns,
            transport: transport,
            requiresPairing: requiresPairing
        )
    }
}

func splitHostPort(_ value: String) -> (host: String, port: Int?) {
    if value.hasPrefix("["), let closing = value.firstIndex(of: "]") {
        let host = String(value[value.index(after: value.startIndex)..<closing])
        let suffix = value[value.index(after: closing)...]
        return (host, Int(suffix.drop(while: { $0 == ":" })))
    }
    guard let separator = value.lastIndex(of: ":"), let port = Int(value[value.index(after: separator)...]) else {
        return (value, nil)
    }
    return (String(value[..<separator]), port)
}

func mdnsDeviceSerial(_ value: String) -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.lowercased().hasPrefix("mdns:") {
        normalized = String(normalized.dropFirst(5))
    }
    normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    if normalized.lowercased().hasSuffix(".local") {
        normalized = String(normalized.dropLast(6))
    }
    normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    for suffix in ["._adb-tls-connect._tcp", "._adb-tls-pairing._tcp", "._adb._tcp"] {
        if normalized.lowercased().hasSuffix(suffix) {
            normalized = String(normalized.dropLast(suffix.count))
            break
        }
    }
    guard normalized.lowercased().hasPrefix("adb-") else { return normalized }
    let serialAndNonce = String(normalized.dropFirst(4))
    guard let separator = serialAndNonce.lastIndex(of: "-"),
          separator != serialAndNonce.startIndex,
          separator != serialAndNonce.index(before: serialAndNonce.endIndex) else {
        return serialAndNonce
    }
    return String(serialAndNonce[..<separator])
}
