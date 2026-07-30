import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

final class ScrcpyVideoSurface: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var pixelSize = CGSize.zero

    private let context = CIContext(options: [.cacheIntermediates: false])

    func publish(_ pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.image = image
            self?.pixelSize = CGSize(width: image.width, height: image.height)
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.image = nil
            self?.pixelSize = .zero
        }
    }
}

enum NativeScrcpyError: LocalizedError {
    case serverUnavailable(String)
    case commandFailed(String)
    case invalidForwardPort(String)
    case socketFailed(String)
    case invalidProtocol(String)
    case unsupportedCodec(String)
    case decoderFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverUnavailable(let detail): "scrcpy-server is unavailable: \(detail)"
        case .commandFailed(let detail): "scrcpy command failed: \(detail)"
        case .invalidForwardPort(let detail): "ADB returned an invalid forward port: \(detail)"
        case .socketFailed(let detail): "scrcpy socket failed: \(detail)"
        case .invalidProtocol(let detail): "Invalid scrcpy protocol data: \(detail)"
        case .unsupportedCodec(let codec): "Unsupported native video codec: \(codec)"
        case .decoderFailed(let detail): "VideoToolbox decoder failed: \(detail)"
        }
    }
}

/// Owns the official scrcpy 4.1 server lifecycle and its ordered media/control sockets.
/// scrcpy-mask is only a behavioral reference; no scrcpy-mask server extensions are used.
final class NativeScrcpySession {
    static let serverVersion = "4.1"
    static let serverSHA256 = "deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae"

    let surface: ScrcpyVideoSurface

    private let adbPath: String
    private let serial: String
    private let options: ScrcpyDeviceOptions
    private let queue = DispatchQueue(label: "com.screenremote.scrcpy.native", qos: .userInitiated)
    private let stateLock = NSLock()
    private var stopped = false
    private var serverProcess: Process?
    private var socketDescriptors: [Int32] = []
    private var forwardedPort: UInt16?
    private var decoder: ScrcpyH264Decoder?

    init(
        adbPath: String,
        serial: String,
        options: ScrcpyDeviceOptions,
        surface: ScrcpyVideoSurface
    ) {
        self.adbPath = adbPath
        self.serial = serial
        self.options = options
        self.surface = surface
    }

