import AppKit
import AudioToolbox
import AVFoundation
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

enum NativeScrcpyError: LocalizedError {
    case serverUnavailable(String)
    case commandFailed(String)
    case invalidForwardPort(String)
    case socketFailed(String)
    case invalidProtocol(String)
    case unsupportedCodec(String)
    case decoderFailed(String)
    case audioFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverUnavailable(let detail): "scrcpy-server is unavailable: \(detail)"
        case .commandFailed(let detail): "scrcpy command failed: \(detail)"
        case .invalidForwardPort(let detail): "ADB returned an invalid forward port: \(detail)"
        case .socketFailed(let detail): "scrcpy socket failed: \(detail)"
        case .invalidProtocol(let detail): "Invalid scrcpy protocol data: \(detail)"
        case .unsupportedCodec(let codec): "Unsupported native video codec: \(codec)"
        case .decoderFailed(let detail): "VideoToolbox decoder failed: \(detail)"
        case .audioFailed(let detail): "Core Audio playback failed: \(detail)"
        }
    }
}

enum ScrcpyTouchAction: UInt8 {
    case down = 0
    case up = 1
    case move = 2
    case hoverMove = 7
}

enum ScrcpyMouseButton: UInt32 {
    case primary = 1
    case secondary = 2
    case tertiary = 4
    case back = 8
    case forward = 16
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
    private let controlQueue = DispatchQueue(
        label: "com.screenremote.scrcpy.native.control",
        qos: .userInteractive
    )
    private let stateLock = NSLock()
    private var stopped = false
    private var serverProcess: Process?
    private var socketDescriptors: [Int32] = []
    private var controlSocket: Int32?
    private var forwardedPort: UInt16?
    private var decoder: ScrcpyVideoToolboxDecoder?
    private var audioRenderer: ScrcpyAudioRenderer?

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
                let remoteEncoders = self.detectRemoteEncoders(log: log)
                let videoSelection = selectNativeVideoCodec(
                    remoteEncoders: remoteEncoders,
                    requestedEncoder: self.options.videoEncoder,
                    requestedDecoder: self.options.videoDecoder
                )
                let audioSelection = selectNativeAudioCodec(
                    remoteEncoders: remoteEncoders,
                    requestedEncoder: self.options.audioEncoder,
                    requestedDecoder: self.options.audioDecoder
                )
                self.logSelectionFallbacks(
                    video: videoSelection,
                    audio: audioSelection,
                    log: log
                )
                try self.ensureRunning()
                let scid = UInt32.random(in: 1...0x7fff_ffff)
                let socketName = String(format: "scrcpy_%08x", scid)
                let port = try self.createForward(socketName: socketName, log: log)
                try self.ensureRunning()
                try self.launchServer(
                    scid: scid,
                    videoSelection: videoSelection,
                    audioSelection: audioSelection,
                    log: log
                )

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
                self.setControlSocket(control)

                let deviceName = try self.readDeviceMetadata(from: video)
                // The media streams are long-lived byte streams. Once the
                // handshake is complete, an idle/locked device may legitimately
                // produce no video or audio data for an unbounded period. Match
                // the Android and scrcpy-mask clients: use a blocking read and
                // let stop() close the socket to cancel it.
                self.clearReceiveTimeout(video)
                if let audio { self.clearReceiveTimeout(audio) }
                // Keep the ADB forward alive for the entire media session. The
                // video/audio sockets are still backed by this forward after
                // metadata has been read; removing it here can tear down the
                // active tunnel and make scrcpy cancel its encoder. Android and
                // scrcpy-mask both retain the forward until session cleanup.
                log("ADB forward retained for scrcpy session: localPort=\(self.forwardedPort ?? 0)")
                ready(deviceName)

