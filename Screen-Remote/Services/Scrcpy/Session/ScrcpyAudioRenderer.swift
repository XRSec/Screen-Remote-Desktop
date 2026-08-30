import AudioToolbox
import AVFoundation
import Foundation

// AudioConverter packet plumbing is adapted from droidMirroring-mac's
// Apache-2.0-licensed AudioRenderer (Copyright 2026 matyle and macDros contributors).
final class ScrcpyAudioRenderer {
    private let codec: String
    private let decoderIdentifier: String?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var gain: Float
    private let log: (String) -> Void
    private let lock = NSLock()
    private var started = false
    private var loggedPacketCount = 0
    private var converter: AudioConverterRef?
    private var inputFormat: AudioStreamBasicDescription
    private var outputFormat: AudioStreamBasicDescription
    private var magicCookie: Data?
    private var pendingPacket: Data?
    private var pendingPacketConsumed = false
    private var packetStorage: UnsafeMutableRawBufferPointer?
    private var packetDescription = AudioStreamPacketDescription()

    init(
        codec: String,
        decoderIdentifier: String?,
        volume: Double,
        log: @escaping (String) -> Void
    ) throws {
        self.codec = codec
        self.decoderIdentifier = decoderIdentifier
        self.inputFormat = Self.makeInputFormat(codec: codec)
        self.outputFormat = Self.makeOutputFormat()
        self.log = log
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ) else {
            throw NativeScrcpyError.audioFailed("audio output format creation failed")
        }
        self.format = format
        self.gain = Float(min(max(volume, 1), 3))
        player.volume = 1
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        try engine.start()
        player.volume = gain
        player.play()
        started = true
        log(
            "Core Audio playback started: engine=\(engine.isRunning), " +
                "player=\(player.isPlaying), gain=\(gain)"
        )
    }

    func enqueue(_ packet: Data, isConfig: Bool, pts: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        guard started else { return }
        if isConfig {
            magicCookie = try Self.makeMagicCookie(codec: codec, config: packet)
            // Opus is fixed at 48 kHz with 960 frames per packet in scrcpy's
            // stream contract. Core Audio's FormatInfo query accepts OpusHead,
            // but reports mFramesPerPacket as 0. Replacing our explicit ASBD
            // with that result makes AudioConverter repeatedly return zero
            // decoded frames without an error, so keep the known-good Opus
            // input format and use OpusHead only as the decoder magic cookie.
            if let magicCookie, codec != "opus" {
                var resolvedInput = inputFormat
                var resolvedSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                let status = magicCookie.withUnsafeBytes { bytes -> OSStatus in
                    AudioFormatGetProperty(
                        kAudioFormatProperty_FormatInfo,
                        UInt32(magicCookie.count),
                        bytes.baseAddress,
                        &resolvedSize,
                        &resolvedInput
                    )
                }
                guard status == noErr else {
                    throw NativeScrcpyError.audioFailed(
                        "cannot parse \(codec) configuration: status \(status)"
                    )
                }
                inputFormat = resolvedInput
            }
            log(
                "Audio configuration applied: codec=\(codec), bytes=\(packet.count), " +
                    "framesPerPacket=\(inputFormat.mFramesPerPacket)"
            )
            resetConverter()
            return
        }
        if codec == "raw" {
            try enqueueRaw(packet)
        } else {
            try enqueueCompressed(packet, pts: pts)
        }
    }

    private func enqueueRaw(_ packet: Data) throws {
        let bytesPerFrame = MemoryLayout<Int16>.size * 2
        guard packet.count.isMultiple(of: bytesPerFrame) else {
            throw NativeScrcpyError.invalidProtocol("unaligned RAW audio packet size \(packet.count)")
        }
        let frameCount = AVAudioFrameCount(packet.count / bytesPerFrame)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            throw NativeScrcpyError.audioFailed("RAW audio buffer allocation failed")
        }
        packet.withUnsafeBytes { source in
            let samples = source.bindMemory(to: Int16.self)
            for frame in 0..<Int(frameCount) {
                let left = Float(Int16(littleEndian: samples[frame * 2])) / 32_768 * gain
                let right = Float(Int16(littleEndian: samples[frame * 2 + 1])) / 32_768 * gain
                channels[0][frame] = min(max(left, -1), 1)
                channels[1][frame] = min(max(right, -1), 1)
            }
        }
        buffer.frameLength = frameCount
        logDecodedPacketIfNeeded(packetBytes: packet.count, buffer: buffer)
        player.scheduleBuffer(buffer)
    }

    private func enqueueCompressed(_ packet: Data, pts: Int64) throws {
        if converter == nil { try makeConverter() }
        guard let converter else { return }
        pendingPacket = packet
        pendingPacketConsumed = false

        let maximumFrames: AVAudioFrameCount = 5_760
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrames),
              let channels = buffer.floatChannelData else {
            throw NativeScrcpyError.audioFailed("decoded audio buffer allocation failed")
        }
        let bytesPerChannel = maximumFrames * AVAudioFrameCount(MemoryLayout<Float32>.size)
        let audioBuffers = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(audioBuffers.unsafeMutablePointer) }
        for channel in 0..<2 {
            audioBuffers[channel] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: bytesPerChannel,
                mData: UnsafeMutableRawPointer(channels[channel])
            )
        }

        // A scrcpy audio media packet is one encoded codec packet. Requesting
        // the full 120 ms Opus maximum (5,760 frames) makes AudioConverter ask
        // the callback for several input packets during this single call. Our
        // callback intentionally exposes only the current scrcpy packet, so the
        // converter may consume it and return zero output while waiting for
        // more. Ask for the codec packet duration instead; the 5,760-frame
        // allocation remains available for genuinely variable-duration codecs.
        var frameCount = inputFormat.mFramesPerPacket > 0
            ? min(inputFormat.mFramesPerPacket, UInt32(maximumFrames))
            : UInt32(maximumFrames)
        let status = AudioConverterFillComplexBuffer(
            converter,
            scrcpyAudioInputCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &frameCount,
            audioBuffers.unsafeMutablePointer,
            nil
        )
        guard status == noErr else {
            throw NativeScrcpyError.audioFailed(
                "\(codec) decoder failed with status \(status) at pts \(pts)"
            )
        }
        guard frameCount > 0 else {
            if loggedPacketCount < 3 {
                log(
                    "Decoded audio packet: codec=\(codec), bytes=\(packet.count), " +
                        "frames=0, engine=\(engine.isRunning), player=\(player.isPlaying)"
                )
                loggedPacketCount += 1
            }
            return
        }
        if gain != 1 {
            for channel in 0..<2 {
                for frame in 0..<Int(frameCount) {
                    channels[channel][frame] = min(max(channels[channel][frame] * gain, -1), 1)
                }
            }
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        logDecodedPacketIfNeeded(packetBytes: packet.count, buffer: buffer)
        player.scheduleBuffer(buffer)
    }

    private func logDecodedPacketIfNeeded(packetBytes: Int, buffer: AVAudioPCMBuffer) {
        guard loggedPacketCount < 3 else { return }
        var peak: Float = 0
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(channels[channel][frame]))
                }
            }
        }
        log(
            "Decoded audio packet: codec=\(codec), bytes=\(packetBytes), " +
                "frames=\(buffer.frameLength), peak=\(peak), " +
                "engine=\(engine.isRunning), player=\(player.isPlaying)"
        )
        loggedPacketCount += 1
    }

    private func makeConverter() throws {
        var created: AudioConverterRef?
        var input = inputFormat
        var output = outputFormat
        let selected = decoderIdentifier.flatMap(coreAudioDecoderCapability(identifier:))?.componentDescription
        let status: OSStatus
        if var selected {
            status = AudioConverterNewSpecific(&input, &output, 1, &selected, &created)
        } else {
            status = AudioConverterNew(&input, &output, &created)
        }
        guard status == noErr, let created else {
            throw NativeScrcpyError.audioFailed("cannot create \(codec) decoder: status \(status)")
        }
        if let magicCookie, !magicCookie.isEmpty {
            let cookieStatus = magicCookie.withUnsafeBytes { bytes -> OSStatus in
                guard let address = bytes.baseAddress else { return kAudio_ParamError }
                return AudioConverterSetProperty(
                    created,
                    kAudioConverterDecompressionMagicCookie,
                    UInt32(magicCookie.count),
                    address
                )
            }
            guard cookieStatus == noErr else {
                AudioConverterDispose(created)
                throw NativeScrcpyError.audioFailed(
                    "cannot configure \(codec) decoder: status \(cookieStatus)"
                )
            }
        }
        converter = created
    }

    fileprivate func provideInput(
        packetCount: UnsafeMutablePointer<UInt32>,
        audioData: UnsafeMutablePointer<AudioBufferList>,
        packetDescriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?
    ) -> OSStatus {
        guard !pendingPacketConsumed, let pendingPacket else {
            packetCount.pointee = 0
            return noErr
        }
        packetStorage?.deallocate()
        let storage = UnsafeMutableRawPointer.allocate(byteCount: pendingPacket.count, alignment: 1)
        pendingPacket.copyBytes(to: storage.assumingMemoryBound(to: UInt8.self), count: pendingPacket.count)
        packetStorage = UnsafeMutableRawBufferPointer(start: storage, count: pendingPacket.count)

        let buffers = UnsafeMutableAudioBufferListPointer(audioData)
        buffers.unsafeMutablePointer.pointee.mNumberBuffers = 1
        buffers[0] = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: UInt32(pendingPacket.count),
            mData: storage
        )
        packetCount.pointee = 1
        if let packetDescriptions {
            packetDescription = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: inputFormat.mFramesPerPacket,
                mDataByteSize: UInt32(pendingPacket.count)
            )
            withUnsafeMutablePointer(to: &packetDescription) {
                packetDescriptions.pointee = $0
            }
        }
        pendingPacketConsumed = true
        return noErr
    }

    private func resetConverter() {
        if let converter { AudioConverterDispose(converter) }
        converter = nil
    }

    private static func makeInputFormat(codec: String) -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        format.mSampleRate = 48_000
        format.mChannelsPerFrame = 2
        switch codec {
        case "opus":
            format.mFormatID = kAudioFormatOpus
            format.mFramesPerPacket = 960
        case "aac":
            format.mFormatID = kAudioFormatMPEG4AAC
            format.mFramesPerPacket = 1_024
        case "flac":
            format.mFormatID = kAudioFormatFLAC
        default:
            format.mFormatID = kAudioFormatLinearPCM
            format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
            format.mFramesPerPacket = 1
            format.mBitsPerChannel = 16
            format.mBytesPerFrame = 4
            format.mBytesPerPacket = 4
        }
        return format
    }

    private static func makeOutputFormat() -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        format.mSampleRate = 48_000
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked |
            kAudioFormatFlagIsNonInterleaved
        format.mFramesPerPacket = 1
        format.mChannelsPerFrame = 2
        format.mBitsPerChannel = 32
        format.mBytesPerFrame = 4
        format.mBytesPerPacket = 4
        return format
    }

    private static func makeMagicCookie(codec: String, config: Data) throws -> Data? {
        switch codec {
        case "opus":
            guard config.count >= 19,
                  config.prefix(8) == Data("OpusHead".utf8),
                  config[9] > 0 else {
                throw NativeScrcpyError.audioFailed("invalid OpusHead configuration")
            }
            return config
        case "aac":
            guard config.count >= 2 else {
                throw NativeScrcpyError.audioFailed("invalid AAC AudioSpecificConfig")
            }
            let decoderConfigLength = 18 + config.count
            let esDescriptorLength = 14 + decoderConfigLength
            var cookie = Data([0x03])
            cookie.append(descriptorLength(esDescriptorLength))
            cookie.append(contentsOf: [0x00, 0x01, 0x00])
            cookie.append(0x04)
            cookie.append(descriptorLength(decoderConfigLength))
            cookie.append(contentsOf: [0x40, 0x15, 0x00, 0x00, 0x00])
            cookie.append(contentsOf: [0x00, 0x01, 0xF4, 0x00])
            cookie.append(contentsOf: [0x00, 0x01, 0xF4, 0x00])
            cookie.append(0x05)
            cookie.append(descriptorLength(config.count))
            cookie.append(config)
            cookie.append(contentsOf: [0x06, 0x80, 0x80, 0x80, 0x01, 0x02])
            return cookie
        case "flac":
            if config.count >= 50,
               config.subdata(in: 4..<8) == Data("dfLa".utf8) {
                return config
            }
            let streamInfo: Data
            if config.count >= 42, config.prefix(4) == Data("fLaC".utf8) {
                streamInfo = config.subdata(in: 8..<42)
            } else if config.count == 34 {
                streamInfo = config
            } else if config.count >= 38,
                      config[0] & 0x7f == 0,
                      Int(config[1]) << 16 | Int(config[2]) << 8 | Int(config[3]) == 34 {
                streamInfo = config.subdata(in: 4..<38)
            } else {
                throw NativeScrcpyError.audioFailed("invalid FLAC STREAMINFO configuration")
            }
            var cookie = Data([0x00, 0x00, 0x00, 0x32])
            cookie.append(Data("dfLa".utf8))
            cookie.append(Data("fLaC".utf8))
            cookie.append(contentsOf: [0x80, 0x00, 0x00, 0x22])
            cookie.append(streamInfo)
            return cookie
        case "raw":
            return nil
        default:
            throw NativeScrcpyError.audioFailed("unsupported audio configuration codec \(codec)")
        }
    }

    private static func descriptorLength(_ length: Int) -> Data {
        Data([
            UInt8((length >> 21) & 0x7f) | 0x80,
            UInt8((length >> 14) & 0x7f) | 0x80,
            UInt8((length >> 7) & 0x7f) | 0x80,
            UInt8(length & 0x7f)
        ])
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard started else { return }
        player.stop()
        engine.stop()
        resetConverter()
        packetStorage?.deallocate()
        packetStorage = nil
        started = false
    }

    func setGain(_ volume: Double) {
        let clamped = Float(min(max(volume, 1), 3))
        lock.lock()
        gain = clamped
        player.volume = clamped
        lock.unlock()
    }

    deinit { stop() }
}

private func scrcpyAudioInputCallback(
    _ converter: AudioConverterRef,
    _ packetCount: UnsafeMutablePointer<UInt32>,
    _ audioData: UnsafeMutablePointer<AudioBufferList>,
    _ packetDescriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context else {
        packetCount.pointee = 0
        return noErr
    }
    return Unmanaged<ScrcpyAudioRenderer>.fromOpaque(context).takeUnretainedValue().provideInput(
        packetCount: packetCount,
        audioData: audioData,
        packetDescriptions: packetDescriptions
    )
}
