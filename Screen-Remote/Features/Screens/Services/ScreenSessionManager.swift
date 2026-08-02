import AppKit
import Foundation

@MainActor
final class ScreenSessionManager: NSObject, ObservableObject {
    @Published var sessions: [UUID: ScreenSessionSnapshot] = [:]
    @Published var appVirtualDisplayLaunchCounts: [AppVirtualDisplayIdentifier: Int] = [:]
    @Published var layoutInspectorStates: [UUID: ScreenLayoutInspectorState] = [:]
    @Published var resolutionAdjustmentStates: [UUID: ScreenResolutionAdjustmentState] = [:]
    var onSessionConnected: ((Device, String, String) -> Void)?

    var startupTasks: [UUID: Task<Void, Never>] = [:]
    var batteryRefreshTasks: [UUID: Task<Void, Never>] = [:]
    var runningProcesses: [UUID: Process] = [:]
    var nativeSessions: [UUID: NativeScrcpySession] = [:]
    var pendingNativeSessions: [UUID: NativeScrcpySession] = [:]
    var videoSurfaces: [UUID: ScrcpyVideoSurface] = [:]
    var pendingVideoSurfaces: [UUID: ScrcpyVideoSurface] = [:]
    var appVirtualDisplayTasks: [AppVirtualDisplayKey: Task<Void, Never>] = [:]
    var appVirtualDisplayProcesses: [AppVirtualDisplayKey: Process] = [:]
    var layoutInspectorRefreshTasks: [UUID: Task<Void, Never>] = [:]

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
        for session in pendingNativeSessions.values {
            session.stop()
        }
        for task in appVirtualDisplayTasks.values {
            task.cancel()
        }
        for process in appVirtualDisplayProcesses.values where process.isRunning {
            process.terminate()
        }
        for task in layoutInspectorRefreshTasks.values {
            task.cancel()
        }
        startupTasks.removeAll()
        batteryRefreshTasks.removeAll()
        runningProcesses.removeAll()
        nativeSessions.removeAll()
        pendingNativeSessions.removeAll()
        pendingVideoSurfaces.removeAll()
        appVirtualDisplayTasks.removeAll()
        appVirtualDisplayProcesses.removeAll()
        layoutInspectorRefreshTasks.removeAll()
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

    func sendTouch(
        deviceID: UUID,
        action: ScrcpyTouchAction,
        point: CGPoint,
        screenSize: CGSize
    ) {
        nativeSessions[deviceID]?.sendTouch(
            action: action,
            point: point,
            screenSize: screenSize
        )
    }

    func sendMouseMove(
        deviceID: UUID,
        point: CGPoint,
        screenSize: CGSize,
        buttons: UInt32
    ) {
        nativeSessions[deviceID]?.sendMouseMove(
            point: point,
            screenSize: screenSize,
            buttons: buttons
        )
    }

    func sendMouseButton(
        deviceID: UUID,
        action: ScrcpyTouchAction,
        button: ScrcpyMouseButton,
        point: CGPoint,
        screenSize: CGSize,
        buttons: UInt32
    ) {
        nativeSessions[deviceID]?.sendMouseButton(
            action: action,
            button: button,
            point: point,
            screenSize: screenSize,
            buttons: buttons
        )
    }

    func sendMouseScroll(
        deviceID: UUID,
        point: CGPoint,
        screenSize: CGSize,
        horizontal: CGFloat,
        vertical: CGFloat,
        buttons: UInt32
    ) {
        nativeSessions[deviceID]?.sendMouseScroll(
            point: point,
            screenSize: screenSize,
            horizontal: horizontal,
            vertical: vertical,
            buttons: buttons
        )
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
        if pendingNativeSessions[device.id] != nil {
            update(device.id, phase: .reconnecting, detail: session(for: device.id).detail)
            log("Native scrcpy parameter replacement is already in progress: \(device.name)")
            return
        }
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
        stopLayoutInspection(deviceID: deviceID)
        pendingVideoSurfaces.removeValue(forKey: deviceID)
        pendingNativeSessions.removeValue(forKey: deviceID)?.stop(log: log)
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
}
