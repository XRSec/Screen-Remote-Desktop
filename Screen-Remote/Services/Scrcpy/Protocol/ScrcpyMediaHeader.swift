import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

enum ScrcpyMediaHeader {
    case session(width: Int, height: Int, clientResized: Bool)
    case media(size: Int, pts: Int64, isConfig: Bool, isKeyFrame: Bool)

    init(data: Data) throws {
        guard data.count == 12 else { throw NativeScrcpyError.invalidProtocol("short media header") }
        let first = data.readUInt64BE(at: 0)
        let tail = Int(data.readUInt32BE(at: 8))
        if first & (UInt64(1) << 63) != 0 {
            self = .session(
                width: Int(data.readUInt32BE(at: 4)),
                height: tail,
                clientResized: data[3] & 1 != 0
            )
        } else {
            self = .media(
                size: tail,
                pts: Int64(first & ((UInt64(1) << 61) - 1)),
                isConfig: first & (UInt64(1) << 62) != 0,
                isKeyFrame: first & (UInt64(1) << 61) != 0
            )
        }
    }
}

extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        self[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func readUInt64BE(at offset: Int) -> UInt64 {
        self[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
