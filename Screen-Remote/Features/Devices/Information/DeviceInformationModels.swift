import Foundation
import SwiftUI

private let deviceInfoColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let deviceInfoGridMaxWidth: CGFloat = 914

enum RemoteDeviceField: String, CaseIterable {
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

struct RemoteDeviceFieldResult {
    let value: String
    let error: String
}

struct DeviceInformationSnapshot {
    let fields: [RemoteDeviceField: RemoteDeviceFieldResult]

    func value(_ field: RemoteDeviceField) -> String {
        fields[field]?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct DeviceInfoRow: Identifiable {
    let label: LocalizedStringKey
    let value: String
    var id: String { "\(label)-\(value)" }
}

struct DeviceInfoGroup: Identifiable {
    let title: LocalizedStringKey
    let rows: [DeviceInfoRow]
    var id: String { "\(title)" }
}
