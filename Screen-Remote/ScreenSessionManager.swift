import AppKit
import Foundation

enum ScreenSessionPhase: String, Equatable {
    case idle
    case checkingExisting
    case racing
    case connected
    case buildingCommand
    case launching
    case running
    case stopped
    case failed

    var localizationKey: String {
        switch self {
        case .idle: "screenSessionIdle"
        case .checkingExisting: "screenSessionCheckingExisting"
        case .racing: "screenSessionRacing"
        case .connected: "screenSessionConnected"
        case .buildingCommand: "screenSessionBuildingCommand"
        case .launching: "screenSessionLaunching"
        case .running: "screenSessionRunning"
        case .stopped: "screenSessionStopped"
        case .failed: "screenSessionFailed"
        }
    }

    var isWorking: Bool {
        switch self {
        case .checkingExisting, .racing, .buildingCommand, .launching:
            true
        case .idle, .connected, .running, .stopped, .failed:
            false
        }
    }

    var supportsBatteryInformation: Bool {
        switch self {
        case .connected, .buildingCommand, .launching, .running:
            true
        case .idle, .checkingExisting, .racing, .stopped, .failed:
            false
        }
    }
}

struct ScreenDevicePreflight: Equatable {
    var model = ""
    var androidVersion = ""
    var serial = ""
    var buildFingerprint = ""
    var displaySize = ""
    var batteryLevel: Int?
}

struct ScreenSessionSnapshot: Equatable {
    let deviceID: UUID
    var phase: ScreenSessionPhase = .idle
    var transport: DeviceTransport?
    var adbSerial = ""
    var detail = ""
    var preflight: ScreenDevicePreflight?
    var command: [String] = []
    var processIdentifier: Int32?

    var isRunning: Bool { phase == .running }
    var isConnected: Bool { phase.supportsBatteryInformation && !adbSerial.isEmpty }
    var batteryLevel: Int? { preflight?.batteryLevel }
}

struct ResolvedADBTarget: Equatable {
    let serial: String
    let transport: DeviceTransport
    let adbPath: String
}

private struct SessionLaunchConfiguration {
    let adbPath: String
    let scrcpyPath: String
}

private struct RemoteVideoEncoder: Hashable {
    let codec: String
    let name: String
}

private struct AppVirtualDisplayKey: Hashable {
    let launchID: UUID
    let deviceID: UUID
    let packageName: String
}

private struct AppVirtualDisplayIdentifier: Hashable {
    let deviceID: UUID
    let packageName: String
}

private struct ADBConnectedDevice {
    let serial: String
    let state: String
}

private struct ResolvedConnectionCandidate {
    let connection: DeviceConnection
    let adbSerial: String

    var transport: DeviceTransport { connection.transport }
}

private struct ConnectionRaceOutcome {
    let candidate: ResolvedConnectionCandidate
    let preflight: ScreenDevicePreflight?
    let error: String?

    var succeeded: Bool { preflight != nil }
}

private struct SessionCommandResult {
    let exitCode: Int32
    let output: String
    let error: String
    let timedOut: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut }
}

private final class ScrcpyOutputCapture {
    private let lock = NSLock()
    private var pending = ""
    private var recentLines: [String] = []

    func append(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }

        let combined = pending + String(decoding: data, as: UTF8.self)
        var lines = combined.components(separatedBy: .newlines)
        pending = lines.popLast() ?? ""
        let completed = lines.filter { !$0.isEmpty }
        recentLines.append(contentsOf: completed)
        if recentLines.count > 40 {
            recentLines.removeFirst(recentLines.count - 40)
        }
        return completed
    }

    var failureDetail: String {
        lock.lock()
        defer { lock.unlock() }
        let lines = recentLines.suffix(4) + (pending.isEmpty ? [] : [pending])
        return lines.joined(separator: " | ")
    }
}

@MainActor
final class ScreenSessionManager: NSObject, ObservableObject {
    @Published private(set) var sessions: [UUID: ScreenSessionSnapshot] = [:]
    @Published private var appVirtualDisplayLaunchCounts: [AppVirtualDisplayIdentifier: Int] = [:]

    private var startupTasks: [UUID: Task<Void, Never>] = [:]
    private var batteryRefreshTasks: [UUID: Task<Void, Never>] = [:]
    private var runningProcesses: [UUID: Process] = [:]
    private var nativeSessions: [UUID: NativeScrcpySession] = [:]
    private var videoSurfaces: [UUID: ScrcpyVideoSurface] = [:]
    private var appVirtualDisplayTasks: [AppVirtualDisplayKey: Task<Void, Never>] = [:]
    private var appVirtualDisplayProcesses: [AppVirtualDisplayKey: Process] = [:]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationWillTerminate() {
        for task in startupTasks.values {
            task.cancel()
        }
        for task in batteryRefreshTasks.values {
            task.cancel()
        }
        for process in runningProcesses.values where process.isRunning {
            process.terminate()
        }
        for session in nativeSessions.values {
            session.stop()
        }
        for task in appVirtualDisplayTasks.values {
            task.cancel()
        }
        for process in appVirtualDisplayProcesses.values where process.isRunning {
            process.terminate()
        }
        startupTasks.removeAll()
        batteryRefreshTasks.removeAll()
        runningProcesses.removeAll()
        nativeSessions.removeAll()
        appVirtualDisplayTasks.removeAll()
        appVirtualDisplayProcesses.removeAll()
    }

    func session(for deviceID: UUID) -> ScreenSessionSnapshot {
        sessions[deviceID] ?? ScreenSessionSnapshot(deviceID: deviceID)
    }

