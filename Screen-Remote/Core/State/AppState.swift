import AppKit
import Combine
import SwiftUI
@MainActor
final class AppState: ObservableObject {
    @Published var selection: AppSection = .screens
    let screenWindows = ScreenWindowCoordinator()
    let screenSessions = ScreenSessionManager()
    let deviceApps = DeviceAppsManager()
    @Published var isSidebarCollapsed = false
    @Published var showingSettings = false
    @Published var showingAddDevice = false
    @Published var editingDeviceID: UUID?
    @Published var showingDeviceDiscovery = false
    @Published var showingGroupManager = false
    @Published var showingVirtualDevices = false
    @Published var shouldOpenVirtualDeviceCreator = false
    @Published var appWindowWidth: CGFloat = MainWindowMetrics.preferredWidth
    @Published var appWindowHeight: CGFloat = MainWindowMetrics.preferredHeight
    @Published var appLanguage: AppLanguagePreference = .system {
        didSet {
            AppLocalization.useLanguage(appLanguage.locale?.identifier)
            persistSettings()
        }
    }
    @Published var appTheme: AppThemePreference = .system {
        didSet {
            persistSettings()
            if !isLoadingPersistence { applyThemePreference() }
        }
    }
    @Published var selectedDevice = 0
    @Published var selectedGroupID = DeviceGroup.allID
    @Published var groups: [DeviceGroup] = [] { didSet { persistDevices() } }
    @Published var sdlLogs: [SDLLogEntry] = [] {
        didSet {
            guard !isLoadingPersistence, !isLoadingLogPage else { return }
            scheduleLogPersistence()
        }
    }
    @Published var adbPath = "" { didSet { persistSettings() } }
    @Published var scrcpyPath = "" { didSet { persistSettings() } }
    @Published var androidSDKRoot = AndroidSDKLocator.defaultSDKRoot.path { didSet { persistSettings() } }
    @Published var androidCLIPath = "" { didSet { persistSettings() } }
    @Published var commandLineToolsPath = "" { didSet { persistSettings() } }
    @Published var emulatorPath = "" { didSet { persistSettings() } }
    @Published var skinsPath = AndroidSDKLocator.defaultSDKRoot.appendingPathComponent("skins", isDirectory: true).path {
        didSet { persistSettings() }
    }
    @Published var avdHome = "" { didSet { persistSettings() } }
    @Published var downloadAccelerator = "https://v4.gh-proxy.org/" { didSet { persistSettings() } }
    @Published var useDownloadAccelerator = false { didSet { persistSettings() } }
    @Published var downloadProxy = "127.0.0.1:7897" { didSet { persistSettings() } }
    @Published var useDownloadProxy = false { didSet { persistSettings() } }
    @Published var downloadProxyType = "http" { didSet { persistSettings() } }

    @Published var devices: [Device] = [] { didSet { persistDevices() } }
    @Published private(set) var deviceInformationCache: [UUID: DeviceInformationSnapshot] = [:]
    @Published private(set) var deviceInformationLoading: Set<UUID> = []
    @Published private(set) var deviceInformationErrors: [UUID: String] = [:]

    private var isLoadingPersistence = true
    private var isLoadingLogPage = false
    private var screenSessionObserver: AnyCancellable?
    private var deviceInformationTasks: [UUID: Task<Void, Never>] = [:]
    private var deviceInformationSerials: [UUID: String] = [:]
    private var logPersistenceTask: Task<Void, Never>?
    private var sdlLogWindowController: SDLLogWindowController?

