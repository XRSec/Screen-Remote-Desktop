import AppKit
import Combine
import SwiftUI

struct Device: Identifiable {
    let id: UUID
    let name: String
    let model: String
    let systemVersion: String
    let battery: Int
    let accent: Color
    var isConnected: Bool
    var groupIDs: Set<String>
    let connections: [DeviceConnection]
    var scrcpyOptions: ScrcpyDeviceOptions

    init(
        id: UUID = UUID(), name: String, model: String, systemVersion: String,
        battery: Int, accent: Color, isConnected: Bool, groupIDs: Set<String> = [],
        connections: [DeviceConnection], scrcpyOptions: ScrcpyDeviceOptions
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.systemVersion = systemVersion
        self.battery = battery
        self.accent = accent
        self.isConnected = isConnected
        self.groupIDs = groupIDs
        self.connections = connections
        self.scrcpyOptions = scrcpyOptions
    }

    var primaryConnection: DeviceConnection? {
        connections.min { $0.priority < $1.priority }
    }
}

struct DeviceGroup: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var symbol: String
    var parentID: String? = nil

    static let allID = "all_devices"
}

struct DeviceGroupTreeNode: Identifiable {
    let group: DeviceGroup
    let children: [DeviceGroupTreeNode]?

    var id: String { group.id }
}

struct FlattenedDeviceGroup: Identifiable {
    let group: DeviceGroup
    let depth: Int

    var id: String { group.id }
}

enum DeviceTransport: String, CaseIterable, Identifiable, Codable {
    case tcp = "TCP/IP"
    case usb = "USB"
    case mdns = "mDNS"

    var id: String { rawValue }
}

struct DeviceConnection: Identifiable, Codable {
    let id: UUID
    var transport: DeviceTransport
    var host: String = ""
    var port: Int = 5555
    var serial: String = ""
    var priority: Int = 0

    init(
        id: UUID = UUID(), transport: DeviceTransport, host: String = "", port: Int = 5555,
        serial: String = "", priority: Int = 0
    ) {
        self.id = id
        self.transport = transport
        self.host = host
        self.port = port
        self.serial = serial
        self.priority = priority
    }

    var displayAddress: String {
        switch transport {
        case .tcp: host.isEmpty ? String.localizedKey("deviceConnectionAddressNotConfigured") : "\(host):\(port)"
        case .usb: serial.isEmpty ? String.localizedKey("deviceConnectionSerialNotConfigured") : serial
        case .mdns: host.isEmpty ? String.localizedKey("deviceConnectionServiceNotConfigured") : host
        }
    }
}
