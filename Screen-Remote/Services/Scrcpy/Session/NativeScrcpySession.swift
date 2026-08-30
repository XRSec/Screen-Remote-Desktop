import AppKit
import Foundation
import Darwin

/// Owns the official scrcpy 4.1 server lifecycle and its ordered media/control sockets.
/// scrcpy-mask is only a behavioral reference; no scrcpy-mask server extensions are used.
final class NativeScrcpySession {
    let surface: ScrcpyVideoSurface

    private let adbPath: String
    private let serial: String
    let options: ScrcpyDeviceOptions
    private let queue = DispatchQueue(label: "com.screenremote.scrcpy.native", qos: .userInitiated)
    private let controlQueue = DispatchQueue(
        label: "com.screenremote.scrcpy.native.control",
        qos: .userInteractive
    )
    private let stateLock = NSLock()
    private let onClipboardChanged: (String) -> Void
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
        surface: ScrcpyVideoSurface,
        onClipboardChanged: ((String) -> Void)? = nil
    ) {
        self.adbPath = adbPath
        self.serial = serial
        self.options = options
        self.surface = surface
        self.onClipboardChanged = onClipboardChanged ?? { text in
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    func start(
        log: @escaping (String) -> Void,
        ready: @escaping (String) -> Void,
        stopped: @escaping (Error?) -> Void,
        onStartupAudioReady: (() -> Void)? = nil,
        onStartupFrameRendered: ((String) -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try ScrcpyServerAsset.ensureDeployed(
                    adbPath: adbPath,
                    serial: serial,
                    log: log
                )
                try self.ensureRunning()
                let remoteEncoders = ScrcpyCodecCapabilityProbe.remoteEncoders(
                    adbPath: adbPath,
                    serial: serial,
                    log: log
                )
                let requestedVideoCodec = self.requestedVideoCodec()
                let requestedVideoCodecLabel = self.requestedVideoCodecLabel()
                let fallbackPolicy = self.codecFallbackPolicy()
                var videoSelection = selectNativeVideoCodec(
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
                    requestedVideoCodec: requestedVideoCodec,
                    log: log
                )
                var fallbackAttempted = false
                var startupVideoStarted = false
                while true {
                    var startupFailureReason: String?
                    do {
                        startupVideoStarted = false
                        try self.runNativeScrcpySession(
                            videoSelection: videoSelection,
                            audioSelection: audioSelection,
                            log: log,
                            ready: ready,
                            onStartupFrameRendered: onStartupFrameRendered,
                            onStartupAudioReady: onStartupAudioReady,
                            onServerFailureReason: {
                                startupFailureReason = $0
                            },
                            onStartupVideoStarted: {
                                startupVideoStarted = true
                            }
                        )
                        return
                    } catch {
                        let fallbackReason = Self.startupCodecFailureReason(
                            error: error,
                            selectedCodec: videoSelection.codec,
                            serverReason: startupFailureReason
                        )
                        let requestCodec = requestedVideoCodec ?? videoSelection.codec
                        if !startupVideoStarted,
                           !fallbackAttempted,
                            let fallbackReason,
                           let fallbackSelection = self.fallbackNativeVideoCodec(
                                remoteEncoders: remoteEncoders,
                                requestedCodec: requestCodec,
                                currentSelection: videoSelection,
                                failureReason: fallbackReason,
                                policy: fallbackPolicy
                           ) {
                            fallbackAttempted = true
                            self.logCodecFallback(
                                requestedCodec: requestCodec,
                                appliedCodec: fallbackSelection.codec,
                                reason: fallbackReason,
                                log: log
                            )
                            self.cleanupAfterStartupFailure(log: log)
                            videoSelection = fallbackSelection
                            continue
                        }
                        if !startupVideoStarted,
                           fallbackPolicy == .strict,
                           hasExplicitVideoCodecRequest {
                            self.logExplicitCodecRequestFailed(
                                requestedCodec: requestedVideoCodecLabel ?? requestCodec,
                                reason: fallbackReason ?? error.localizedDescription,
                                log: log
                            )
                        }
                        throw error
                    }
                }
            } catch {
                let wasStopped = self.isStopped
                if !wasStopped {
                    log("Native scrcpy worker failed before cleanup: \(error.localizedDescription)")
                }
                self.stop(log: log)
                stopped(wasStopped ? nil : error)
            }
        }
    }

    func stop(log: ((String) -> Void)? = nil) {
        stopResources(log: log)
    }

    func applyAudioVolume(_ volume: Double) -> Bool {
        stateLock.lock()
        let renderer = audioRenderer
        stateLock.unlock()
        guard let renderer else { return false }
        renderer.setGain(volume)
        return true
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

    private func runNativeScrcpySession(
        videoSelection: ScrcpyCodecSelection,
        audioSelection: ScrcpyCodecSelection,
        log: @escaping (String) -> Void,
        ready: @escaping (String) -> Void,
        onStartupFrameRendered: ((String) -> Void)?,
        onStartupAudioReady: (() -> Void)?,
        onServerFailureReason: @escaping (String) -> Void,
        onStartupVideoStarted: @escaping () -> Void
    ) throws {
        try ensureRunning()
        let scid = UInt32.random(in: 1...0x7fff_ffff)
        let socketName = String(format: "scrcpy_%08x", scid)
        let port = try createForward(socketName: socketName, log: log)
        try ensureRunning()
        try launchServer(
            scid: scid,
            videoSelection: videoSelection,
            audioSelection: audioSelection,
            log: log,
            onServerLogLine: { line in
                if let reason = Self.serverCodecFailureReason(from: line) {
                    onServerFailureReason(reason)
                }
            }
        )

        let video = try connectFirstSocket(port: port)
        try registerSocket(video)
        let audio: Int32?
        if options.enableAudio {
            let socket = try connectSocket(port: port)
            try registerSocket(socket)
            audio = socket
        } else {
            audio = nil
        }
        let control = try connectSocket(port: port)
        try registerSocket(control)
        setControlSocket(control)

        let deviceName = try readDeviceMetadata(from: video)
        clearReceiveTimeout(video)
        if let audio { clearReceiveTimeout(audio) }
        clearReceiveTimeout(control)
        startControlReceiver(
            socket: control,
            onClipboardChanged: onClipboardChanged,
            log: log
        )
        log("ADB forward retained for scrcpy session: localPort=\(forwardedPort ?? 0)")
        ready(deviceName)
        let onStartupFrameRendered = onStartupFrameRendered.map { callback in
            { callback(deviceName) }
        }

        if let audio { consumeAudio(socket: audio, selection: audioSelection, onStartupAudioReady: onStartupAudioReady, log: log) }
        try consumeVideo(
            socket: video,
            expectedCodec: videoSelection.codec,
            onStartupVideoStarted: onStartupVideoStarted,
            onStartupFrameRendered: onStartupFrameRendered,
            log: log
        )
        if !isStopped {
            throw NativeScrcpyError.socketFailed("video stream closed")
        }
    }

    func enqueueControlMessage(_ message: Data) {
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

    private func cleanupAfterStartupFailure(log: @escaping (String) -> Void) {
        var sockets: [Int32] = []
        var process: Process?
        var forwardPort: UInt16?
        var activeDecoder: ScrcpyVideoToolboxDecoder?
        var activeRenderer: ScrcpyAudioRenderer?

        stateLock.lock()
        sockets = socketDescriptors
        socketDescriptors.removeAll()
        process = serverProcess
        serverProcess = nil
        forwardPort = forwardedPort
        forwardedPort = nil
        controlSocket = nil
        activeDecoder = decoder
        decoder = nil
        activeRenderer = audioRenderer
        audioRenderer = nil
        stateLock.unlock()

        for socket in sockets {
            Darwin.shutdown(socket, SHUT_RDWR)
            Darwin.close(socket)
        }
        let removedPort = forwardPort
        if let process {
            if process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(0.8)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning { process.terminate() }
            }
        }
        activeDecoder?.invalidate()
        activeRenderer?.stop()
        if let port = removedPort {
            let result = try? NativeProcess.run(
                adbPath,
                ["-s", serial, "forward", "--remove", "tcp:\(port)"]
            )
            if result?.status == 0 {
                log("ADB forward removed: localPort=\(port)")
            } else {
                log("ADB forward removal failed: localPort=\(port), \(result?.failureDetail ?? "unknown failure")")
            }
        }
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
        log: @escaping (String) -> Void,
        onServerLogLine: ((String) -> Void)? = nil
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
            "CLASSPATH=\(ScrcpyServerMetadata.remotePath)",
            "app_process", "/", "com.genymobile.scrcpy.Server", ScrcpyServerMetadata.version
        ] + parameters
        process.arguments = command
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                let logLine = String(line)
                log("scrcpy-server: \(logLine)")
                onServerLogLine?(logLine)
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

    private func readDeviceMetadata(from socket: Int32) throws -> String {
        let data = try readExact(socket, count: 64)
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }

    private func consumeVideo(
        socket: Int32,
        expectedCodec: String,
        onStartupVideoStarted: @escaping () -> Void,
        onStartupFrameRendered: (() -> Void)?,
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
            hardwareDecodingEnabled: options.enableHardwareDecoding,
            onFirstFrame: onStartupFrameRendered
        )
        self.decoder = decoder
        var startupVideoStarted = false
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
                if !startupVideoStarted {
                    startupVideoStarted = true
                    onStartupVideoStarted()
                }
            }
        }
    }

    private func consumeAudio(
        socket: Int32,
        selection: ScrcpyCodecSelection,
        onStartupAudioReady: (() -> Void)?,
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
                var startupAudioReady = false
                while !self.isStopped {
                    let header = try ScrcpyMediaHeader(data: self.readExact(socket, count: 12))
                    guard case .media(let size, let pts, let isConfig, _) = header,
                          size > 0,
                          size <= 16 * 1024 * 1024 else {
                        throw NativeScrcpyError.invalidProtocol("invalid audio packet")
                    }
                    let packet = try self.readExact(socket, count: size)
                    try renderer.enqueue(packet, isConfig: isConfig, pts: pts)
                    if !startupAudioReady {
                        startupAudioReady = true
                        onStartupAudioReady?()
                    }
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