    init() {
        let settings = AppPersistence.loadSettings()
        appLanguage = settings.appLanguage
        appTheme = settings.appTheme
        adbPath = settings.adbPath
        scrcpyPath = settings.scrcpyPath
        androidSDKRoot = settings.androidSDKRoot
        androidCLIPath = settings.androidCLIPath
        commandLineToolsPath = settings.commandLineToolsPath
        emulatorPath = settings.emulatorPath
        skinsPath = settings.skinsPath
        avdHome = settings.avdHome
        downloadAccelerator = settings.downloadAccelerator
        useDownloadAccelerator = settings.useDownloadAccelerator
        downloadProxy = settings.downloadProxy
        useDownloadProxy = settings.useDownloadProxy
        downloadProxyType = settings.downloadProxyType
        if let stored = AppPersistence.loadDevices() {
            var loadedGroups = stored.groups
            let loadedGroupIDs = Set(loadedGroups.map(\.id))
            for index in loadedGroups.indices {
                if let parentID = loadedGroups[index].parentID,
                   parentID == loadedGroups[index].id || !loadedGroupIDs.contains(parentID) {
                    loadedGroups[index].parentID = nil
                }
            }
            groups = loadedGroups
            devices = stored.devices.map {
                var device = $0.device
                device.groupIDs.formIntersection(loadedGroupIDs)
                return device
            }
        }
        sdlLogs = AppPersistence.loadLatestLogs()
        hasOlderSDLLogs = AppPersistence.hasOlderLogs(afterLoadedCount: sdlLogs.count)
        isLoadingPersistence = false
        appendSDLLog("Application log stream initialized", tag: .other)
        applyThemePreference()
        persistSettings()
        persistDevices()
        screenSessions.onSessionConnected = { [weak self] device, serial, adbPath in
            self?.loadDeviceInformation(
                device: device,
                serial: serial,
                adbPath: adbPath,
                force: true
            )
        }
        screenSessionObserver = screenSessions.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var resolvedLocale: Locale {
        appLanguage.locale ?? Locale.current
    }

    private func persistSettings() {
        guard !isLoadingPersistence else { return }
        AppPersistence.saveSettings(AppSettings(
            appLanguage: appLanguage,
            appTheme: appTheme,
            adbPath: adbPath,
            scrcpyPath: scrcpyPath,
            androidSDKRoot: androidSDKRoot,
            androidCLIPath: androidCLIPath,
            commandLineToolsPath: commandLineToolsPath,
            emulatorPath: emulatorPath,
            skinsPath: skinsPath,
            avdHome: avdHome,
            downloadAccelerator: downloadAccelerator,
            useDownloadAccelerator: useDownloadAccelerator,
            downloadProxy: downloadProxy,
            useDownloadProxy: useDownloadProxy,
            downloadProxyType: downloadProxyType
        ))
    }

    private func persistDevices() {
        guard !isLoadingPersistence else { return }
        AppPersistence.saveDevices(devices, groups: groups)
    }

    private func applyThemePreference() {
        guard let app = NSApp else { return }
        app.appearance = appTheme.nsAppearance
        for window in app.windows {
            window.appearance = appTheme.nsAppearance
        }
    }

    func addDevice(_ device: Device) {
        devices.append(device)
        selectedDevice = devices.indices.last ?? 0
        appendSDLLog("Device session added: \(device.name) [\(device.primaryConnection?.displayAddress ?? "Address not configured")], total \(device.connections.count) addresses")
    }

    func updateDevice(_ device: Device) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        let previousDevice = devices[index]
        devices[index] = device
        selectedDevice = index
        appendSDLLog("Device session updated: \(device.name)")

        guard previousDevice.scrcpyOptions != device.scrcpyOptions else { return }
        screenSessions.reconnect(
            device: device,
            configuration: SessionLaunchConfiguration(
                adbPath: executablePath(adbPath, fallback: .adb),
                scrcpyPath: executablePath(scrcpyPath, fallback: .scrcpy)
            ),
            log: { [weak self] message in
                Task { @MainActor in
                    self?.appendSDLLog(message, tag: .connection)
                }
            }
        )
    }

    func updateScreenOptions(
        deviceID: UUID,
        _ mutation: (inout ScrcpyDeviceOptions) -> Void
    ) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        let previousOptions = devices[index].scrcpyOptions
        var device = devices[index]
        mutation(&device.scrcpyOptions)
        normalizeScreenOptions(&device.scrcpyOptions)
        guard device.scrcpyOptions != devices[index].scrcpyOptions else { return }
        let evaluation = SessionParameterController.evaluate(previous: previousOptions, next: device.scrcpyOptions)
        appendSDLLog("Session parameter update:\n" +
            "Applied: \(formatSessionParameters(evaluation.applied))\n" +
            "Requires restart: \(formatSessionParameters(evaluation.requiresRestart))\n" +
            "Unsupported: \(formatSessionParameters(evaluation.unsupported))")