    func videoSurface(for deviceID: UUID) -> ScrcpyVideoSurface {
        if let surface = videoSurfaces[deviceID] { return surface }
        let surface = ScrcpyVideoSurface()
        videoSurfaces[deviceID] = surface
        return surface
    }

    func isLaunchingAppVirtualDisplay(deviceID: UUID, packageName: String) -> Bool {
        let identifier = AppVirtualDisplayIdentifier(deviceID: deviceID, packageName: packageName)
        return appVirtualDisplayLaunchCounts[identifier, default: 0] > 0
    }

    func start(
        device: Device,
        adbPath configuredADBPath: String,
        scrcpyPath configuredScrcpyPath: String,
        log: @escaping (String) -> Void
    ) {
        if nativeSessions[device.id] != nil {
            update(device.id, phase: .running, detail: session(for: device.id).detail)
            log("Existing native scrcpy session is already active: \(device.name)")
            return
        }
        if let process = runningProcesses[device.id], process.isRunning {
            update(device.id, phase: .running, detail: "")
            NSRunningApplication(processIdentifier: process.processIdentifier)?.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )
            log("Existing scrcpy session activated: \(device.name), pid=\(process.processIdentifier)")
            return
        }
        guard startupTasks[device.id] == nil else { return }

        let adbPath = executablePath(configuredADBPath, fallback: .adb)
        let scrcpyPath = executablePath(configuredScrcpyPath, fallback: .scrcpy)
        let configuration = SessionLaunchConfiguration(
            adbPath: adbPath,
            scrcpyPath: scrcpyPath
        )
        if !session(for: device.id).isConnected {
            sessions[device.id] = ScreenSessionSnapshot(
                deviceID: device.id,
                phase: .checkingExisting,
                detail: ""
            )
        }
        log("Screen startup requested: \(device.name)")

