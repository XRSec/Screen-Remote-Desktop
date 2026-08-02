import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

func splitAnnexBNALUnits(_ data: Data) -> [Data] {
    let bytes = [UInt8](data)
    var starts: [(index: Int, length: Int)] = []
    var index = 0
    while index + 3 < bytes.count {
        if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
            starts.append((index, 3)); index += 3
        } else if index + 4 <= bytes.count,
                  bytes[index] == 0, bytes[index + 1] == 0,
                  bytes[index + 2] == 0, bytes[index + 3] == 1 {
            starts.append((index, 4)); index += 4
        } else {
            index += 1
        }
    }
    return starts.enumerated().compactMap { offset, start in
        let begin = start.index + start.length
        let end = offset + 1 < starts.count ? starts[offset + 1].index : bytes.count
        guard begin < end else { return nil }
        return Data(bytes[begin..<end])
    }
}

func annexBToAVCC(_ data: Data) -> Data {
    let units = splitAnnexBNALUnits(data)
    guard !units.isEmpty else { return data }
    var output = Data()
    for unit in units {
        var size = UInt32(unit.count).bigEndian
        withUnsafeBytes(of: &size) { output.append(contentsOf: $0) }
        output.append(unit)
    }
    return output
}