        devices[index] = device
        selectedDevice = index
        appendSDLLog("Device session updated: \(device.name)")
        if !evaluation.applied.isEmpty,
           evaluation.applied.contains(.audioVolume) {
            let volumeApplied = screenSessions.applyLiveAudioVolume(
                deviceID: device.id,
                volume: device.scrcpyOptions.audioVolume
            )
            appendSDLLog(
                volumeApplied
                    ? "Audio volume updated without session reconnect: \(device.name), volume=\(device.scrcpyOptions.audioVolume)"
                    : "Audio volume updated in configuration only; it will apply on next session startup: \(device.name), volume=\(device.scrcpyOptions.audioVolume)",
                tag: .connection
            )
        }
        if !evaluation.requiresRestart.isEmpty {
            screenSessions.reconnect(
                device: device,
                configuration: SessionLaunchConfiguration(
                    adbPath: executablePath(adbPath, fallback: .adb),
                    scrcpyPath: executablePath(scrcpyPath, fallback: .scrcpy)
                ),
                log: { [weak self] message in
                    Task { @MainActor in
                        self?.appendSDLLog(message, tag: .connection)
                    }
                }
            )
        }
        if !evaluation.unsupported.isEmpty {
            appendSDLLog(
                "Unsupported session parameter updates detected in current app version: " +
                "\(device.name), \(formatSessionParameters(evaluation.unsupported))",
                tag: .connection
            )
        }
    }

    private func formatSessionParameters(_ parameters: [SessionParameter]) -> String {
        guard !parameters.isEmpty else { return "" }
        return parameters.map(\.rawValue).joined(separator: ",")
    }

    private func isOnlyAudioVolumeChange(previous: ScrcpyDeviceOptions, next: ScrcpyDeviceOptions) -> Bool {
        var expected = previous
        expected.audioVolume = next.audioVolume
        return expected == next
    }

    func setScreenQuality(deviceID: UUID, preset: ScreenQualityPreset) {
        updateScreenOptions(deviceID: deviceID) { options in
            options.maxSize = preset.maxSize
        }
    }

    private func normalizeScreenOptions(_ options: inout ScrcpyDeviceOptions) {
        options.audioVolume = min(max(options.audioVolume, 1), 3)
        if options.compatibilityMode {
            options.enableAudio = false
            options.gameMode = false
            options.enableHardwareDecoding = false
            options.clipboardSync = false
            options.turnScreenOff = false
            options.powerOffOnClose = false
            options.keepDeviceAwake = false
            options.ignoreVideoEncoderConstraints = false
            options.newDisplayEnabled = false
        }
        if options.gameMode {
            options.maxSize = nearestPreset(
                options.maxSize,
                values: [720, 1080, 1920],
                fallback: 720
            )
            options.videoBitrate = nearestBitratePreset(
                options.videoBitrate,
                values: [1, 2, 4, 8, 12, 20],
                fallback: 2
            )
            options.maxFPS = nearestPreset(
                options.maxFPS,
                values: [60, 90, 120],
                fallback: 60
            )
        }
        if !options.cleanupOnDisconnect {
            options.powerOffOnClose = false
            options.keepDeviceAwake = false
        }
    }

    private func nearestPreset(_ value: Int, values: [Int], fallback: Int) -> Int {
        guard !values.isEmpty else { return fallback }
        guard value > 0 else { return fallback }
        return values.min { abs($0 - value) < abs($1 - value) } ?? fallback
    }

    private func nearestBitratePreset(_ value: String, values: [Int], fallback: Int) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let numeric: Double
        if normalized.hasSuffix("M"), let parsed = Double(normalized.dropLast()) {
            numeric = parsed
        } else if normalized.hasSuffix("K"), let parsed = Double(normalized.dropLast()) {
            numeric = parsed / 1_000
        } else {
            numeric = Double(normalized) ?? Double(fallback)
        }
        let selected = values.min { abs(Double($0) - numeric) < abs(Double($1) - numeric) } ?? fallback
        return "\(selected)M"
    }

    func removeDevice(id: UUID) {
        guard let removalIndex = devices.firstIndex(where: { $0.id == id }) else { return }
        let removedDevice = devices[removalIndex]
        let selectedDeviceID = devices.indices.contains(selectedDevice) ? devices[selectedDevice].id : nil
        let session = screenSessions.session(for: id)

        if session.isConnected || session.isRunning || session.phase.isWorking {
            stopScreenSession(deviceID: id)
        }
        screenWindows.dock(id)
        if editingDeviceID == id { editingDeviceID = nil }
        devices.remove(at: removalIndex)

        if let selectedDeviceID,
           selectedDeviceID != id,
           let preservedIndex = devices.firstIndex(where: { $0.id == selectedDeviceID }) {
            selectedDevice = preservedIndex
        } else if let replacement = visibleDeviceOffsets().first(where: { $0.offset >= removalIndex })
                    ?? visibleDeviceOffsets().last {
            selectedDevice = replacement.offset
        } else {
            selectedDevice = devices.isEmpty ? 0 : min(removalIndex, devices.count - 1)
        }

        appendSDLLog("Device session deleted: \(removedDevice.name)")
    }

    func selectDevice(at index: Int) {
        guard devices.indices.contains(index) else { return }
        guard selectedDevice != index else { return }
        selectedDevice = index
    }

    func startScreenSession(deviceID: UUID? = nil) {
        let device: Device?
        if let deviceID {
            device = devices.first(where: { $0.id == deviceID })
        } else {
            device = devices.indices.contains(selectedDevice) ? devices[selectedDevice] : nil
        }
        guard let device else { return }
        appendSDLLog("Screen session start requested: \(device.name)", tag: .connection)
        screenSessions.start(
            device: device,
            adbPath: adbPath,
            scrcpyPath: scrcpyPath,
            log: { [weak self] message in
                Task { @MainActor in
                    self?.appendSDLLog(message)
                }
            }
        )
    }

    func connectScreenSession(deviceID: UUID) {
        guard let device = devices.first(where: { $0.id == deviceID }) else { return }
        appendSDLLog("ADB connection requested: \(device.name)", tag: .connection)
        screenSessions.connect(
            device: device,
            adbPath: adbPath,
            log: { [weak self] message in
                Task { @MainActor in
                    self?.appendSDLLog(message)
                }
            }
        )
    }

    func loadDeviceInformation(
        device: Device,
        serial: String,
        adbPath: String,
        force: Bool = false
    ) {
        if deviceInformationSerials[device.id] != serial {
            deviceInformationCache.removeValue(forKey: device.id)
            deviceInformationErrors.removeValue(forKey: device.id)
            deviceInformationSerials[device.id] = serial
        }
        guard force || deviceInformationCache[device.id] == nil else { return }
        guard deviceInformationTasks[device.id] == nil else { return }
        deviceInformationTasks[device.id] = Task { [weak self] in
            guard let self else { return }
            self.deviceInformationLoading.insert(device.id)
            self.deviceInformationErrors.removeValue(forKey: device.id)
            defer {
                self.deviceInformationLoading.remove(device.id)
                self.deviceInformationTasks.removeValue(forKey: device.id)
            }
            do {
                let helper = try await DADBHelperRuntime.prepare(
                    serial: serial,
                    configuredADBPath: adbPath
                )
                let output = try await helper.invoke(
                    mainClass: "dadb.helper.ManagementSnapshotMain",
                    arguments: ["device"],
                    timeout: 40
                )
                let snapshot = try parseDeviceInformationResponse(output.standardOutput)
                guard self.screenSessions.session(for: device.id).adbSerial == serial else { return }
                self.deviceInformationCache[device.id] = snapshot
                self.appendSDLLog("Device information cached: \(device.name)")
            } catch {
                self.deviceInformationErrors[device.id] = String.localizedKey("managementDeviceInfoLoadFailed")
                self.appendSDLLog(
                    "Failed to cache device information: \(device.name), \(englishDiagnostic(for: error))"
                )
            }
        }
    }

    func ensureDeviceInformationLoaded(for target: ManagementTarget) {
        loadDeviceInformation(
            device: target.device,
            serial: target.serial,
            adbPath: target.adbPath
        )
    }

    private func englishDiagnostic(for error: Error) -> String {
        if let error = error as? DADBHelperRuntimeError { return error.englishDiagnostic }
        if let error = error as? DeviceInformationProtocolError { return error.englishDiagnostic }
        return String(describing: error)
    }

    func refreshSelectedDeviceApps() {
        guard devices.indices.contains(selectedDevice) else { return }
        let device = devices[selectedDevice]
        let session = screenSessions.session(for: device.id)
        if session.isConnected {
            deviceApps.beginManaging(for: device, appState: self)
            deviceApps.loadApps(for: device, appState: self, force: true)
        } else {
            screenSessions.connect(
                device: device,
                adbPath: adbPath,
                log: { [weak self] message in
                    Task { @MainActor in
                        self?.appendSDLLog(message)
                    }
                }
            )
        }
    }

    func openVirtualDeviceCreator() {
        shouldOpenVirtualDeviceCreator = true
        showingVirtualDevices = true
    }

    func stopScreenSession(deviceID: UUID) {
        if let device = devices.first(where: { $0.id == deviceID }) {
            appendSDLLog("Screen session stop requested: \(device.name)", tag: .connection)
        }
        screenSessions.stop(deviceID: deviceID) { [weak self] message in
            Task { @MainActor in
                self?.appendSDLLog(message)
            }
        }
    }

    func sendScreenKeyEvent(deviceID: UUID, keyCode: Int, action: String) {
        let session = screenSessions.session(for: deviceID)
        guard !session.adbSerial.isEmpty else {
            appendSDLLog("Screen key event skipped because ADB is not connected: action=\(action)")
            return
        }
        let resolvedADBPath = executablePath(adbPath, fallback: .adb)
        Task { [weak self] in
            let result = await SessionProcessRunner.run(
                executable: resolvedADBPath,
                arguments: ["-s", session.adbSerial, "shell", "input", "keyevent", String(keyCode)],
                timeout: 5
            )
            guard let self else { return }
            if result.succeeded {
                self.appendSDLLog("Screen key event sent: action=\(action), keyCode=\(keyCode)")
            } else {
                self.appendSDLLog("Screen key event failed: action=\(action), \(result.failureDetail)")
            }
        }
    }

    func toggleScreenLayoutAnalysis(deviceID: UUID) {
        if screenSessions.layoutInspectorState(for: deviceID).isVisible {
            screenSessions.stopLayoutInspection(deviceID: deviceID)
            appendSDLLog("UI layout analysis stopped: deviceID=\(deviceID.uuidString)")
        } else {
            screenSessions.beginLayoutInspection(
                deviceID: deviceID,
                adbPath: adbPath,
                log: { [weak self] message in self?.appendSDLLog(message) }
            )
        }
    }

    func refreshScreenLayoutAnalysis(deviceID: UUID) {
        screenSessions.requestLayoutInspectionRefresh(
            deviceID: deviceID,
            adbPath: adbPath,
            log: { [weak self] message in self?.appendSDLLog(message) }
        )
    }

    func toggleScreenResolutionAdjustment(
        deviceID: UUID,
        viewportSize: CGSize,
        backingScale: CGFloat
    ) {
        screenSessions.toggleResolutionAdjustment(
            deviceID: deviceID,
            viewportSize: viewportSize,
            backingScale: backingScale,
            adbPath: adbPath,
            log: { [weak self] message in self?.appendSDLLog(message) },
            onSuccess: { [weak self] restored, original in
                guard restored else { return }
                self?.screenWindows.restoreOriginalDisplayWindow(
                    deviceID: deviceID,
                    originalDisplay: original
                )
            }
        )
    }

    func visibleDeviceOffsets() -> [(offset: Int, element: Device)] {
        let visibleGroupIDs = selectedGroupID == DeviceGroup.allID
            ? Set<String>()
            : groupDescendantIDs(including: selectedGroupID)
        return Array(devices.enumerated()).filter { _, device in
            selectedGroupID == DeviceGroup.allID
                || !device.groupIDs.isDisjoint(with: visibleGroupIDs)
        }
    }

    func addGroup(named name: String, parentID: String? = nil) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let normalizedParentID = parentID == DeviceGroup.allID ? nil : parentID
        guard normalizedParentID == nil || groups.contains(where: { $0.id == normalizedParentID }) else { return }
        groups.append(DeviceGroup(
            id: UUID().uuidString, name: normalized, symbol: "folder.fill",
            parentID: normalizedParentID
        ))
    }

    func removeGroup(id: String) {
        let removedIDs = groupDescendantIDs(including: id)
        groups.removeAll { removedIDs.contains($0.id) }
        for index in devices.indices {
            devices[index].groupIDs.subtract(removedIDs)
        }
        if removedIDs.contains(selectedGroupID) { selectedGroupID = DeviceGroup.allID }
    }

    func groupTree(parentID: String? = nil) -> [DeviceGroupTreeNode] {
        groups
            .filter { $0.parentID == parentID }
            .map {
                let children = groupTree(parentID: $0.id)
                return DeviceGroupTreeNode(group: $0, children: children.isEmpty ? nil : children)
            }
    }

    func flattenedGroups() -> [FlattenedDeviceGroup] {
        func flatten(_ nodes: [DeviceGroupTreeNode], depth: Int) -> [FlattenedDeviceGroup] {
            nodes.flatMap { node in
                [FlattenedDeviceGroup(group: node.group, depth: depth)]
                    + flatten(node.children ?? [], depth: depth + 1)
            }
        }
        return flatten(groupTree(), depth: 0)
    }

    func groupDescendantIDs(including id: String) -> Set<String> {
        var result: Set<String> = [id]
        var pending = [id]
        while let parentID = pending.popLast() {
            let childIDs = groups.lazy.filter { $0.parentID == parentID }.map(\.id)
            for childID in childIDs where result.insert(childID).inserted {
                pending.append(childID)
            }
        }
        return result
    }

    func appendSDLLog(_ message: String, tag: SDLLogTag? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        sdlLogs.append(SDLLogEntry(
            timestamp: formatter.string(from: Date()),
            tag: tag ?? SDLLogTag.infer(from: message),
            message: message
        ))
        if loadedOlderSDLLogPages == 0, sdlLogs.count > AppPersistence.logPageSize {
            sdlLogs.removeFirst(sdlLogs.count - AppPersistence.logPageSize)
        }
    }

    private func scheduleLogPersistence() {
        logPersistenceTask?.cancel()
        logPersistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            AppPersistence.saveLogs(self.sdlLogs)
            self.logPersistenceTask = nil
        }
    }

    func refreshSDLLogs() {
        isLoadingLogPage = true
        loadedOlderSDLLogPages = 0
        sdlLogs = AppPersistence.loadLatestLogs()
        hasOlderSDLLogs = AppPersistence.hasOlderLogs(afterLoadedCount: sdlLogs.count)
        isLoadingLogPage = false
    }

    @Published private(set) var hasOlderSDLLogs = false
    private var loadedOlderSDLLogPages = 0

    func loadOlderSDLLogs() {
        guard !isLoadingLogPage, hasMoreOlderSDLLogs else { return }
        isLoadingLogPage = true
        let olderLogs = AppPersistence.loadOlderLogs(
            offsetFromEnd: sdlLogs.count,
            limit: AppPersistence.logPageSize
        )
        if olderLogs.isEmpty {
            hasOlderSDLLogs = false
        } else {
            sdlLogs.insert(contentsOf: olderLogs, at: 0)
            loadedOlderSDLLogPages += 1
            hasOlderSDLLogs = AppPersistence.hasOlderLogs(afterLoadedCount: sdlLogs.count)
        }
        isLoadingLogPage = false
    }

    private var hasMoreOlderSDLLogs: Bool {
        hasOlderSDLLogs || AppPersistence.hasOlderLogs(afterLoadedCount: sdlLogs.count)
    }

    func clearSDLLogs() {
        sdlLogs.removeAll()
        AppPersistence.clearLogs()
        hasOlderSDLLogs = false
        loadedOlderSDLLogPages = 0
    }

    func openSDLLogsWindow() {
        if sdlLogWindowController == nil {
            sdlLogWindowController = SDLLogWindowController(appState: self)
        }
        sdlLogWindowController?.showWindowAndActivate()
    }

    let apps: [PhoneApp] = []
    let notifications: [PhoneNotification] = []
    let conversations: [Conversation] = []
}

private extension SDLLogTag {
    static func infer(from message: String) -> SDLLogTag {
        let value = message.lowercased()
        if value.contains("scrcpy-server") || value.contains("scrcpy server") { return .scrcpyServer }
        if value.contains("audio") { return .audio }
        if value.contains("video") { return .video }
        if value.contains("control") { return .control }
        if value.contains("socket") || value.contains("forward") { return .socks }
        if value.contains("render") || value.contains("frame") || value.contains("display") { return .render }
        if value.contains("adb") { return .adb }
        if value.contains("app") { return .apps }
        if value.contains("file") || value.contains("directory") { return .files }
        if value.contains("device") { return .device }
        if value.contains("session") || value.contains("connect") || value.contains("start") || value.contains("stop") {
            return .connection
        }
        return .other
    }
}