        startupTasks[device.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.startupTasks[device.id] = nil }
            do {
                try await self.runStartup(
                    device: device,
                    configuration: configuration,
                    log: log
                )
            } catch is CancellationError {
                self.restoreConnectedStateOrStop(deviceID: device.id)
                log("Screen startup cancelled: \(device.name)")
            } catch {
                if self.session(for: device.id).adbSerial.isEmpty {
                    self.update(device.id, phase: .failed, detail: error.localizedDescription)
                } else {
                    self.restoreConnectedStateOrStop(deviceID: device.id, detail: error.localizedDescription)
                }
                log("Screen startup failed: \(device.name), \(error.localizedDescription)")
            }
        }
    }

    func connect(
        device: Device,
        adbPath configuredADBPath: String,
        log: @escaping (String) -> Void
    ) {
        if session(for: device.id).isConnected {
            log("ADB session already connected: \(device.name)")
            return
        }
        guard startupTasks[device.id] == nil else { return }

        let adbPath = executablePath(configuredADBPath, fallback: .adb)
        sessions[device.id] = ScreenSessionSnapshot(
            deviceID: device.id,
            phase: .checkingExisting,
            detail: ""
        )
        log("ADB session connection requested: \(device.name)")
        startupTasks[device.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.startupTasks[device.id] = nil }
            do {
                let winner = try await self.resolveConnection(
                    connections: device.connections,
                    adbPath: adbPath,
                    log: log,
                    onNetworkRaceStarted: { [weak self] in
                        self?.update(device.id, phase: .racing, detail: "")
                    }
                )
                try self.applyConnectedState(
                    device: device,
                    winner: winner,
                    adbPath: adbPath
                )
                log("ADB session connected without starting scrcpy: \(device.name)")
            } catch is CancellationError {
                self.update(device.id, phase: .stopped, detail: "")
                log("ADB session connection cancelled: \(device.name)")
            } catch {
                self.update(device.id, phase: .failed, detail: error.localizedDescription)
                log("ADB session connection failed: \(device.name), \(error.localizedDescription)")
            }
        }
    }

    func stop(deviceID: UUID, log: ((String) -> Void)? = nil) {
        startupTasks.removeValue(forKey: deviceID)?.cancel()
        nativeSessions.removeValue(forKey: deviceID)?.stop(log: log)
        if let process = runningProcesses.removeValue(forKey: deviceID), process.isRunning {
            process.terminate()
        }
        stopAppVirtualDisplays(deviceID: deviceID)
        update(deviceID, phase: .stopped, detail: "")
        log?("Session stopped: deviceID=\(deviceID.uuidString)")
    }

    func openAppOnVirtualDisplay(
        app: ManagedAndroidApp,
        device: Device,
        adbPath configuredADBPath: String,
        scrcpyPath configuredScrcpyPath: String,
        log: @escaping (String) -> Void
    ) {
        let session = session(for: device.id)
        guard session.isConnected else {
            log("App virtual display launch skipped because the ADB session is not connected: \(device.name)")
            return
        }

        let key = AppVirtualDisplayKey(
            launchID: UUID(),
            deviceID: device.id,
            packageName: app.packageName
        )
        let identifier = AppVirtualDisplayIdentifier(
            deviceID: device.id,
            packageName: app.packageName
        )
        appVirtualDisplayLaunchCounts[identifier, default: 0] += 1

        let configuration = SessionLaunchConfiguration(
            adbPath: executablePath(configuredADBPath, fallback: .adb),
            scrcpyPath: executablePath(configuredScrcpyPath, fallback: .scrcpy)
        )
        appVirtualDisplayTasks[key] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.appVirtualDisplayTasks.removeValue(forKey: key)
                self.finishAppVirtualDisplayLaunch(identifier)
            }
            guard FileManager.default.isExecutableFile(atPath: configuration.scrcpyPath) else {
                log("App virtual display launch failed because scrcpy was not found")
                return
            }

            var options = device.scrcpyOptions
            options.newDisplayEnabled = true
            options.virtualDisplaySystemDecorations = false
            options.preserveVirtualDisplayContent = true
            options.startApp = app.packageName
            let launchDevice = Device(
                id: device.id,
                name: "\(device.name) — \(app.name)",
                model: device.model,
                systemVersion: device.systemVersion,
                battery: device.battery,
                accent: device.accent,
                isConnected: device.isConnected,
                groupIDs: device.groupIDs,
                connections: device.connections,
                scrcpyOptions: options
            )
            let automaticVideoEncoder = await resolveAutomaticVideoEncoder(
                device: launchDevice,
                adbSerial: session.adbSerial,
                configuration: configuration,
                log: log
            )
            guard !Task.isCancelled else { return }
            let arguments = buildScrcpyArguments(
                device: launchDevice,
                adbSerial: session.adbSerial,
                automaticVideoEncoder: automaticVideoEncoder
            )
            do {
                try self.launchAppVirtualDisplayProcess(
                    key: key,
                    app: app,
                    device: device,
                    arguments: arguments,
                    configuration: configuration,
                    log: log
                )
            } catch {
                log("App virtual display launch failed: \(app.packageName), \(error.localizedDescription)")
            }
        }
    }

    func resolveADBTarget(
        connections: [DeviceConnection],
        adbPath configuredADBPath: String,
        log: @escaping (String) -> Void
    ) async throws -> ResolvedADBTarget {
        let adbPath = executablePath(configuredADBPath, fallback: .adb)
        let winner = try await resolveConnection(
            connections: connections,
            adbPath: adbPath,
            log: log
        )
        return ResolvedADBTarget(
            serial: winner.candidate.adbSerial,
            transport: winner.candidate.transport,
            adbPath: adbPath
        )
    }

    private func runStartup(
        device: Device,
        configuration: SessionLaunchConfiguration,
        log: @escaping (String) -> Void
    ) async throws {
        let winner: ConnectionRaceOutcome
        if let connectedWinner = connectedOutcome(for: device) {
            winner = connectedWinner
        } else {
            update(device.id, phase: .checkingExisting, detail: "")
            winner = try await resolveConnection(
                connections: device.connections,
                adbPath: configuration.adbPath,
                log: log,
                onNetworkRaceStarted: { [weak self] in
                    self?.update(device.id, phase: .racing, detail: "")
                }
            )
        }
        try await prepareAndLaunch(
            device: device,
            winner: winner,
            configuration: configuration,
            log: log
        )
    }

    private func connectedOutcome(for device: Device) -> ConnectionRaceOutcome? {
        let snapshot = session(for: device.id)
        guard snapshot.isConnected,
              let transport = snapshot.transport,
              let preflight = snapshot.preflight,
              let connection = device.connections.first(where: { $0.transport == transport })
                ?? device.connections.first else {
            return nil
        }
        return ConnectionRaceOutcome(
            candidate: ResolvedConnectionCandidate(
                connection: connection,
                adbSerial: snapshot.adbSerial
            ),
            preflight: preflight,
            error: nil
        )
    }

    private func resolveConnection(
        connections: [DeviceConnection],
        adbPath: String,
        log: @escaping (String) -> Void,
        onNetworkRaceStarted: (() -> Void)? = nil
    ) async throws -> ConnectionRaceOutcome {
        guard FileManager.default.isExecutableFile(atPath: adbPath) else {
            throw ScreenSessionError.adbNotFound
        }
        guard !connections.isEmpty else {
            throw ScreenSessionError.noConnectionCandidates
        }

        let existingResult = await SessionProcessRunner.run(
            executable: adbPath,
            arguments: ["devices", "-l"],
            timeout: 5
        )
        guard existingResult.succeeded else {
            throw ScreenSessionError.commandFailed(existingResult.failureDetail)
        }
        let mdnsResult = await SessionProcessRunner.run(
            executable: adbPath,
            arguments: ["mdns", "services"],
            timeout: 5
        )
        let candidates = resolveCandidates(connections, mdnsOutput: mdnsResult.output)
        if let winner = await chooseExistingConnection(
            candidates: candidates,
            connectedDevices: parseConnectedADBDevices(existingResult.output),
            adbPath: adbPath,
            log: log
        ) {
            return winner
        }

        let networkCandidates = candidates.filter { $0.transport != .usb }
        guard !networkCandidates.isEmpty else {
            throw ScreenSessionError.usbUnavailable
        }
        onNetworkRaceStarted?()
        log(
            "ADB connection race started: \(networkCandidates.map { "\($0.transport.rawValue):\($0.adbSerial)" }.joined(separator: ", "))"
        )
        return try await raceNetworkConnections(
            networkCandidates,
            adbPath: adbPath,
            log: log
        )
    }

    private func chooseExistingConnection(
        candidates: [ResolvedConnectionCandidate],
        connectedDevices: [ADBConnectedDevice],
        adbPath: String,
        log: @escaping (String) -> Void
    ) async -> ConnectionRaceOutcome? {
        let connectedSerials = Set(
            connectedDevices
                .filter { $0.state == "device" }
                .map { normalizeADBSerial($0.serial) }
        )
        let existing = candidates
            .filter { connectedSerials.contains(normalizeADBSerial($0.adbSerial)) }

        for transport in [DeviceTransport.usb, .mdns, .tcp] {
            let transportCandidates = existing.filter { $0.transport == transport }
            guard !transportCandidates.isEmpty else { continue }

            log(
                "Existing ADB connection race started: \(transportCandidates.map { "\($0.transport.rawValue):\($0.adbSerial)" }.joined(separator: ", "))"
            )
            if let winner = await raceExistingConnections(
                transportCandidates,
                adbPath: adbPath,
                log: log
            ) {
                return winner
            }
        }
        return nil
    }

    private func raceExistingConnections(
        _ candidates: [ResolvedConnectionCandidate],
        adbPath: String,
        log: @escaping (String) -> Void
    ) async -> ConnectionRaceOutcome? {
        let stream = AsyncStream<ConnectionRaceOutcome> { continuation in
            for candidate in candidates {
                Task {
                    let started = Date()
                    let outcome = await preflight(candidate: candidate, adbPath: adbPath)
                    let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
                    await MainActor.run {
                        if outcome.succeeded {
                            log(
                                "Existing ADB race candidate ready: \(candidate.transport.rawValue):\(candidate.adbSerial), preflight=\(elapsed)ms"
                            )
                        } else {
                            log(
                                "Existing ADB race candidate failed: \(candidate.transport.rawValue):\(candidate.adbSerial), preflight=\(elapsed)ms, \(outcome.error ?? "unknown error")"
                            )
                        }
                    }
                    continuation.yield(outcome)
                }
            }
        }

        var completed = 0
        for await outcome in stream {
            completed += 1
            if outcome.succeeded {
                log(
                    "Existing ADB connection race winner: \(outcome.candidate.transport.rawValue):\(outcome.candidate.adbSerial)"
                )
                return outcome
            }
            if completed == candidates.count { break }
        }
        return nil
    }

    private func raceNetworkConnections(
        _ candidates: [ResolvedConnectionCandidate],
        adbPath: String,
        log: @escaping (String) -> Void
    ) async throws -> ConnectionRaceOutcome {
        let stream = AsyncStream<ConnectionRaceOutcome> { continuation in
            for candidate in candidates {
                Task {
                    let started = Date()
                    let connect = await SessionProcessRunner.run(
                        executable: adbPath,
                        arguments: ["connect", candidate.adbSerial],
                        timeout: 7
                    )
                    let outcome: ConnectionRaceOutcome
                    if connect.succeeded && adbConnectSucceeded(connect) {
                        outcome = await preflight(candidate: candidate, adbPath: adbPath)
                    } else {
                        outcome = ConnectionRaceOutcome(
                            candidate: candidate,
                            preflight: nil,
                            error: connect.failureDetail
                        )
                    }
                    let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
                    await MainActor.run {
                        if outcome.succeeded {
                            log(
                                "ADB race candidate ready: \(candidate.transport.rawValue):\(candidate.adbSerial), \(elapsed)ms"
                            )
                        } else {
                            log(
                                "ADB race candidate failed: \(candidate.transport.rawValue):\(candidate.adbSerial), \(elapsed)ms, \(outcome.error ?? "unknown error")"
                            )
                        }
                    }
                    continuation.yield(outcome)
                }
            }
        }

        var completed = 0
        var lastError = ""
        for await outcome in stream {
            completed += 1
            if outcome.succeeded {
                log(
                    "ADB connection race winner: \(outcome.candidate.transport.rawValue):\(outcome.candidate.adbSerial)"
                )
                // Intentionally do not cancel or disconnect the remaining candidates.
                return outcome
            }
            lastError = outcome.error ?? lastError
            if completed == candidates.count { break }
        }
        throw ScreenSessionError.connectionRaceFailed(lastError)
    }

    private func prepareAndLaunch(
        device: Device,
        winner: ConnectionRaceOutcome,
        configuration: SessionLaunchConfiguration,
        log: @escaping (String) -> Void
    ) async throws {
        try applyConnectedState(
            device: device,
            winner: winner,
            adbPath: configuration.adbPath
        )

        update(device.id, phase: .buildingCommand, detail: "")
        var commandSnapshot = session(for: device.id)
        commandSnapshot.command = [
            configuration.adbPath,
            "-s", winner.candidate.adbSerial,
            "shell", "scrcpy-server", NativeScrcpySession.serverVersion
        ]
        sessions[device.id] = commandSnapshot
        log("Native scrcpy session command prepared: \(formatCommand(commandSnapshot.command))")
        log("Screen Remote owns server deployment and ordered video, audio, and control sockets")

        update(device.id, phase: .launching, detail: "")
        let surface = videoSurface(for: device.id)
        let nativeSession = NativeScrcpySession(
            adbPath: configuration.adbPath,
            serial: winner.candidate.adbSerial,
            options: device.scrcpyOptions,
            surface: surface
        )
        nativeSessions[device.id] = nativeSession
        nativeSession.start(
            log: log,
            ready: { [weak self, weak nativeSession] deviceName in
                DispatchQueue.main.async {
                    guard let self,
                          let nativeSession,
                          self.nativeSessions[device.id] === nativeSession else { return }
                    var running = self.session(for: device.id)
                    running.phase = .running
                    running.processIdentifier = nil
                    running.detail = "\(running.transport?.rawValue ?? "ADB") · \(running.adbSerial) · \(deviceName)"
                    self.sessions[device.id] = running
                    log("Native scrcpy session started: \(device.name), serial=\(running.adbSerial)")
                }
            },
            stopped: { [weak self, weak nativeSession] error in
                DispatchQueue.main.async {
                    guard let self,
                          let nativeSession,
                          self.nativeSessions[device.id] === nativeSession else { return }
                    self.nativeSessions.removeValue(forKey: device.id)
                    self.restoreConnectedStateOrStop(
                        deviceID: device.id,
                        detail: error?.localizedDescription ?? ""
                    )
                    if let error {
                        log("Native scrcpy session ended: \(device.name), \(error.localizedDescription)")
                    } else {
                        log("Native scrcpy session stopped: \(device.name)")
                    }
                }
            }
        )
    }

    private func applyConnectedState(
        device: Device,
        winner: ConnectionRaceOutcome,
        adbPath: String
    ) throws {
        guard let preflight = winner.preflight else {
            throw ScreenSessionError.connectionRaceFailed(winner.error ?? "")
        }
        var snapshot = session(for: device.id)
        snapshot.phase = .connected
        snapshot.transport = winner.candidate.transport
        snapshot.adbSerial = winner.candidate.adbSerial
        snapshot.preflight = preflight
        snapshot.processIdentifier = nil
        snapshot.detail = "\(winner.candidate.transport.rawValue) · \(winner.candidate.adbSerial)"
        sessions[device.id] = snapshot
        startBatteryRefresh(
            deviceID: device.id,
            adbSerial: winner.candidate.adbSerial,
            adbPath: adbPath
        )
    }

    private func launchScrcpy(
        device: Device,
        arguments: [String],
        configuration: SessionLaunchConfiguration,
        log: @escaping (String) -> Void
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.scrcpyPath)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = configuration.adbPath
        // scrcpy must remain a regular foreground SDL application so its window
        // can become key and receive the complete scrcpy keyboard shortcut set.
        environment.removeValue(forKey: "SDL_MAC_BACKGROUND_APP")
        process.environment = environment
        let outputPipe = Pipe()
        let outputCapture = ScrcpyOutputCapture()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let lines = outputCapture.append(handle.availableData)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                for line in lines {
                    log("scrcpy: \(line)")
                }
            }
        }
        process.terminationHandler = { [weak self, weak process] terminated in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            let remainingLines = outputCapture.append(
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            )
            DispatchQueue.main.async {
                guard let self,
                      let process,
                      self.runningProcesses[device.id] === process else {
                    return
                }
                self.runningProcesses.removeValue(forKey: device.id)
                let status = terminated.terminationStatus
                for line in remainingLines {
                    log("scrcpy: \(line)")
                }
                self.restoreConnectedStateOrStop(
                    deviceID: device.id,
                    detail: status == 0 ? "" : outputCapture.failureDetail
                )
                log("Primary scrcpy screen exited while the ADB session remains connected: \(device.name), status=\(status)")
            }
        }

        do {
            try process.run()
        } catch {
            throw ScreenSessionError.scrcpyLaunchFailed(error.localizedDescription)
        }
        runningProcesses[device.id] = process
        var running = session(for: device.id)
        running.phase = .running
        running.processIdentifier = process.processIdentifier
        running.detail = "\(running.transport?.rawValue ?? "ADB") · \(running.adbSerial)"
        sessions[device.id] = running
        log(
            "scrcpy session started: \(device.name), serial=\(running.adbSerial), pid=\(process.processIdentifier)"
        )
    }

    private func launchAppVirtualDisplayProcess(
        key: AppVirtualDisplayKey,
        app: ManagedAndroidApp,
        device: Device,
        arguments: [String],
        configuration: SessionLaunchConfiguration,
        log: @escaping (String) -> Void
    ) throws {
        let process = Process()
        let outputPipe = Pipe()
        let outputCapture = ScrcpyOutputCapture()
        process.executableURL = URL(fileURLWithPath: configuration.scrcpyPath)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = configuration.adbPath
        environment.removeValue(forKey: "SDL_MAC_BACKGROUND_APP")
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let lines = outputCapture.append(handle.availableData)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                for line in lines {
                    log("scrcpy app virtual display: \(line)")
                }
            }
        }
        process.terminationHandler = { [weak self, weak process] terminated in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            let remainingLines = outputCapture.append(
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            )
            DispatchQueue.main.async {
                guard let self,
                      let process,
                      self.appVirtualDisplayProcesses[key] === process else {
                    return
                }
                self.appVirtualDisplayProcesses.removeValue(forKey: key)
                for line in remainingLines {
                    log("scrcpy app virtual display: \(line)")
                }
                log(
                    "App virtual display exited: \(app.packageName), status=\(terminated.terminationStatus)"
                )
            }
        }
        do {
            try process.run()
        } catch {
            throw ScreenSessionError.scrcpyLaunchFailed(error.localizedDescription)
        }
        appVirtualDisplayProcesses[key] = process
        log(
            "App virtual display started: device=\(device.name), package=\(app.packageName), " +
                "launchID=\(key.launchID.uuidString), pid=\(process.processIdentifier)"
        )
    }

    private func stopAppVirtualDisplays(deviceID: UUID) {
        let taskKeys = appVirtualDisplayTasks.keys.filter { $0.deviceID == deviceID }
        for key in taskKeys {
            appVirtualDisplayTasks.removeValue(forKey: key)?.cancel()
        }
        let processKeys = appVirtualDisplayProcesses.keys.filter { $0.deviceID == deviceID }
        for key in processKeys {
            if let process = appVirtualDisplayProcesses.removeValue(forKey: key), process.isRunning {
                process.terminate()
            }
        }
    }

    private func finishAppVirtualDisplayLaunch(_ identifier: AppVirtualDisplayIdentifier) {
        let remaining = appVirtualDisplayLaunchCounts[identifier, default: 0] - 1
        if remaining > 0 {
            appVirtualDisplayLaunchCounts[identifier] = remaining
        } else {
            appVirtualDisplayLaunchCounts.removeValue(forKey: identifier)
        }
    }

    private func restoreConnectedStateOrStop(deviceID: UUID, detail: String = "") {
        var snapshot = session(for: deviceID)
        snapshot.processIdentifier = nil
        if !snapshot.adbSerial.isEmpty, snapshot.transport != nil, snapshot.preflight != nil {
            snapshot.phase = .connected
            snapshot.detail = detail.isEmpty
                ? "\(snapshot.transport?.rawValue ?? "ADB") · \(snapshot.adbSerial)"
                : detail
        } else {
            snapshot.phase = .stopped
            snapshot.detail = detail
        }
        sessions[deviceID] = snapshot
    }

    private func startBatteryRefresh(
        deviceID: UUID,
        adbSerial: String,
        adbPath: String
    ) {
        batteryRefreshTasks.removeValue(forKey: deviceID)?.cancel()
        batteryRefreshTasks[deviceID] = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: ScreenSessionConstants.batteryRefreshIntervalNanoseconds
                    )
                } catch {
                    return
                }
                guard let self else { return }
                let current = self.session(for: deviceID)
                guard current.adbSerial == adbSerial,
                      current.phase.supportsBatteryInformation else {
                    return
                }
                let result = await SessionProcessRunner.run(
                    executable: adbPath,
                    arguments: ["-s", adbSerial, "shell", "dumpsys battery"],
                    timeout: 5
                )
                guard !Task.isCancelled,
                      result.succeeded,
                      let batteryLevel = parseBatteryLevel(result.output) else {
                    continue
                }
                var snapshot = self.session(for: deviceID)
                guard snapshot.adbSerial == adbSerial,
                      snapshot.phase.supportsBatteryInformation else {
                    return
                }
                snapshot.preflight?.batteryLevel = batteryLevel
                self.sessions[deviceID] = snapshot
            }
        }
    }

    private func update(_ deviceID: UUID, phase: ScreenSessionPhase, detail: String) {
        if !phase.supportsBatteryInformation {
            batteryRefreshTasks.removeValue(forKey: deviceID)?.cancel()
        }
        var snapshot = session(for: deviceID)
        snapshot.phase = phase
        snapshot.detail = detail
        sessions[deviceID] = snapshot
    }
}

