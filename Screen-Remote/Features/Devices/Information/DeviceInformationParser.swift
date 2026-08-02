import Foundation
import SwiftUI

private let deviceInfoColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let deviceInfoGridMaxWidth: CGFloat = 914

enum DeviceInformationProtocolError: Error {
    case invalid(String)
    var englishDiagnostic: String {
        switch self { case .invalid(let detail): return detail }
    }
}

func parseDeviceInformationResponse(_ output: String) throws -> DeviceInformationSnapshot {
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

func decodeOptionalHelperField(_ encoded: String, name: String) throws -> String {
    encoded == "-" ? "" : try decodeHelperField(encoded, name: name)
}

func decodeHelperField(_ encoded: String, name: String) throws -> String {
    guard let data = Data(base64Encoded: encoded),
          let value = String(data: data, encoding: .utf8) else {
        throw DeviceInformationProtocolError.invalid(
            "DADB management helper returned invalid \(name) data."
        )
    }
    return value
}

func capture(_ text: String, _ pattern: String) -> String? {
    capturesFirst(text, pattern)?.first
}

func captures(_ text: String, _ pattern: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return expression.matches(in: text, range: range).compactMap { match in
        guard match.numberOfRanges > 1, let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }
}

func capturesFirst(_ text: String, _ pattern: String) -> [String]? {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (1..<match.numberOfRanges).compactMap { index in
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}

struct DisplayValues {
    let resolution: String
    let dpi: String
    let ppi: String
    let screenSize: String
    let currentRate: String
    let supportedRates: String
}

struct BatteryValues {
    let level: String
    let status: String
    let health: String
    let voltage: String
    let current: String
    let temperature: String
    let cycleCount: String
}

struct StorageMemoryValues {
    let storage: String
    let memory: String
}

struct NetworkValues {
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
