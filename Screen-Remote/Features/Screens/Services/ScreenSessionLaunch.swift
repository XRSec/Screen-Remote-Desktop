import AppKit
import Foundation

@MainActor
extension ScreenSessionManager {
    func prepareAndLaunch(
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
        startNativeSession(device: device, nativeSession: nativeSession, log: log)
    }

    func reconnect(
        device: Device,
        configuration: SessionLaunchConfiguration,
        log: @escaping (String) -> Void
    ) {
        guard let current = nativeSessions[device.id] else {
            log("Native scrcpy parameter replacement skipped because no active session is available: \(device.name)")
            return
        }
        pendingVideoSurfaces.removeValue(forKey: device.id)
        pendingNativeSessions.removeValue(forKey: device.id)?.stop(log: log)
        let currentSession = session(for: device.id)
        guard !currentSession.adbSerial.isEmpty else {
            log("Native scrcpy parameter replacement skipped because the ADB serial is unavailable: \(device.name)")
            current.stop(log: log)
            nativeSessions.removeValue(forKey: device.id)
            return
        }

        update(device.id, phase: .reconnecting, detail: currentSession.detail)
        log(
            "Native scrcpy parameter replacement requested: device=\(device.name), " +
                "serial=\(currentSession.adbSerial); retaining the active session until the replacement is ready"
        )
        let replacementSurface = ScrcpyVideoSurface()
        let nativeSession = NativeScrcpySession(
            adbPath: configuration.adbPath,
            serial: currentSession.adbSerial,
            options: device.scrcpyOptions,
            surface: replacementSurface
        )
        pendingVideoSurfaces[device.id] = replacementSurface
        pendingNativeSessions[device.id] = nativeSession
        startReplacementNativeSession(
            device: device,
            previous: current,
            replacement: nativeSession,
            log: log
        )
    }

    private func startReplacementNativeSession(
        device: Device,
        previous: NativeScrcpySession,
        replacement: NativeScrcpySession,
        log: @escaping (String) -> Void
    ) {
        replacement.start(
            log: log,
            ready: { [weak self, weak replacement, weak previous] deviceName in
                DispatchQueue.main.async {
                    guard let self,
                          let replacement,
                          self.pendingNativeSessions[device.id] === replacement else {
                        replacement?.stop(log: log)
                        return
                    }
                    let oldSession = self.nativeSessions[device.id]
                    self.pendingNativeSessions.removeValue(forKey: device.id)
                    if let surface = self.pendingVideoSurfaces.removeValue(forKey: device.id) {
                        self.videoSurfaces[device.id] = surface
                    }
                    self.nativeSessions[device.id] = replacement
                    log("Native scrcpy replacement ready; switching active video session: \(device.name)")
                    (oldSession ?? previous)?.stop(log: log)

                    var running = self.session(for: device.id)
                    running.phase = .running
                    running.processIdentifier = nil
                    running.detail = "\(running.transport?.rawValue ?? "ADB") · \(running.adbSerial) · \(deviceName)"
                    self.sessions[device.id] = running
                    log("Native scrcpy session started: \(device.name), serial=\(running.adbSerial)")
                }
            },
            stopped: { [weak self, weak replacement] error in
                DispatchQueue.main.async {
                    guard let self,
                          let replacement,
                          self.pendingNativeSessions[device.id] === replacement else { return }
                    self.pendingNativeSessions.removeValue(forKey: device.id)
                    self.pendingVideoSurfaces.removeValue(forKey: device.id)
                    if self.nativeSessions[device.id] != nil {
                        var running = self.session(for: device.id)
                        running.phase = .running
                        running.detail = "\(running.transport?.rawValue ?? "ADB") · \(running.adbSerial)"
                        self.sessions[device.id] = running
                        log(
                            "Native scrcpy replacement failed; retaining the previous session: " +
                                "\(device.name), \(error?.localizedDescription ?? "unknown error")"
                        )
                    } else {
                        self.restoreConnectedStateOrStop(
                            deviceID: device.id,
                            detail: error?.localizedDescription ?? ""
                        )
                        if let error {
                            log("Native scrcpy replacement ended: \(device.name), \(error.localizedDescription)")
                        }
                    }
                }
            }
        )
    }

    private func startNativeSession(
        device: Device,
        nativeSession: NativeScrcpySession,
        log: @escaping (String) -> Void
    ) {
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
                    if let self,
                       let nativeSession,
                       self.pendingNativeSessions[device.id] != nil,
                       self.nativeSessions[device.id] === nativeSession {
                        self.nativeSessions.removeValue(forKey: device.id)
                        if let error {
                            log(
                                "Previous native scrcpy session ended during replacement: " +
                                    "\(device.name), \(error.localizedDescription)"
                            )
                        } else {
                            log("Previous native scrcpy session stopped during replacement: \(device.name)")
                        }
                        return
                    }
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

    func applyConnectedState(
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
        resolutionAdjustmentStates[device.id] = ScreenResolutionAdjustmentState(
            currentDisplay: preflight.displayInfo,
            isAdjusted: false
        )
        stopLayoutInspection(deviceID: device.id)
        onSessionConnected?(device, winner.candidate.adbSerial, adbPath)
        startBatteryRefresh(
            deviceID: device.id,
            adbSerial: winner.candidate.adbSerial,
            adbPath: adbPath
        )
    }

    func launchScrcpy(
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

    func launchAppVirtualDisplayProcess(
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

    func stopAppVirtualDisplays(deviceID: UUID) {
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

    func finishAppVirtualDisplayLaunch(_ identifier: AppVirtualDisplayIdentifier) {
        let remaining = appVirtualDisplayLaunchCounts[identifier, default: 0] - 1
        if remaining > 0 {
            appVirtualDisplayLaunchCounts[identifier] = remaining
        } else {
            appVirtualDisplayLaunchCounts.removeValue(forKey: identifier)
        }
    }

    func restoreConnectedStateOrStop(deviceID: UUID, detail: String = "") {
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

    func startBatteryRefresh(
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

    func update(_ deviceID: UUID, phase: ScreenSessionPhase, detail: String) {
        if !phase.supportsBatteryInformation {
            batteryRefreshTasks.removeValue(forKey: deviceID)?.cancel()
        }
        var snapshot = session(for: deviceID)
        snapshot.phase = phase
        snapshot.detail = detail
        sessions[deviceID] = snapshot
    }
}