private func preflight(
    candidate: ResolvedConnectionCandidate,
    adbPath: String
) async -> ConnectionRaceOutcome {
    let result = await SessionProcessRunner.run(
        executable: adbPath,
        arguments: ["-s", candidate.adbSerial, "shell", ScreenSessionConstants.preflightCommand],
        timeout: 7
    )
    guard result.succeeded else {
        return ConnectionRaceOutcome(
            candidate: candidate,
            preflight: nil,
            error: result.failureDetail
        )
    }
    do {
        return ConnectionRaceOutcome(
            candidate: candidate,
            preflight: try parsePreflight(result.output),
            error: nil
        )
    } catch {
        return ConnectionRaceOutcome(
            candidate: candidate,
            preflight: nil,
            error: error.localizedDescription
        )
    }
}

private func buildScrcpyArguments(
    device: Device,
    adbSerial: String,
    automaticVideoEncoder: RemoteVideoEncoder?
) -> [String] {
    let options = device.scrcpyOptions
    var arguments = [
        "--serial", adbSerial,
        "--window-title", "Screen Remote — \(device.name)"
    ]
    if options.maxSize > 0 {
        arguments += ["--max-size", String(options.maxSize)]
    }
    if !options.videoBitrate.isEmpty {
        arguments += ["--video-bit-rate", options.videoBitrate]
    }
    if options.maxFPS > 0 {
        arguments += ["--max-fps", String(options.maxFPS)]
    }
    if !options.videoEncoder.isEmpty {
        arguments += ["--video-encoder", options.videoEncoder]
    } else if let automaticVideoEncoder {
        arguments += [
            "--video-codec", automaticVideoEncoder.codec,
            "--video-encoder", automaticVideoEncoder.name
        ]
    }
    if options.enableAudio {
        if !options.audioBitrate.isEmpty {
            arguments += ["--audio-bit-rate", options.audioBitrate]
        }
        if !options.audioEncoder.isEmpty {
            arguments += ["--audio-encoder", options.audioEncoder]
        }
    } else {
        arguments.append("--no-audio")
    }
    if !options.clipboardSync {
        arguments.append("--no-clipboard-autosync")
    }
    if options.turnScreenOff {
        arguments.append("--turn-screen-off")
    }
    if options.powerOffOnClose && options.cleanupOnDisconnect {
        arguments.append("--power-off-on-close")
    }
    if options.keepDeviceAwake {
        arguments.append("--stay-awake")
    }
    if !options.cleanupOnDisconnect {
        arguments.append("--no-cleanup")
    }
    if options.ignoreVideoEncoderConstraints {
        arguments.append("--ignore-video-encoder-constraints")
    }
    if options.useADBForward {
        arguments.append("--force-adb-forward")
    }
    if options.newDisplayEnabled {
        if options.newDisplayWidth > 0, options.newDisplayHeight > 0 {
            var newDisplay = "\(options.newDisplayWidth)x\(options.newDisplayHeight)"
            if options.newDisplayDPI > 0 {
                newDisplay += "/\(options.newDisplayDPI)"
            }
            arguments.append("--new-display=\(newDisplay)")
        } else {
            arguments.append("--new-display")
        }
        if !options.virtualDisplaySystemDecorations {
            arguments.append("--no-vd-system-decorations")
        }
        if options.preserveVirtualDisplayContent {
            arguments.append("--no-vd-destroy-content")
        }
    }
    if !options.startApp.isEmpty {
        arguments += ["--start-app", options.startApp]
    }
    return arguments
}