    func start(
        log: @escaping (String) -> Void,
        ready: @escaping (String) -> Void,
        stopped: @escaping (Error?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let serverURL = try ScrcpyServerAsset.resolve(log: log)
                try self.ensureRunning()
                try self.deploy(serverURL, log: log)
                let scid = UInt32.random(in: 1...0x7fff_ffff)
                let socketName = String(format: "scrcpy_%08x", scid)
                let port = try self.createForward(socketName: socketName, log: log)
                try self.launchServer(scid: scid, log: log)

                // Socket roles are assigned by accept order. Never parallelize these calls.
                let video = try self.connectFirstSocket(port: port)
                try self.registerSocket(video)
                let audio: Int32?
                if self.options.enableAudio {
                    let socket = try self.connectSocket(port: port)
                    try self.registerSocket(socket)
                    audio = socket
                } else {
                    audio = nil
                }
                let control = try self.connectSocket(port: port)
                try self.registerSocket(control)

                let deviceName = try self.readDeviceMetadata(from: video)
                try self.removeForward(log: log)
                ready(deviceName)

                if let audio {
                    self.drainAudio(socket: audio, log: log)
                }
                try self.consumeVideo(socket: video, log: log)
                if !self.isStopped {
                    throw NativeScrcpyError.socketFailed("video stream closed")
                }
                stopped(nil)
            } catch {
                let wasStopped = self.isStopped
                self.stop(log: log)
                stopped(wasStopped ? nil : error)
            }
        }
    }

    func stop(log: ((String) -> Void)? = nil) {
        stateLock.lock()
        let alreadyStopped = stopped
        stopped = true
        let sockets = socketDescriptors
        socketDescriptors.removeAll()
        let process = serverProcess
        serverProcess = nil
        stateLock.unlock()
        guard !alreadyStopped else { return }

        for descriptor in sockets {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        if let process, process.isRunning {
            process.terminate()
        }
        try? removeForward(log: log ?? { _ in })
        decoder?.invalidate()
        decoder = nil
        surface.clear()
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }

    private func ensureRunning() throws {
        if isStopped { throw CancellationError() }
    }

    private func registerSocket(_ socket: Int32) throws {
        stateLock.lock()
        if stopped {
            stateLock.unlock()
            Darwin.close(socket)
            throw CancellationError()
        }
        socketDescriptors.append(socket)
        stateLock.unlock()
    }

    private func deploy(_ serverURL: URL, log: @escaping (String) -> Void) throws {
        log("Deploying official scrcpy-server v\(Self.serverVersion)")
        let result = try NativeProcess.run(
            adbPath,
            ["-s", serial, "push", serverURL.path, ScrcpyServerAsset.remotePath]
        )
        guard result.status == 0 else {
            throw NativeScrcpyError.commandFailed(result.failureDetail)
        }
        log("scrcpy-server deployment completed")
    }

    private func createForward(socketName: String, log: @escaping (String) -> Void) throws -> UInt16 {
        let result = try NativeProcess.run(
            adbPath,
            ["-s", serial, "forward", "tcp:0", "localabstract:\(socketName)"]
        )
        guard result.status == 0 else {
            throw NativeScrcpyError.commandFailed(result.failureDetail)
        }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(value), port > 0 else {
            throw NativeScrcpyError.invalidForwardPort(value)
        }
        forwardedPort = port
        log("ADB forward ready: localPort=\(port), socket=\(socketName)")
        return port
    }

    private func removeForward(log: @escaping (String) -> Void) throws {
        guard let port = forwardedPort else { return }
        forwardedPort = nil
        let result = try NativeProcess.run(adbPath, ["-s", serial, "forward", "--remove", "tcp:\(port)"])
        if result.status == 0 {
            log("ADB forward removed: localPort=\(port)")
        } else {
            log("ADB forward removal failed: localPort=\(port), \(result.failureDetail)")
        }
    }

    private func launchServer(scid: UInt32, log: @escaping (String) -> Void) throws {
        var parameters = [
            String(format: "scid=%08x", scid),
            "log_level=info",
            "video_codec=h264",
            "video_bit_rate=\(parseBitrate(options.videoBitrate, fallback: 4_000_000))",
            "max_fps=\(max(options.maxFPS, 1))",
            "tunnel_forward=true",
            "send_device_meta=true",
            "send_stream_meta=true",
            "send_frame_meta=true",
            "send_dummy_byte=true",
            "downsize_on_error=false",
            "stay_awake=\(options.keepDeviceAwake)",
            "power_off_on_close=\(options.powerOffOnClose && options.cleanupOnDisconnect)"
        ]
        if options.maxSize > 0 { parameters.append("max_size=\(options.maxSize)") }
        if !options.clipboardSync { parameters.append("clipboard_autosync=false") }
        if !options.cleanupOnDisconnect { parameters.append("cleanup=false") }
        if options.ignoreVideoEncoderConstraints { parameters.append("ignore_video_encoder_constraints=true") }
        if options.enableAudio {
            parameters += [
                "audio_codec=opus",
                "audio_bit_rate=\(parseBitrate(options.audioBitrate, fallback: 128_000))"
            ]
        } else {
            parameters.append("audio=false")
        }
        if options.newDisplayEnabled {
            var display = ""
            if options.newDisplayWidth > 0, options.newDisplayHeight > 0 {
                display = "\(options.newDisplayWidth)x\(options.newDisplayHeight)"
                if options.newDisplayDPI > 0 { display += "/\(options.newDisplayDPI)" }
            }
            parameters.append("new_display=\(display)")
            if !options.virtualDisplaySystemDecorations { parameters.append("vd_system_decorations=false") }
            if options.preserveVirtualDisplayContent { parameters.append("vd_destroy_content=false") }
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = [
            "-s", serial, "shell",
            "CLASSPATH=\(ScrcpyServerAsset.remotePath)",
            "app_process", "/", "com.genymobile.scrcpy.Server", Self.serverVersion
        ] + parameters
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                log("scrcpy-server: \(line)")
            }
        }
        try process.run()
        stateLock.lock()
        serverProcess = process
        stateLock.unlock()
        log("scrcpy-server launched: scid=\(String(format: "%08x", scid)), pid=\(process.processIdentifier)")
    }

    private func connectFirstSocket(port: UInt16) throws -> Int32 {
        let deadline = Date().addingTimeInterval(10)
        var lastError = "server socket not ready"
        while Date() < deadline {
            try ensureRunning()
            do {
                let socket = try connectSocket(port: port)
                let dummy = try readExact(socket, count: 1)
                guard dummy.first == 0 else {
                    Darwin.close(socket)
                    throw NativeScrcpyError.invalidProtocol("unexpected dummy byte")
                }
                return socket
            } catch {
                lastError = error.localizedDescription
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        throw NativeScrcpyError.socketFailed(lastError)
    }

    private func connectSocket(port: UInt16) throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw NativeScrcpyError.socketFailed(lastPOSIXError()) }
        var yes: Int32 = 1
        setsockopt(descriptor, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout.size(ofValue: timeout))
        )
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let detail = lastPOSIXError()
            Darwin.close(descriptor)
            throw NativeScrcpyError.socketFailed(detail)
        }
        return descriptor
    }

    private func readDeviceMetadata(from socket: Int32) throws -> String {
        let data = try readExact(socket, count: 64)
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }

    private func consumeVideo(socket: Int32, log: @escaping (String) -> Void) throws {
        let codecData = try readExact(socket, count: 4)
        let codec = String(decoding: codecData.filter { $0 != 0 }, as: UTF8.self)
        guard codec == "h264" else { throw NativeScrcpyError.unsupportedCodec(codec) }
        let initialHeader = try readExact(socket, count: 12)
        let initial = try ScrcpyMediaHeader(data: initialHeader)
        guard case .session(let width, let height, _) = initial else {
            throw NativeScrcpyError.invalidProtocol("missing initial video session header")
        }
        log("Native video stream ready: codec=h264, size=\(width)x\(height)")

        let decoder = ScrcpyH264Decoder(surface: surface)
        self.decoder = decoder
        while !isStopped {
            let header = try ScrcpyMediaHeader(data: readExact(socket, count: 12))
            switch header {
            case .session(let width, let height, let clientResized):
                log("Video session changed: size=\(width)x\(height), clientResized=\(clientResized)")
            case .media(let size, let pts, let isConfig, let isKeyFrame):
                guard size > 0, size <= 64 * 1024 * 1024 else {
                    throw NativeScrcpyError.invalidProtocol("invalid video packet size \(size)")
                }
                let data = try readExact(socket, count: size)
                if isConfig {
                    try decoder.configure(annexB: data)
                } else {
                    try decoder.decode(annexB: data, pts: pts, isKeyFrame: isKeyFrame)
                }
            }
        }
    }

    private func drainAudio(socket: Int32, log: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let codecData = try self.readExact(socket, count: 4)
                let codec = String(decoding: codecData.filter { $0 != 0 }, as: UTF8.self)
                log("Audio socket ready: codec=\(codec), playback=pending")
                while !self.isStopped {
                    let header = try ScrcpyMediaHeader(data: self.readExact(socket, count: 12))
                    guard case .media(let size, _, _, _) = header, size <= 16 * 1024 * 1024 else {
                        throw NativeScrcpyError.invalidProtocol("invalid audio packet")
                    }
                    _ = try self.readExact(socket, count: size)
                }
            } catch {
                if !self.isStopped { log("Audio stream ended: \(error.localizedDescription)") }
            }
        }
    }

    private func readExact(_ socket: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            while offset < count {
                try ensureRunning()
                let received = Darwin.recv(socket, base.advanced(by: offset), count - offset, 0)
                if received == 0 { throw NativeScrcpyError.socketFailed("connection closed") }
                if received < 0 {
                    if errno == EINTR { continue }
                    throw NativeScrcpyError.socketFailed(lastPOSIXError())
                }
                offset += received
            }
        }
        return data
    }
}

