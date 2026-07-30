import Foundation
import SwiftUI

private let deviceInfoColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let deviceInfoGridMaxWidth: CGFloat = 914

private enum RemoteDeviceField: String, CaseIterable {
    case model
    case manufacturer
    case socModel = "soc_model"
    case androidVersion = "android_version"
    case sdk
    case uptime
    case baseband
    case productCodeName = "product_code_name"
    case securityPatch = "security_patch"
    case serial
    case resolution
    case density
    case displayMetrics = "display_metrics"
    case displayInfo = "display_info"
    case networkInterfaces = "network_interfaces"
    case defaultRoute = "default_route"
    case mobileNetworkType = "mobile_network_type"
    case carrierNames = "carrier_names"
    case signalStrength = "signal_strength"
    case cellIdentity = "cell_identity"
    case wifiInfo = "wifi_info"
    case memory
    case dataFilesystem = "data_filesystem"
    case batteryCycle = "battery_cycle"
    case battery
    case voltageNow = "voltage_now"
    case batteryCurrentNow = "battery_current_now"
    case batteryCurrentAverage = "battery_current_average"
    case sysfsCurrent = "sysfs_current"
    case abi
    case board
    case fingerprint
    case wirelessPort = "wireless_port"
    case cpuCount = "cpu_count"
    case cpuMaxFrequency = "cpu_max_frequency"
}

private struct RemoteDeviceFieldResult {
    let value: String
    let error: String
}

private struct DeviceInformationSnapshot {
    let fields: [RemoteDeviceField: RemoteDeviceFieldResult]