private func resolveAutomaticVideoEncoder(
    device: Device,
    adbSerial: String,
    configuration: SessionLaunchConfiguration,
    log: @escaping (String) -> Void
) async -> RemoteVideoEncoder? {
    guard device.scrcpyOptions.videoEncoder.isEmpty else { return nil }

    var environment = ProcessInfo.processInfo.environment
    environment["ADB"] = configuration.adbPath
    let result = await SessionProcessRunner.run(
        executable: configuration.scrcpyPath,
        arguments: ["--serial", adbSerial, "--list-encoders"],
        environment: environment,
        timeout: 15
    )
    guard result.succeeded else {
        log("Automatic video encoder detection failed; using the scrcpy default: \(result.failureDetail)")
        return nil
    }

    let encoders = parseRemoteVideoEncoders("\(result.output)\n\(result.error)")
    guard let selected = selectAutomaticVideoEncoder(from: encoders) else { return nil }
    log("Automatic video encoder selected: codec=\(selected.codec), encoder=\(selected.name)")
    return selected
}

private func parseRemoteVideoEncoders(_ output: String) -> Set<RemoteVideoEncoder> {
    let pattern = #"--video-codec=([^\s]+)\s+--video-encoder=['"]?([^'"\s]+)"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(output.startIndex..., in: output)
    return Set(expression.matches(in: output, range: range).compactMap { match in
        guard match.numberOfRanges >= 3,
              let codecRange = Range(match.range(at: 1), in: output),
              let nameRange = Range(match.range(at: 2), in: output) else {
            return nil
        }
        return RemoteVideoEncoder(
            codec: String(output[codecRange]).lowercased(),
            name: String(output[nameRange])
        )
    })
}

