import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

enum NativeVideoCodec: String {
    case h264
    case h265
}

final class ScrcpyVideoToolboxDecoder {
    private let codec: NativeVideoCodec
    private let surface: ScrcpyVideoSurface
    private let hardwareDecodingEnabled: Bool
    private let lock = NSLock()
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?

    init(codec: NativeVideoCodec, surface: ScrcpyVideoSurface, hardwareDecodingEnabled: Bool) {
        self.codec = codec
        self.surface = surface
        self.hardwareDecodingEnabled = hardwareDecodingEnabled
    }

    func configure(annexB: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        let units = splitAnnexBNALUnits(annexB)
        var description: CMFormatDescription?
        let status: OSStatus
        switch codec {
        case .h264:
            guard let sps = units.first(where: { ($0.first ?? 0) & 0x1f == 7 }),
                  let pps = units.first(where: { ($0.first ?? 0) & 0x1f == 8 }) else {
                throw NativeScrcpyError.decoderFailed("H.264 configuration does not contain SPS and PPS")
            }
            status = Self.makeH264Description(sps: sps, pps: pps, output: &description)
        case .h265:
            guard let vps = units.first(where: { (($0.first ?? 0) >> 1) & 0x3f == 32 }),
                  let sps = units.first(where: { (($0.first ?? 0) >> 1) & 0x3f == 33 }),
                  let pps = units.first(where: { (($0.first ?? 0) >> 1) & 0x3f == 34 }) else {
                throw NativeScrcpyError.decoderFailed("H.265 configuration does not contain VPS, SPS, and PPS")
            }
            status = Self.makeH265Description(vps: vps, sps: sps, pps: pps, output: &description)
        }
        guard status == noErr, let description else {
            throw NativeScrcpyError.decoderFailed("format description status \(status)")
        }
        invalidateLocked()
        formatDescription = description
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let refCon, let imageBuffer else { return }
                Unmanaged<ScrcpyVideoToolboxDecoder>.fromOpaque(refCon).takeUnretainedValue().surface.publish(imageBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let specification: [CFString: Any] = hardwareDecodingEnabled
            ? [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true]
            : [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: false,
               kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: false]
        var newSession: VTDecompressionSession?
        let createStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: description,
            decoderSpecification: specification as CFDictionary,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &newSession
        )
        guard createStatus == noErr, let newSession else {
            throw NativeScrcpyError.decoderFailed("session creation status \(createStatus)")
        }
        session = newSession
    }

    func decode(annexB: Data, pts: Int64, isKeyFrame: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let formatDescription, let session else { return }
        let avcc = annexBToAVCC(annexB)
        var blockBuffer: CMBlockBuffer?
        let blockStatus = avcc.withUnsafeBytes { bytes in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: avcc.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avcc.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            ) == noErr
                ? CMBlockBufferReplaceDataBytes(
                    with: bytes.baseAddress!, blockBuffer: blockBuffer!, offsetIntoDestination: 0,
                    dataLength: avcc.count
                ) : -1
        }
        guard blockStatus == noErr, let blockBuffer else {
            throw NativeScrcpyError.decoderFailed("block buffer status \(blockStatus)")
        }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: pts, timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var size = avcc.count
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw NativeScrcpyError.decoderFailed("sample buffer status \(sampleStatus)")
        }
        if !isKeyFrame,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        var flags = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression, ._EnableTemporalProcessing],
            frameRefcon: nil,
            infoFlagsOut: &flags
        )
        guard decodeStatus == noErr else {
            throw NativeScrcpyError.decoderFailed("frame decode status \(decodeStatus)")
        }
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        invalidateLocked()
    }

    private func invalidateLocked() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
    }

    deinit { invalidateLocked() }

    private static func makeH264Description(
        sps: Data,
        pps: Data,
        output: inout CMFormatDescription?
    ) -> OSStatus {
        withParameterSets([sps, pps]) { pointers, sizes in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers.baseAddress!,
                parameterSetSizes: sizes.baseAddress!,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &output
            )
        }
    }

    private static func makeH265Description(
        vps: Data,
        sps: Data,
        pps: Data,
        output: inout CMFormatDescription?
    ) -> OSStatus {
        withParameterSets([vps, sps, pps]) { pointers, sizes in
            CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers.baseAddress!,
                parameterSetSizes: sizes.baseAddress!,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &output
            )
        }
    }

    private static func withParameterSets(
        _ parameterSets: [Data],
        body: (UnsafeBufferPointer<UnsafePointer<UInt8>>, UnsafeBufferPointer<Int>) -> OSStatus
    ) -> OSStatus {
        func recurse(
            _ index: Int,
            pointers: [UnsafePointer<UInt8>],
            sizes: [Int]
        ) -> OSStatus {
            guard index < parameterSets.count else {
                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        body(pointerBuffer, sizeBuffer)
                    }
                }
            }
            return parameterSets[index].withUnsafeBytes { bytes in
                guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else {
                    return OSStatus(paramErr)
                }
                return recurse(
                    index + 1,
                    pointers: pointers + [base],
                    sizes: sizes + [parameterSets[index].count]
                )
            }
        }
        return recurse(0, pointers: [], sizes: [])
    }
}