    func value(_ field: RemoteDeviceField) -> String {
        fields[field]?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct DeviceInfoRow: Identifiable {
    let label: LocalizedStringKey
    let value: String
    var id: String { "\(label)-\(value)" }
}

private struct DeviceInfoGroup: Identifiable {
    let title: LocalizedStringKey
    let rows: [DeviceInfoRow]
    var id: String { "\(title)" }
}

struct DeviceInformationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
    let isCompact: Bool

    @State private var snapshot: DeviceInformationSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var refreshID = UUID()

    var body: some View {
        ScrollView {
            if managementTarget(from: appState) == nil {
                ManagementUnavailableView()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                    if let errorMessage { ManagementErrorBanner(message: errorMessage) }

                    if let snapshot, let target = managementTarget(from: appState) {
                        LazyVGrid(columns: deviceInfoColumns, alignment: .center, spacing: 14) {
                            ForEach(groups(for: snapshot, target: target)) { group in
                                DeviceInfoSection(group: group)
                            }
                        }
                        .frame(maxWidth: deviceInfoGridMaxWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(isCompact ? 20 : 28)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: appState.selectedDevice) { _ in refresh() }
        .onChange(of: managementTarget(from: appState)?.serial ?? "") { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .screenRemoteRefreshManagement)) { _ in refresh() }
    }

    private func refresh() {
        guard let target = managementTarget(from: appState) else {
            snapshot = nil
            isLoading = false
            return
        }
        let requestID = UUID()
        refreshID = requestID
        snapshot = nil
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let helper = try await DADBHelperRuntime.prepare(
                    serial: target.serial,
                    configuredADBPath: target.adbPath
                )
                let output = try await helper.invoke(
                    mainClass: "dadb.helper.ManagementSnapshotMain",
                    arguments: ["device"],
                    timeout: 40
                )
                let loaded = try parseDeviceInformationResponse(output.standardOutput)
                guard refreshID == requestID,
                      managementTarget(from: appState)?.serial == target.serial else { return }
                snapshot = loaded
                logFieldDiagnostics(loaded, deviceName: target.device.name)
                appState.appendSDLLog("Device information loaded: \(target.device.name)")
            } catch {
                guard refreshID == requestID,
                      managementTarget(from: appState)?.serial == target.serial else { return }
                errorMessage = String.localizedKey("managementDeviceInfoLoadFailed")
                appState.appendSDLLog(
                    "Failed to load device information: \(target.device.name), \(englishDiagnostic(for: error))"
                )
            }
            if refreshID == requestID { isLoading = false }
        }
    }

    private func logFieldDiagnostics(_ snapshot: DeviceInformationSnapshot, deviceName: String) {
        for field in RemoteDeviceField.allCases {
            guard let result = snapshot.fields[field] else {
                appState.appendSDLLog(
                    "Device information field missing: \(deviceName), \(field.rawValue)"
                )
                continue
            }
            if !result.error.isEmpty {
                appState.appendSDLLog(
                    "Device information field failed: \(deviceName), \(field.rawValue), \(result.error)"
                )
            }
        }
    }

    private func englishDiagnostic(for error: Error) -> String {
        if let error = error as? DADBHelperRuntimeError { return error.englishDiagnostic }
        if let error = error as? DeviceInformationProtocolError { return error.englishDiagnostic }
        return String(describing: error)
    }

    private func groups(
        for snapshot: DeviceInformationSnapshot,
        target: ManagementTarget
    ) -> [DeviceInfoGroup] {
        _ = locale
        let model = snapshot.value(.model)
        let manufacturer = snapshot.value(.manufacturer)
        let board = snapshot.value(.board)
        let display = displayValues(snapshot)
        let battery = batteryValues(snapshot)
        let storageMemory = storageMemoryValues(snapshot)
        let network = networkValues(snapshot)

        let connectionType: String = target.device.connections.contains {
            $0.transport == .usb && $0.serial.trimmingCharacters(in: .whitespacesAndNewlines) == target.serial
        } ? "USB / OTG" : "Wi-Fi / TCP"
        let connection = "\(connectionType) / \(target.serial)"

        return [
            group("managementDeviceInfoSystemHardware", [
                row("managementDeviceInfoBrandModel", join([manufacturer, model], separator: " ")),
                row("managementDeviceInfoSoC", nonempty(snapshot.value(.socModel), fallback: board)),
                row("managementDeviceInfoAndroidVersion", snapshot.value(.androidVersion)),
                row("managementDeviceInfoSDK", snapshot.value(.sdk)),
                row("managementDeviceInfoUptime", formatUptime(snapshot.value(.uptime))),
                row("managementDeviceInfoBaseband", uniqueList(snapshot.value(.baseband), separator: " / ")),
                row("managementDeviceInfoProductCodename", snapshot.value(.productCodeName)),
                row("managementDeviceInfoSecurityPatch", snapshot.value(.securityPatch)),
                row("managementDeviceInfoSerial", snapshot.value(.serial)),
                row("managementDeviceInfoConnection", connection),
                row("managementDeviceInfoCPU", formatCPU(
                    count: snapshot.value(.cpuCount),
                    frequency: snapshot.value(.cpuMaxFrequency)
                )),
                row("managementDeviceInfoABI", snapshot.value(.abi)),
                row("managementDeviceInfoBoard", board)
            ]),
            group("managementDeviceInfoDisplayPower", [
                row("managementDeviceInfoDisplay", join([display.resolution, display.currentRate])),
                row("managementDeviceInfoScreen", join([display.dpi, display.ppi, display.screenSize], separator: " / ")),
                row("managementDeviceInfoRefreshRates", display.supportedRates),
                row("managementDeviceInfoBattery", join([battery.voltage, battery.current, battery.health])),
                row("managementDeviceInfoStatus", join([battery.level, battery.status, battery.temperature])),
                row("managementDeviceInfoCycleCount", battery.cycleCount)
            ]),
            group("managementDeviceInfoStorageMemory", [
                row("managementDeviceInfoStorage", storageMemory.storage),
                row("managementDeviceInfoMemory", storageMemory.memory)
            ]),
            group(
                "managementDeviceInfoNetwork",
                [
                    row("managementDeviceInfoCellular", network.cellular),
                    row("managementDeviceInfoCarrier", network.carrier),
                    row("managementDeviceInfoPCI", network.pci),
                    row("managementDeviceInfoArfcn", network.arfcn),
                    row("managementDeviceInfoRSRP", network.rsrp),
                    row("managementDeviceInfoRSRQ", network.rsrq),
                    row("managementDeviceInfoSINR", network.sinr),
                    row("managementDeviceInfoWifiSSID", network.ssid),
                    row("managementDeviceInfoWifiInfo", network.wifiSummary),
                    row("managementDeviceInfoBSSID", network.bssid)
                ].compactMap { $0 }
                    + network.interfaces
                    + [
                        row("managementDeviceInfoDefaultGateway", network.gateway),
                        row("managementDeviceInfoWirelessPort", validPort(snapshot.value(.wirelessPort)))
                    ].compactMap { $0 }
            ),
            group("managementDeviceInfoSystemIdentity", [
                row("managementDeviceInfoFingerprint", snapshot.value(.fingerprint))
            ])
        ].filter { !$0.rows.isEmpty }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> DeviceInfoRow? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : DeviceInfoRow(label: label, value: value)
    }

    private func group(_ title: LocalizedStringKey, _ rows: [DeviceInfoRow?]) -> DeviceInfoGroup {
        DeviceInfoGroup(title: title, rows: rows.compactMap { $0 })
    }

    private func group(_ title: LocalizedStringKey, _ rows: [DeviceInfoRow]) -> DeviceInfoGroup {
        DeviceInfoGroup(title: title, rows: rows)
    }

    private func formatUptime(_ raw: String) -> String {
        guard let value = Double(raw.split(whereSeparator: \.isWhitespace).first ?? ""),
              value.isFinite, value >= 0 else { return "" }
        let seconds = Int64(value)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return String(
                format: String.localizedKey("managementDeviceInfoUptimeDaysHours"),
                days,
                hours
            )
        }
        if hours > 0 {
            return String(
                format: String.localizedKey("managementDeviceInfoUptimeHoursMinutes"),
                hours,
                minutes
            )
        }
        return String(format: String.localizedKey("managementDeviceInfoUptimeMinutes"), minutes)
    }