private func selectAutomaticVideoEncoder(
    from encoders: Set<RemoteVideoEncoder>
) -> RemoteVideoEncoder? {
    let googleH264 = "OMX.google.h264.encoder"
    let googleVP8 = "OMX.google.vp8.encoder"
    guard encoders.count == 2,
          encoders.contains(where: {
              $0.codec == "h264" && $0.name.caseInsensitiveCompare(googleH264) == .orderedSame
          }) else {
        return nil
    }
    return encoders.first {
        $0.codec == "vp8" && $0.name.caseInsensitiveCompare(googleVP8) == .orderedSame
    }
}

private func resolveCandidates(
    _ connections: [DeviceConnection],
    mdnsOutput: String
) -> [ResolvedConnectionCandidate] {
    let mdnsServices = parseMDNSEndpoints(mdnsOutput)
    return connections
        .sorted { $0.priority < $1.priority }
        .compactMap { connection in
            let serial: String
            switch connection.transport {
            case .usb:
                serial = connection.serial.trimmingCharacters(in: .whitespacesAndNewlines)
            case .tcp:
                let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
                serial = hostPort(host: host, port: connection.port)
            case .mdns:
                let configured = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
                let configuredSerial = mdnsDeviceSerial(configured)
                serial = mdnsServices.first {
                    $0.service.caseInsensitiveCompare(configured) == .orderedSame
                        || $0.endpoint.caseInsensitiveCompare(configured) == .orderedSame
                        || mdnsDeviceSerial($0.service).caseInsensitiveCompare(configuredSerial) == .orderedSame
                }?.endpoint ?? configured
            }
            guard !serial.isEmpty else { return nil }
            return ResolvedConnectionCandidate(connection: connection, adbSerial: serial)
        }
}