private enum ScrcpyServerAsset {
    static let remotePath = "/data/local/tmp/scrcpy-server.jar"

    static func resolve(log: @escaping (String) -> Void) throws -> URL {
        guard let bundled = Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar") else {
            throw NativeScrcpyError.serverUnavailable(
                "the macOS application bundle does not contain scrcpy-server.jar; run scripts/prepare-scrcpy-server.sh and rebuild"
            )
        }
        guard verified(bundled) else {
            throw NativeScrcpyError.serverUnavailable("the bundled scrcpy-server.jar failed SHA-256 verification")
        }
        log("Using verified bundled scrcpy-server v\(NativeScrcpySession.serverVersion)")
        return bundled
    }

    private static func verified(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return sha256(data) == NativeScrcpySession.serverSHA256
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum ScrcpyMediaHeader {
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

private final class ScrcpyH264Decoder {
    private let surface: ScrcpyVideoSurface
    private let lock = NSLock()
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?

    init(surface: ScrcpyVideoSurface) {
        self.surface = surface
    }

    func configure(annexB: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        let units = splitAnnexBNALUnits(annexB)
        guard let sps = units.first(where: { ($0.first ?? 0) & 0x1f == 7 }),
              let pps = units.first(where: { ($0.first ?? 0) & 0x1f == 8 }) else {
            throw NativeScrcpyError.decoderFailed("H.264 configuration does not contain SPS and PPS")
        }
        var description: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                guard let spsBase = spsBytes.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBase = ppsBytes.bindMemory(to: UInt8.self).baseAddress else {
                    return OSStatus(paramErr)
                }
                let pointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                let sizes = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
        }
        guard status == noErr, let description else {
            throw NativeScrcpyError.decoderFailed("format description status \(status)")
        }
        invalidateLocked()
        formatDescription = description
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let refCon, let imageBuffer else { return }
                Unmanaged<ScrcpyH264Decoder>.fromOpaque(refCon).takeUnretainedValue().surface.publish(imageBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let specification: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]
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
}

private struct NativeProcessResult {
    let status: Int32
    let output: String
    let error: String

    var failureDetail: String {
        let stderr = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        let stdout = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? "exit status \(status)" : stdout
    }
}

private enum NativeProcess {
    static func run(_ executable: String, _ arguments: [String]) throws -> NativeProcessResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return NativeProcessResult(
            status: process.terminationStatus,
            output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            error: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}

private func parseBitrate(_ value: String, fallback: Int) -> Int {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let last = normalized.last else { return fallback }
    let multiplier: Double
    let number: String
    switch last {
    case "K": multiplier = 1_000; number = String(normalized.dropLast())
    case "M": multiplier = 1_000_000; number = String(normalized.dropLast())
    case "G": multiplier = 1_000_000_000; number = String(normalized.dropLast())
    default: multiplier = 1; number = normalized
    }
    guard let parsed = Double(number), parsed > 0 else { return fallback }
    return Int(min(parsed * multiplier, Double(Int32.max)))
}

private func splitAnnexBNALUnits(_ data: Data) -> [Data] {
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

private func annexBToAVCC(_ data: Data) -> Data {
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

private func lastPOSIXError() -> String {
    String(cString: strerror(errno))
}

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        self[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func readUInt64BE(at offset: Int) -> UInt64 {
        self[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