                if let audio {
                    self.consumeAudio(socket: audio, selection: audioSelection, log: log)
                }
                try self.consumeVideo(socket: video, expectedCodec: videoSelection.codec, log: log)
                if !self.isStopped {
                    throw NativeScrcpyError.socketFailed("video stream closed")
                }
                stopped(nil)
            } catch {
                let wasStopped = self.isStopped
                log("Native scrcpy worker failed before cleanup: \(error.localizedDescription)")
                self.stop(log: log)
                stopped(wasStopped ? nil : error)
            }
        }
    }

    func stop(log: ((String) -> Void)? = nil) {
        stopResources(log: log)
    }

    private func stopResources(log: ((String) -> Void)?) {
        stateLock.lock()
        let alreadyStopped = stopped
        stopped = true
        let sockets = socketDescriptors
        socketDescriptors.removeAll()
        controlSocket = nil
        let process = serverProcess
        serverProcess = nil
        let audioRenderer = self.audioRenderer
        self.audioRenderer = nil
        stateLock.unlock()
        if alreadyStopped {
            // A stop can race with adb forward creation. The first stop may
            // have observed no port, while the worker assigns it immediately
            // afterwards; retry forward cleanup from the worker's catch path.
            try? removeForward(log: log ?? { _ in })
            return
        }

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
        audioRenderer?.stop()
        surface.clear()
    }

    func sendTouch(action: ScrcpyTouchAction, point: CGPoint, screenSize: CGSize) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        let message = Self.pointerMessage(
            action: action,
            pointerID: UInt64.max - 1,
            point: point,
            screenSize: screenSize,
            pressure: action == .up ? 0 : 1,
            actionButton: 0,
            buttons: 0
        )
        enqueueControlMessage(message)
    }

    func sendMouseMove(
        point: CGPoint,
        screenSize: CGSize,
        buttons: UInt32
    ) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        let message = Self.pointerMessage(
            action: buttons == 0 ? .hoverMove : .move,
            pointerID: UInt64.max,
            point: point,
            screenSize: screenSize,
            pressure: 1,
            actionButton: 0,
            buttons: buttons
        )
        enqueueControlMessage(message)
    }

    func sendMouseButton(
        action: ScrcpyTouchAction,
        button: ScrcpyMouseButton,
        point: CGPoint,
        screenSize: CGSize,
        buttons: UInt32
    ) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        let message = Self.pointerMessage(
            action: action,
            pointerID: UInt64.max,
            point: point,
            screenSize: screenSize,
            pressure: action == .up ? 0 : 1,
            actionButton: button.rawValue,
            buttons: buttons
        )
        enqueueControlMessage(message)
    }

    func sendMouseScroll(
        point: CGPoint,
        screenSize: CGSize,
        horizontal: CGFloat,
        vertical: CGFloat,
        buttons: UInt32
    ) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        let message = Self.scrollMessage(
            point: point,
            screenSize: screenSize,
            horizontal: horizontal,
            vertical: vertical,
            buttons: buttons
        )
        enqueueControlMessage(message)
    }

    private func enqueueControlMessage(_ message: Data) {
        controlQueue.async { [weak self] in
            self?.sendControlMessage(message)
        }
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

    private func setControlSocket(_ socket: Int32) {
        stateLock.lock()
        if !stopped {
            controlSocket = socket
        }
        stateLock.unlock()
    }

    private func registerAudioRenderer(_ renderer: ScrcpyAudioRenderer) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stopped else { return false }
        audioRenderer = renderer
        return true
    }

    private func clearAudioRenderer(_ renderer: ScrcpyAudioRenderer) {
        stateLock.lock()
        if audioRenderer === renderer {
            audioRenderer = nil
        }
        stateLock.unlock()
    }

    private func sendControlMessage(_ message: Data) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stopped, let socket = controlSocket else { return }

        message.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let sent = Darwin.send(
                    socket,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset,
                    0
                )
                if sent > 0 {
                    offset += sent
                } else if sent < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    private static func pointerMessage(
        action: ScrcpyTouchAction,
        pointerID: UInt64,
        point: CGPoint,
        screenSize: CGSize,
        pressure: Float,
        actionButton: UInt32,
        buttons: UInt32
    ) -> Data {
        let width = UInt16(clamping: max(Int(screenSize.width.rounded()), 1))
        let height = UInt16(clamping: max(Int(screenSize.height.rounded()), 1))
        let x = UInt32(clamping: max(Int(point.x.rounded()), 0))
        let y = UInt32(clamping: max(Int(point.y.rounded()), 0))

        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        bytes.append(2) // SC_CONTROL_MSG_TYPE_INJECT_TOUCH_EVENT
        bytes.append(action.rawValue)
        appendBigEndian(pointerID, to: &bytes)
        appendBigEndian(x, to: &bytes)
        appendBigEndian(y, to: &bytes)
        appendBigEndian(width, to: &bytes)
        appendBigEndian(height, to: &bytes)
        let encodedPressure = UInt16(clamping: Int((max(min(pressure, 1), 0) * 65_535).rounded()))
        appendBigEndian(encodedPressure, to: &bytes)
        appendBigEndian(actionButton, to: &bytes)
        appendBigEndian(buttons, to: &bytes)
        return Data(bytes)
    }

    private static func scrollMessage(
        point: CGPoint,
        screenSize: CGSize,
        horizontal: CGFloat,
        vertical: CGFloat,
        buttons: UInt32
    ) -> Data {
        let width = UInt16(clamping: max(Int(screenSize.width.rounded()), 1))
        let height = UInt16(clamping: max(Int(screenSize.height.rounded()), 1))
        let x = UInt32(clamping: max(Int(point.x.rounded()), 0))
        let y = UInt32(clamping: max(Int(point.y.rounded()), 0))
        let horizontalValue = Int16(clamping: Int(
            (max(min(horizontal / 16, 1), -1) * CGFloat(Int16.max)).rounded()
        ))
        let verticalValue = Int16(clamping: Int(
            (max(min(vertical / 16, 1), -1) * CGFloat(Int16.max)).rounded()
        ))

        var bytes = [UInt8]()
        bytes.reserveCapacity(21)
        bytes.append(3) // SC_CONTROL_MSG_TYPE_INJECT_SCROLL_EVENT
        appendBigEndian(x, to: &bytes)
        appendBigEndian(y, to: &bytes)
        appendBigEndian(width, to: &bytes)
        appendBigEndian(height, to: &bytes)
        appendBigEndian(horizontalValue, to: &bytes)
        appendBigEndian(verticalValue, to: &bytes)
        appendBigEndian(buttons, to: &bytes)
        return Data(bytes)
    }

    private static func appendBigEndian<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        let bigEndian = value.bigEndian
        withUnsafeBytes(of: bigEndian) { bytes.append(contentsOf: $0) }
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

    private func createForward(
        socketName: String,
        log: @escaping (String) -> Void
    ) throws -> UInt16 {
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

    private func launchServer(
        scid: UInt32,
        videoSelection: ScrcpyCodecSelection,
        audioSelection: ScrcpyCodecSelection,
        log: @escaping (String) -> Void
    ) throws {
        var parameters = [
            String(format: "scid=%08x", scid),
            "log_level=debug",
            "video_codec=\(videoSelection.codec)",
            "video_bit_rate=\(parseBitrate(options.videoBitrate, fallback: 4_000_000))",
            "max_fps=\(max(options.maxFPS, 1))",
            "tunnel_forward=true",
            "send_device_meta=true",
            "send_stream_meta=true",
            "send_frame_meta=true",
            "send_dummy_byte=true",
            "display_id=0",
            "downsize_on_error=false",
            "stay_awake=\(options.keepDeviceAwake)",
            "power_off_on_close=\(options.powerOffOnClose && options.cleanupOnDisconnect)"
        ]
        if options.maxSize > 0 { parameters.append("max_size=\(options.maxSize)") }
        if let encoder = videoSelection.encoder { parameters.append("video_encoder=\(encoder)") }
        if !options.clipboardSync { parameters.append("clipboard_autosync=false") }
        if !options.cleanupOnDisconnect { parameters.append("cleanup=false") }
        if options.ignoreVideoEncoderConstraints { parameters.append("ignore_video_encoder_constraints=true") }
        if options.enableAudio {
            parameters.append("audio_codec=\(audioSelection.codec)")
            if audioSelection.codec != "raw" {
                parameters.append("audio_bit_rate=\(parseBitrate(options.audioBitrate, fallback: 128_000))")
            }
            if let encoder = audioSelection.encoder { parameters.append("audio_encoder=\(encoder)") }
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
        let command = [
            "-s", serial, "shell",
            "CLASSPATH=\(ScrcpyServerAsset.remotePath)",
            "app_process", "/", "com.genymobile.scrcpy.Server", Self.serverVersion
        ] + parameters
        process.arguments = command
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
        log("scrcpy-server command: \(formatCommand([adbPath] + command))")
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
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
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

    private func clearReceiveTimeout(_ socket: Int32) {
        var timeout = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(
            socket,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout.size(ofValue: timeout))
        )
    }

    private func readDeviceMetadata(from socket: Int32) throws -> String {
        let data = try readExact(socket, count: 64)
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }

    private func consumeVideo(
        socket: Int32,
        expectedCodec: String,
        log: @escaping (String) -> Void
    ) throws {
        let codecData = try readExact(socket, count: 4)
        let codec = String(decoding: codecData.filter { $0 != 0 }, as: UTF8.self)
        guard codec == expectedCodec, let nativeCodec = NativeVideoCodec(rawValue: codec) else {
            throw NativeScrcpyError.unsupportedCodec(codec)
        }
        let initialHeader = try readExact(socket, count: 12)
        let initial = try ScrcpyMediaHeader(data: initialHeader)
        guard case .session(let width, let height, _) = initial else {
            throw NativeScrcpyError.invalidProtocol("missing initial video session header")
        }
        log("Native video stream ready: codec=\(codec), size=\(width)x\(height)")

        let decoder = ScrcpyVideoToolboxDecoder(
            codec: nativeCodec,
            surface: surface,
            hardwareDecodingEnabled: options.enableHardwareDecoding
        )
        self.decoder = decoder
        var loggedVideoPacketCount = 0
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
                if loggedVideoPacketCount < 3 {
                    log(
                        "Native video packet: bytes=\(size), config=\(isConfig), " +
                            "keyFrame=\(isKeyFrame), pts=\(pts)"
                    )
                    loggedVideoPacketCount += 1
                }
                if isConfig {
                    try decoder.configure(annexB: data)
                } else {
                    try decoder.decode(annexB: data, pts: pts, isKeyFrame: isKeyFrame)
                }
            }
        }
    }

    private func consumeAudio(
        socket: Int32,
        selection: ScrcpyCodecSelection,
        log: @escaping (String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let codecData = try self.readExact(socket, count: 4)
                let codec = String(decoding: codecData.filter { $0 != 0 }, as: UTF8.self)
                guard codec == selection.codec else {
                    throw NativeScrcpyError.invalidProtocol("unsupported audio codec \(codec)")
                }
                let renderer = try ScrcpyAudioRenderer(
                    codec: codec,
                    decoderIdentifier: selection.decoder,
                    volume: self.options.audioVolume,
                    log: log
                )
                defer {
                    renderer.stop()
                    self.clearAudioRenderer(renderer)
                }
                try renderer.start()
                guard self.registerAudioRenderer(renderer) else { return }
                log("Native audio stream ready: codec=\(codec), rate=48000, channels=2")
                while !self.isStopped {
                    let header = try ScrcpyMediaHeader(data: self.readExact(socket, count: 12))
                    guard case .media(let size, let pts, let isConfig, _) = header,
                          size > 0,
                          size <= 16 * 1024 * 1024 else {
                        throw NativeScrcpyError.invalidProtocol("invalid audio packet")
                    }
                    let packet = try self.readExact(socket, count: size)
                    try renderer.enqueue(packet, isConfig: isConfig, pts: pts)
                }
            } catch {
                if !self.isStopped { log("Audio stream ended: \(error.localizedDescription)") }
            }
        }
    }

    private func detectRemoteEncoders(log: @escaping (String) -> Void) -> [ScrcpyRemoteEncoder] {
        let cached = ScrcpyCodecCapabilityCache.remoteEncoders(for: serial)
        let hasVideo = cached.contains { $0.kind == .video }
        let hasAudio = cached.contains { $0.kind == .audio }
        if hasVideo, !options.enableAudio || hasAudio {
            log("Using cached remote codec capabilities: encoders=\(cached.count)")
            return cached
        }
        let command = [
            "-s", serial, "shell",
            "CLASSPATH=\(ScrcpyServerAsset.remotePath)",
            "app_process", "/", "com.genymobile.scrcpy.Server", Self.serverVersion,
            "log_level=info", "list_encoders=true", "cleanup=false"
        ]
        do {
            let result = try NativeProcess.run(adbPath, command)
            let encoders = parseScrcpyRemoteEncoders("\(result.output)\n\(result.error)")
            guard result.status == 0, !encoders.isEmpty else {
                log("Native codec detection failed; using safe fallbacks: \(result.failureDetail)")
                return []
            }
            let videoCount = encoders.filter { $0.kind == .video }.count
            let audioCount = encoders.filter { $0.kind == .audio }.count
            ScrcpyCodecCapabilityCache.saveRemoteEncoders(encoders, for: serial)
            log("Native codec detection completed: videoEncoders=\(videoCount), audioEncoders=\(audioCount)")
            return encoders
        } catch {
            log("Native codec detection failed; using safe fallbacks: \(error.localizedDescription)")
            return []
        }
    }

    private func logSelectionFallbacks(
        video: ScrcpyCodecSelection,
        audio: ScrcpyCodecSelection,
        log: @escaping (String) -> Void
    ) {
        let requestedVideoEncoder = options.videoEncoder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestedVideoEncoder.isEmpty, video.encoder != requestedVideoEncoder {
            log("Requested video encoder is incompatible with the native decoder and was ignored: \(requestedVideoEncoder)")
        }
        if let requestedVideoCodec = codecForVideoDecoderSelection(options.videoDecoder),
           requestedVideoCodec != video.codec {
            log("Requested video decoder route is not implemented by the native session and was ignored: \(options.videoDecoder)")
        }
        if options.enableAudio {
            let requestedAudioEncoder = options.audioEncoder.trimmingCharacters(in: .whitespacesAndNewlines)
            if !requestedAudioEncoder.isEmpty, audio.encoder != requestedAudioEncoder {
                log("Requested audio encoder is incompatible with the local decoder and was ignored: \(requestedAudioEncoder)")
            }
            let requestedAudioDecoder = options.audioDecoder.trimmingCharacters(in: .whitespacesAndNewlines)
            if !requestedAudioDecoder.isEmpty, audio.decoder != requestedAudioDecoder {
                log("Requested audio decoder is unavailable or incompatible with the remote encoder and was ignored: \(requestedAudioDecoder)")
            }
        }
        log(
            "Native codec selection: video=\(video.codec), " +
                "videoEncoder=\(video.encoder ?? "server-default"), " +
                "audio=\(options.enableAudio ? audio.codec : "disabled"), " +
                "audioEncoder=\(audio.encoder ?? "not-applicable"), " +
                "audioDecoder=\(audio.decoder ?? (audio.codec == "raw" ? "not-applicable" : "system-default"))"
        )
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
                    // A locked or otherwise idle device can legitimately leave the
                    // video stream without data for longer than SO_RCVTIMEO. This
                    // is not a disconnect; keep waiting so the session survives
                    // until the device produces another frame or stop() closes
                    // the socket.
                    if errno == EAGAIN || errno == EWOULDBLOCK { continue }
                    throw NativeScrcpyError.socketFailed(lastPOSIXError())
                }
                offset += received
            }
        }
        return data
    }
}

// AudioConverter packet plumbing is adapted from droidMirroring-mac's
// Apache-2.0-licensed AudioRenderer (Copyright 2026 matyle and macDros contributors).
private final class ScrcpyAudioRenderer {
    private let codec: String
    private let decoderIdentifier: String?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let gain: Float
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