    private func formatCPU(count: String, frequency: String) -> String {
        let cores = Int(count.trimmingCharacters(in: .whitespacesAndNewlines))
        let khz = Double(frequency.trimmingCharacters(in: .whitespacesAndNewlines))
        let frequencyText = khz.flatMap { $0 > 0 ? String(format: "%.2f GHz", $0 / 1_000_000) : nil } ?? ""
        if let cores, !frequencyText.isEmpty {
            return String(
                format: String.localizedKey("managementDeviceInfoCPUCoresFrequency"),
                cores,
                frequencyText
            )
        }
        if let cores {
            return String(format: String.localizedKey("managementDeviceInfoCPUCores"), cores)
        }
        return frequencyText
    }

    private func displayValues(_ snapshot: DeviceInformationSnapshot) -> DisplayValues {
        let resolution = wmValue(snapshot.value(.resolution))
        let density = wmValue(snapshot.value(.density))
        let info = snapshot.value(.displayInfo)
        let metrics = snapshot.value(.displayMetrics)
        let current = capture(info, #"renderFrameRate\s*([0-9]+(?:\.[0-9]+)?)"#)
            .flatMap(Double.init)
            .map { String(format: "%.0f Hz", $0) } ?? ""

        var rates = captures(info, #"fps=([0-9]+(?:\.[0-9]+)?)"#)
        if let direct = capture(info, #"supportedRefreshRates\s*\[([^\]]+)\]"#) {
            rates = direct.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let supported = orderedUnique(rates.compactMap(Double.init).map { String(format: "%.0f", $0) })
        let dpiPair = physicalDpi(metrics)
        let ppi = dpiPair.map { String(format: "%.0f PPI", ($0.0 + $0.1) / 2) } ?? ""
        let size: String
        if let (width, height) = resolutionPixels(resolution),
           let (xDpi, yDpi) = dpiPair, xDpi > 0, yDpi > 0 {
            let diagonal = hypot(Double(width) / xDpi, Double(height) / yDpi)
            size = diagonal.isFinite && diagonal > 0
                ? String(format: String.localizedKey("managementDeviceInfoScreenInches"), diagonal)
                : ""
        } else {
            size = ""
        }
        return DisplayValues(
            resolution: resolution,
            dpi: density.isEmpty ? "" : "\(density) DPI",
            ppi: ppi,
            screenSize: size,
            currentRate: current,
            supportedRates: supported.isEmpty ? "" : "\(supported.joined(separator: "/")) Hz"
        )
    }

    private func batteryValues(_ snapshot: DeviceInformationSnapshot) -> BatteryValues {
        let values = keyValueBlock(snapshot.value(.battery))
        let level = values["level"].map { "\($0) %" } ?? ""
        let status: String
        switch values["status"] {
        case "2": status = String.localizedKey("managementDeviceInfoBatteryCharging")
        case "3": status = String.localizedKey("managementDeviceInfoBatteryDischarging")
        case "4": status = String.localizedKey("managementDeviceInfoBatteryNotCharging")
        case "5": status = String.localizedKey("managementDeviceInfoBatteryFull")
        default: status = ""
        }
        let health: String
        switch values["health"] {
        case "2": health = String.localizedKey("managementDeviceInfoBatteryGood")
        case "3": health = String.localizedKey("managementDeviceInfoBatteryOverheating")
        case "4": health = String.localizedKey("managementDeviceInfoBatteryDead")
        case "5": health = String.localizedKey("managementDeviceInfoBatteryOverVoltage")
        case "7": health = String.localizedKey("managementDeviceInfoBatteryCold")
        default: health = ""
        }
        let temperature = Double(values["temperature"] ?? "").map { String(format: "%.1f °C", $0 / 10) } ?? ""
        let voltageRaw = firstPositiveInteger([
            values["voltage"] ?? "",
            snapshot.value(.voltageNow)
        ])
        let voltage = voltageRaw.map {
            let millivolts = $0 >= 100_000 ? Double($0) / 1_000 : Double($0)
            return String(format: "%.0f mV", millivolts)
        } ?? ""
        let currentRaw = firstNonzeroInteger([
            values["current now"] ?? "",
            values["current average"] ?? "",
            snapshot.value(.batteryCurrentNow),
            snapshot.value(.batteryCurrentAverage),
            snapshot.value(.sysfsCurrent)
        ])
        let current = currentRaw.map {
            let absolute = abs(Double($0))
            let milliamps = absolute >= 1_000_000_000
                ? absolute / 1_000_000
                : (absolute >= 10_000 ? absolute / 1_000 : absolute)
            return String(format: "%.0f mA", milliamps)
        } ?? ""
        let cycle = snapshot.value(.batteryCycle)
        return BatteryValues(
            level: level,
            status: status,
            health: health,
            voltage: voltage,
            current: current,
            temperature: temperature,
            cycleCount: cycle == "0" ? "" : cycle
        )
    }

    private func storageMemoryValues(_ snapshot: DeviceInformationSnapshot) -> StorageMemoryValues {
        let memory = keyValueBlock(snapshot.value(.memory))
        let totalMemory = memory["MemTotal"].flatMap(kilobytes)
        let availableMemory = memory["MemAvailable"].flatMap(kilobytes)
        let storageParts = snapshot.value(.dataFilesystem).split(whereSeparator: \.isWhitespace)
        let totalStorage = storageParts.count >= 4 ? Int64(storageParts[1]).flatMap(safeKilobytes) : nil
        let availableStorage = storageParts.count >= 4 ? Int64(storageParts[3]).flatMap(safeKilobytes) : nil
        return StorageMemoryValues(
            storage: resourceSummary(available: availableStorage, total: totalStorage),
            memory: resourceSummary(available: availableMemory, total: totalMemory)
        )
    }

    private func networkValues(_ snapshot: DeviceInformationSnapshot) -> NetworkValues {
        let networkType = uniqueList(
            snapshot.value(.mobileNetworkType),
            separator: ", ",
            filtersUnknown: true
        )
        let carrier = uniqueList(snapshot.value(.carrierNames), separator: ", ", filtersUnknown: true)
        let identity = snapshot.value(.cellIdentity)
        let bands = capture(identity, #"mBands\s*=\s*\[([^\]]+)\]"#)?
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        let cellular: String
        if bands.isEmpty {
            cellular = ""
        } else if networkType.localizedCaseInsensitiveContains("NR") {
            cellular = join([networkType, bands.map { "n\($0)" }.joined(separator: ", ")], separator: " ")
        } else {
            cellular = join([networkType, bands.map { $0.lowercased().hasPrefix("b") ? $0 : "B\($0)" }.joined(separator: ", ")], separator: " ")
        }
        let pci = capture(identity, #"mPci\s*=\s*([*\d]+)"#) ?? ""
        let arfcn = capture(identity, #"mNrArfcn\s*=\s*([*\d]+)"#)
            ?? capture(identity, #"mEarfcn\s*=\s*([*\d]+)"#) ?? ""
        let signal = signalValues(snapshot.value(.signalStrength))
        let wifi = snapshot.value(.wifiInfo)
        let rawSSID = capture(wifi, #"SSID:\s*"?(.*?)(?:"?\s*,|\s+BSSID:|$)"#) ?? ""
        let ssid = ["<unknown ssid>", "<none>", "null"].contains(rawSSID.lowercased()) ? "" : rawSSID
        let rawBSSID = capture(wifi, #"BSSID:\s*([^,]+)"#) ?? ""
        let bssid = ["<none>", "null"].contains(rawBSSID.lowercased()) ? "" : rawBSSID
        let frequency = capture(wifi, #"Frequency:\s*([0-9]+)\s*MHz"#).map { "\($0) MHz" } ?? ""
        let speed = capture(wifi, #"Link speed:\s*([0-9]+)\s*Mbps"#).map { "\($0) Mbps" } ?? ""
        return NetworkValues(
            cellular: cellular,
            carrier: carrier,
            pci: pci,
            arfcn: arfcn,
            rsrp: signal.0,
            rsrq: signal.1,
            sinr: signal.2,
            ssid: ssid,
            bssid: bssid,
            wifiSummary: join([frequency, speed]),
            interfaces: interfaceRows(snapshot.value(.networkInterfaces)),
            gateway: defaultGateway(snapshot.value(.defaultRoute))
        )
    }

    private func signalValues(_ raw: String) -> (String, String, String) {
        func metric(_ pattern: String, _ unit: String) -> String {
            guard let value = capture(raw, pattern), value != "2147483647" else { return "" }
            return "\(value) \(unit)"
        }
        let nr = (
            metric(#"ssRsrp\s*=\s*(-?\d+)"#, "dBm"),
            metric(#"ssRsrq\s*=\s*(-?\d+)"#, "dB"),
            capture(raw, #"ssSinr\s*=\s*(-?\d+)"#).flatMap(formatSinr) ?? ""
        )
        if !nr.0.isEmpty || !nr.1.isEmpty || !nr.2.isEmpty { return nr }
        return (
            metric(#"rsrp\s*=\s*(-?\d+)"#, "dBm"),
            metric(#"rsrq\s*=\s*(-?\d+)"#, "dB"),
            capture(raw, #"rssnr\s*=\s*(-?\d+)"#).flatMap(formatSinr) ?? ""
        )
    }

    private func formatSinr(_ raw: String) -> String? {
        guard raw != "2147483647", let value = Int(raw) else { return nil }
        return abs(value) >= 100 ? String(format: "%.1f dB", Double(value) / 10) : "\(value) dB"
    }

    private func interfaceRows(_ raw: String) -> [DeviceInfoRow] {
        var entries: [(String, String)] = []
        var ifconfigInterface = ""
        for line in raw.components(separatedBy: .newlines) {
            if let values = capturesFirst(line, #"^\d+:\s+([^:@\s]+)(?:@[^:\s]+)?\s+.*\binet\s+([0-9.]+)(?:/\d+)?\b"#),
               values.count == 2 {
                entries.append((values[0], values[1]))
                continue
            }
            if let first = line.first, !first.isWhitespace, !line.isEmpty {
                ifconfigInterface = line.components(separatedBy: CharacterSet(charactersIn: ": ")).first ?? ""
            }
            if !ifconfigInterface.isEmpty,
               let address = capture(line, #"\binet(?:\s+addr:|\s+)([0-9.]+)\b"#) {
                entries.append((ifconfigInterface, address))
            }
        }
        var seen = Set<String>()
        return entries
            .filter { $0.0 != "lo" && !$0.1.hasPrefix("127.") && seen.insert("\($0.0)|\($0.1)").inserted }
            .sorted { interfaceOrder($0.0) == interfaceOrder($1.0) ? $0.0 < $1.0 : interfaceOrder($0.0) < interfaceOrder($1.0) }
            .map { name, address in
                let key: LocalizedStringKey
                if name.range(of: #"^(wlan|wifi)\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    key = "managementDeviceInfoWifiIP"
                } else if name.range(of: #"^(ap|softap|swlan)\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    key = "managementDeviceInfoHotspotIP"
                } else if name.range(of: #"^(rndis|usb)\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    key = "managementDeviceInfoUSBTetheringIP"
                } else {
                    key = "managementDeviceInfoInterfaceIP"
                }
                return DeviceInfoRow(label: key, value: "\(address) (\(name))")
            }
    }

    private func interfaceOrder(_ name: String) -> Int {
        if name.range(of: #"^(wlan|wifi)\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil { return 0 }
        if name.range(of: #"^(ap|softap|swlan)\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil { return 1 }
        if name.range(of: #"^(rndis|usb)\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil { return 2 }
        return 3
    }

    private func defaultGateway(_ raw: String) -> String {
        if let route = raw.components(separatedBy: .newlines).first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("default") }) {
            let gateway = capture(route, #"\bvia\s+(\S+)"#) ?? ""
            let interface = capture(route, #"\bdev\s+(\S+)"#) ?? ""
            if !gateway.isEmpty && !interface.isEmpty { return "\(gateway) (\(interface))" }
            return nonempty(gateway, fallback: interface)
        }
        for line in raw.components(separatedBy: .newlines) {
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 4, columns[1] == "00000000",
                  let flags = Int(columns[3], radix: 16), flags & 0x2 != 0 else { continue }
            let bytes = stride(from: 0, to: 8, by: 2).compactMap {
                Int(columns[2].dropFirst($0).prefix(2), radix: 16)
            }
            guard bytes.count == 4 else { continue }
            return "\(bytes.reversed().map(String.init).joined(separator: ".")) (\(columns[0]))"
        }
        return ""
    }

    private func resourceSummary(available: Int64?, total: Int64?) -> String {
        guard let total, total > 0 else { return available.map(formatBytes) ?? "" }
        guard let available else { return formatBytes(total) }
        return "\(formatBytes(available)) / \(formatBytes(total)) (\(String(format: "%.0f", Double(available) / Double(total) * 100))%)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        String(format: "%.2f G", Double(bytes) / 1_073_741_824)
    }

    private func kilobytes(_ raw: String) -> Int64? {
        raw.split(whereSeparator: \.isWhitespace).first.flatMap { Int64($0) }.flatMap(safeKilobytes)
    }

    private func safeKilobytes(_ value: Int64) -> Int64? {
        guard value >= 0, value <= Int64.max / 1024 else { return nil }
        return value * 1024
    }

    private func validPort(_ raw: String) -> String {
        guard let port = Int(raw), port > 0 else { return "" }
        return String(port)
    }

    private func wmValue(_ raw: String) -> String {
        raw.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
    }

    private func physicalDpi(_ raw: String) -> (Double, Double)? {
        if let values = capturesFirst(raw, #"xDpi=([0-9]+(?:\.[0-9]+)?).*?yDpi=([0-9]+(?:\.[0-9]+)?)"#),
           values.count == 2, let x = Double(values[0]), let y = Double(values[1]),
           x >= 50, y >= 50, x <= 2_000, y <= 2_000 {
            return (x, y)
        }
        if let values = capturesFirst(raw, #"\(([0-9]+(?:\.[0-9]+)?)\s*x\s*([0-9]+(?:\.[0-9]+)?)\)\s*dpi"#),
           values.count == 2, let x = Double(values[0]), let y = Double(values[1]),
           x >= 50, y >= 50, x <= 2_000, y <= 2_000 {
            return (x, y)
        }
        return nil
    }

    private func resolutionPixels(_ raw: String) -> (Int, Int)? {
        guard let values = capturesFirst(raw, #"^(\d+)x(\d+)$"#),
              values.count == 2, let width = Int(values[0]), let height = Int(values[1]),
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private func keyValueBlock(_ raw: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: raw.components(separatedBy: .newlines).compactMap { line in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : (key, value)
        })
    }

    private func uniqueList(_ raw: String, separator: String, filtersUnknown: Bool = false) -> String {
        let values = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && (!filtersUnknown || !["unknown", "(unknown)", "n/a"].contains($0.lowercased())) }
        return orderedUnique(values).joined(separator: separator)
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func join(_ values: [String], separator: String = " / ") -> String {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: separator)
    }

    private func nonempty(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }

    private func firstPositiveInteger(_ values: [String]) -> Int64? {
        values.lazy.compactMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.first { $0 > 0 }
    }

    private func firstNonzeroInteger(_ values: [String]) -> Int64? {
        values.lazy.compactMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.first { $0 != 0 }
    }
}

private enum DeviceInformationProtocolError: Error {
    case invalid(String)
    var englishDiagnostic: String {
        switch self { case .invalid(let detail): return detail }
    }
}

private func parseDeviceInformationResponse(_ output: String) throws -> DeviceInformationSnapshot {
    let lines = output.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard let header = lines.first else {
        throw DeviceInformationProtocolError.invalid("DADB management helper returned no output.")
    }
    if header.hasPrefix("ERROR\t") {
        let encoded = String(header.dropFirst("ERROR\t".count))
        throw DeviceInformationProtocolError.invalid(
            try decodeHelperField(encoded, name: "helper error")
        )
    }
    guard header == "DADB_MANAGEMENT\tDEVICE" else {
        throw DeviceInformationProtocolError.invalid("DADB management helper returned an unexpected response.")
    }

    var fields: [RemoteDeviceField: RemoteDeviceFieldResult] = [:]
    for line in lines.dropFirst() {
        let parts = line.components(separatedBy: "\t")
        guard parts.count == 4, parts[0] == "D" else {
            throw DeviceInformationProtocolError.invalid("DADB management helper returned an invalid device record.")
        }
        guard let field = RemoteDeviceField(rawValue: parts[1]) else {
            throw DeviceInformationProtocolError.invalid(
                "DADB management helper returned unknown device field '\(parts[1])'."
            )
        }
        fields[field] = RemoteDeviceFieldResult(
            value: try decodeOptionalHelperField(parts[2], name: "\(parts[1]) value"),
            error: try decodeOptionalHelperField(parts[3], name: "\(parts[1]) error")
        )
    }
    return DeviceInformationSnapshot(fields: fields)
}

private func decodeOptionalHelperField(_ encoded: String, name: String) throws -> String {
    encoded == "-" ? "" : try decodeHelperField(encoded, name: name)
}

private func decodeHelperField(_ encoded: String, name: String) throws -> String {
    guard let data = Data(base64Encoded: encoded),
          let value = String(data: data, encoding: .utf8) else {
        throw DeviceInformationProtocolError.invalid(
            "DADB management helper returned invalid \(name) data."
        )
    }
    return value
}

private func capture(_ text: String, _ pattern: String) -> String? {
    capturesFirst(text, pattern)?.first
}

private func captures(_ text: String, _ pattern: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return expression.matches(in: text, range: range).compactMap { match in
        guard match.numberOfRanges > 1, let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }
}

private func capturesFirst(_ text: String, _ pattern: String) -> [String]? {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (1..<match.numberOfRanges).compactMap { index in
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}

private struct DisplayValues {
    let resolution: String
    let dpi: String
    let ppi: String
    let screenSize: String
    let currentRate: String
    let supportedRates: String
}

private struct BatteryValues {
    let level: String
    let status: String
    let health: String
    let voltage: String
    let current: String
    let temperature: String
    let cycleCount: String
}

private struct StorageMemoryValues {
    let storage: String
    let memory: String
}

private struct NetworkValues {
    let cellular: String
    let carrier: String
    let pci: String
    let arfcn: String
    let rsrp: String
    let rsrq: String
    let sinr: String
    let ssid: String
    let bssid: String
    let wifiSummary: String
    let interfaces: [DeviceInfoRow]
    let gateway: String
}

private struct DeviceInfoSection: View {
    let group: DeviceInfoGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title).font(.headline).padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).foregroundColor(.secondary)
                        Spacer(minLength: 20)
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    if index != group.rows.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .appCard()
        }
    }
}