private func parseConnectedADBDevices(_ output: String) -> [ADBConnectedDevice] {
    output
        .split(whereSeparator: \.isNewline)
        .dropFirst()
        .compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2 else { return nil }
            return ADBConnectedDevice(serial: fields[0], state: fields[1])
        }
}

private func parseMDNSEndpoints(_ output: String) -> [(service: String, endpoint: String)] {
    output
        .split(whereSeparator: \.isNewline)
        .compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2,
                  !line.lowercased().contains("list of discovered"),
                  fields.contains(where: { $0.localizedCaseInsensitiveContains("_adb-tls-connect") }),
                  let endpoint = fields.last(where: { looksLikeNetworkEndpoint($0) }) else {
                return nil
            }
            return (fields[0], endpoint)
        }
}

private func parsePreflight(_ output: String) throws -> ScreenDevicePreflight {
    func section(_ marker: String, next: String?) -> String {
        let suffix = output.components(separatedBy: marker).dropFirst().joined(separator: marker)
        guard let next else { return suffix.trimmingCharacters(in: .whitespacesAndNewlines) }
        return suffix.components(separatedBy: next).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    guard output.contains(ScreenSessionConstants.modelMarker),
          output.contains(ScreenSessionConstants.displayMarker) else {
        throw ScreenSessionError.invalidPreflight
    }
    return ScreenDevicePreflight(
        model: section(ScreenSessionConstants.modelMarker, next: ScreenSessionConstants.androidMarker)
            .firstNonemptyLine,
        androidVersion: section(ScreenSessionConstants.androidMarker, next: ScreenSessionConstants.serialMarker)
            .firstNonemptyLine,
        serial: section(ScreenSessionConstants.serialMarker, next: ScreenSessionConstants.fingerprintMarker)
            .firstNonemptyLine,
        buildFingerprint: section(ScreenSessionConstants.fingerprintMarker, next: ScreenSessionConstants.displayMarker)
            .firstNonemptyLine,
        displaySize: section(ScreenSessionConstants.displayMarker, next: ScreenSessionConstants.batteryMarker)
            .components(separatedBy: .newlines)
            .first { $0.lowercased().contains("size") }
            ?? "",
        batteryLevel: parseBatteryLevel(
            section(ScreenSessionConstants.batteryMarker, next: nil)
        )
    )
}

private func parseBatteryLevel(_ output: String) -> Int? {
    output
        .components(separatedBy: .newlines)
        .lazy
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { $0.lowercased().hasPrefix("level:") }?
        .split(separator: ":", maxSplits: 1)
        .last
        .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .flatMap { (0...100).contains($0) ? $0 : nil }
}

private func adbConnectSucceeded(_ result: SessionCommandResult) -> Bool {
    let combined = "\(result.output)\n\(result.error)".lowercased()
    return combined.contains("connected to") || combined.contains("already connected")
}

private func executablePath(_ configured: String, fallback: ToolDownloadKind) -> String {
    if FileManager.default.isExecutableFile(atPath: configured) {
        return configured
    }
    return ToolLocator.find(fallback) ?? configured
}

private func normalizeADBSerial(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ".:", with: ":")
        .lowercased()
}

