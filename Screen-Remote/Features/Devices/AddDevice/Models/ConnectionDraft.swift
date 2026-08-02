import AppKit
import AudioToolbox
import SwiftUI
import VideoToolbox

struct ConnectionDraft: Identifiable {
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

struct ConnectionDiscoveryTarget: Identifiable {
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