private func hostPort(host: String, port: Int) -> String {
    guard !host.isEmpty else { return "" }
    if host.hasPrefix("[") || host.filter({ $0 == ":" }).count <= 1 {
        return "\(host):\(port)"
    }
    return "[\(host)]:\(port)"
}

private func looksLikeNetworkEndpoint(_ value: String) -> Bool {
    if value.hasPrefix("["), let closing = value.firstIndex(of: "]") {
        return Int(value[value.index(after: closing)...].drop(while: { $0 == ":" })) != nil
    }
    guard let separator = value.lastIndex(of: ":") else { return false }
    return Int(value[value.index(after: separator)...]) != nil
}

private func formatCommand(_ command: [String]) -> String {
    command.map { argument in
        let escaped = argument.replacingOccurrences(of: "'", with: "'\\''")
        return argument.contains(where: \.isWhitespace) ? "'\(escaped)'" : escaped
    }.joined(separator: " ")
}

private enum ScreenSessionConstants {
    static let batteryRefreshIntervalNanoseconds: UInt64 = 60_000_000_000
    static let modelMarker = "__SCREEN_REMOTE_MODEL__"
    static let androidMarker = "__SCREEN_REMOTE_ANDROID__"
    static let serialMarker = "__SCREEN_REMOTE_SERIAL__"
    static let fingerprintMarker = "__SCREEN_REMOTE_FINGERPRINT__"
    static let displayMarker = "__SCREEN_REMOTE_DISPLAY__"
    static let batteryMarker = "__SCREEN_REMOTE_BATTERY__"

    static let preflightCommand =
        "echo '\(modelMarker)'; getprop ro.product.model; " +
        "echo '\(androidMarker)'; getprop ro.build.version.release; " +
        "echo '\(serialMarker)'; getprop ro.serialno; " +
        "echo '\(fingerprintMarker)'; getprop ro.build.fingerprint; " +
        "echo '\(displayMarker)'; wm size; " +
        "echo '\(batteryMarker)'; dumpsys battery 2>/dev/null || true"
}

private enum ScreenSessionError: LocalizedError {
    case adbNotFound
    case scrcpyNotFound
    case noConnectionCandidates
    case usbUnavailable
    case connectionRaceFailed(String)
    case commandFailed(String)
    case invalidPreflight
    case scrcpyLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .adbNotFound: String.localizedKey("screenSessionErrorADBNotFound")
        case .scrcpyNotFound: String.localizedKey("screenSessionErrorScrcpyNotFound")
        case .noConnectionCandidates: String.localizedKey("screenSessionErrorNoCandidates")
        case .usbUnavailable: String.localizedKey("screenSessionErrorUSBUnavailable")
        case .connectionRaceFailed(let detail):
            String(format: String.localizedKey("screenSessionErrorRaceFailed %@"), detail)
        case .commandFailed(let detail):
            String(format: String.localizedKey("screenSessionErrorADBCommand %@"), detail)
        case .invalidPreflight:
            String.localizedKey("screenSessionErrorInvalidPreflight")
        case .scrcpyLaunchFailed(let detail):
            String(format: String.localizedKey("screenSessionErrorScrcpyLaunch %@"), detail)
        }
    }
}

private extension SessionCommandResult {
    var failureDetail: String {
        if timedOut { return "timed out" }
        let detail = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { return detail }
        let standardOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return standardOutput.isEmpty ? "exit status \(exitCode)" : standardOutput
    }
}

private extension String {
    var firstNonemptyLine: String {
        components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

}

private enum SessionProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) async -> SessionCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = environment
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                let lock = NSLock()
                var didTimeOut = false
                do {
                    try process.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard process.isRunning else { return }
                        didTimeOut = true
                        process.terminate()
                    }
                    process.waitUntilExit()
                    lock.lock()
                    let timedOut = didTimeOut
                    lock.unlock()
                    continuation.resume(returning: SessionCommandResult(
                        exitCode: process.terminationStatus,
                        output: String(
                            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self
                        ),
                        error: String(
                            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self
                        ),
                        timedOut: timedOut
                    ))
                } catch {
                    continuation.resume(returning: SessionCommandResult(
                        exitCode: 126,
                        output: "",
                        error: error.localizedDescription,
                        timedOut: false
                    ))
                }
            }
        }
    }
}
