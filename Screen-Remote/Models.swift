import AppKit
import Combine
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case deviceInfo = "appSectionDeviceInfo"
    case utilities = "appSectionUtilities"
    case files = "appSectionFiles"
    case apps = "appSectionApps"
    case processes = "appSectionProcesses"
    case portForward = "appSectionPortForward"
    case notifications = "appSectionNotifications"
    case messages = "appSectionMessages"
    case photos = "appSectionPhotos"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var icon: String {
        switch self {
        case .deviceInfo: "info.circle"
        case .utilities: "wrench.and.screwdriver"
        case .files: "folder"
        case .apps: "square.grid.2x2"
        case .processes: "waveform.path.ecg"
        case .portForward: "arrow.left.arrow.right"
        case .notifications: "bell"
        case .messages: "message"
        case .photos: "photo.on.rectangle.angled"
        }
    }
}

enum AppLanguagePreference: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }
}

enum AppThemePreference: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct Device: Identifiable {
    let id: UUID
    let name: String
    let model: String
    let systemVersion: String
    let battery: Int
    let accent: Color
    var isConnected: Bool
    var groupIDs: Set<String>
    let connections: [DeviceConnection]
    let scrcpyOptions: ScrcpyDeviceOptions

    init(
        id: UUID = UUID(), name: String, model: String, systemVersion: String,
        battery: Int, accent: Color, isConnected: Bool, groupIDs: Set<String> = [],
        connections: [DeviceConnection], scrcpyOptions: ScrcpyDeviceOptions
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.systemVersion = systemVersion
        self.battery = battery
        self.accent = accent
        self.isConnected = isConnected
        self.groupIDs = groupIDs
        self.connections = connections
        self.scrcpyOptions = scrcpyOptions
    }

    var primaryConnection: DeviceConnection? {
        connections.min { $0.priority < $1.priority }
    }
}

struct DeviceGroup: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var symbol: String
    var parentID: String? = nil

    static let allID = "all_devices"
}

struct DeviceGroupTreeNode: Identifiable {
    let group: DeviceGroup
    let children: [DeviceGroupTreeNode]?

    var id: String { group.id }
}

struct FlattenedDeviceGroup: Identifiable {
    let group: DeviceGroup
    let depth: Int

    var id: String { group.id }
}

enum DeviceTransport: String, CaseIterable, Identifiable, Codable {
    case tcp = "TCP/IP"
    case usb = "USB"
    case mdns = "mDNS"

    var id: String { rawValue }
}

struct DeviceConnection: Identifiable, Codable {
    let id: UUID
    var transport: DeviceTransport
    var host: String = ""
    var port: Int = 5555
    var serial: String = ""
    var priority: Int = 0

    init(
        id: UUID = UUID(), transport: DeviceTransport, host: String = "", port: Int = 5555,
        serial: String = "", priority: Int = 0
    ) {
        self.id = id
        self.transport = transport
        self.host = host
        self.port = port
        self.serial = serial
        self.priority = priority
    }

    var displayAddress: String {
        switch transport {
        case .tcp: host.isEmpty ? String.localizedKey("deviceConnectionAddressNotConfigured") : "\(host):\(port)"
        case .usb: serial.isEmpty ? String.localizedKey("deviceConnectionSerialNotConfigured") : serial
        case .mdns: host.isEmpty ? String.localizedKey("deviceConnectionServiceNotConfigured") : host
        }
    }
}

struct ScrcpyDeviceOptions: Codable {
    var maxSize: Int = 0
    var videoBitrate: String = "4M"
    var maxFPS: Int = 60
    var videoEncoder = ""
    var videoDecoder = ""
    var enableAudio = false
    var audioBitrate = "128K"
    var audioEncoder = ""
    var audioDecoder = ""
    var audioVolume = 1.0
    var clipboardSync = true
    var turnScreenOff = false
    var powerOffOnClose = false
    var cleanupOnDisconnect = true
    var keepControllerAwake = false
    var keepDeviceAwake = true
    var ignoreVideoEncoderConstraints = false
    var compatibilityMode = false
    var gameMode = false
    var showFloatingBall = true
    var enableHardwareDecoding = true
    var useADBForward = false
    var newDisplayEnabled = false
    var virtualDisplaySystemDecorations = true
    var preserveVirtualDisplayContent = false
    var startApp = ""
    var newDisplayWidth = 0
    var newDisplayHeight = 0
    var newDisplayDPI = 0

    init(
        maxSize: Int = 0, videoBitrate: String = "4M", maxFPS: Int = 60,
        videoEncoder: String = "", videoDecoder: String = "",
        enableAudio: Bool = false, audioBitrate: String = "128K",
        audioEncoder: String = "", audioDecoder: String = "", audioVolume: Double = 1.0,
        clipboardSync: Bool = true, turnScreenOff: Bool = false, powerOffOnClose: Bool = false,
        cleanupOnDisconnect: Bool = true, keepControllerAwake: Bool = false,
        keepDeviceAwake: Bool = true, ignoreVideoEncoderConstraints: Bool = false,
        compatibilityMode: Bool = false, gameMode: Bool = false,
        showFloatingBall: Bool = true, enableHardwareDecoding: Bool = true,
        useADBForward: Bool = false,
        newDisplayEnabled: Bool = false, virtualDisplaySystemDecorations: Bool = true,
        preserveVirtualDisplayContent: Bool = false, startApp: String = "",
        newDisplayWidth: Int = 0, newDisplayHeight: Int = 0, newDisplayDPI: Int = 0
    ) {
        self.maxSize = maxSize
        self.videoBitrate = videoBitrate
        self.maxFPS = maxFPS
        self.videoEncoder = videoEncoder
        self.videoDecoder = videoDecoder
        self.enableAudio = enableAudio
        self.audioBitrate = audioBitrate
        self.audioEncoder = audioEncoder
        self.audioDecoder = audioDecoder
        self.audioVolume = audioVolume
        self.clipboardSync = clipboardSync
        self.turnScreenOff = turnScreenOff
        self.powerOffOnClose = powerOffOnClose
        self.cleanupOnDisconnect = cleanupOnDisconnect
        self.keepControllerAwake = keepControllerAwake
        self.keepDeviceAwake = keepDeviceAwake
        self.ignoreVideoEncoderConstraints = ignoreVideoEncoderConstraints
        self.compatibilityMode = compatibilityMode
        self.gameMode = gameMode
        self.showFloatingBall = showFloatingBall
        self.enableHardwareDecoding = enableHardwareDecoding
        self.useADBForward = useADBForward
        self.newDisplayEnabled = newDisplayEnabled
        self.virtualDisplaySystemDecorations = virtualDisplaySystemDecorations
        self.preserveVirtualDisplayContent = preserveVirtualDisplayContent
        self.startApp = startApp
        self.newDisplayWidth = newDisplayWidth
        self.newDisplayHeight = newDisplayHeight
        self.newDisplayDPI = newDisplayDPI
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxSize: try values.decodeIfPresent(Int.self, forKey: .maxSize) ?? 0,
            videoBitrate: try values.decodeIfPresent(String.self, forKey: .videoBitrate) ?? "4M",
            maxFPS: try values.decodeIfPresent(Int.self, forKey: .maxFPS) ?? 60,
            videoEncoder: try values.decodeIfPresent(String.self, forKey: .videoEncoder) ?? "",
            videoDecoder: try values.decodeIfPresent(String.self, forKey: .videoDecoder) ?? "",
            enableAudio: try values.decodeIfPresent(Bool.self, forKey: .enableAudio) ?? false,
            audioBitrate: try values.decodeIfPresent(String.self, forKey: .audioBitrate) ?? "128K",
            audioEncoder: try values.decodeIfPresent(String.self, forKey: .audioEncoder) ?? "",
            audioDecoder: try values.decodeIfPresent(String.self, forKey: .audioDecoder) ?? "",
            audioVolume: try values.decodeIfPresent(Double.self, forKey: .audioVolume) ?? 1,
            clipboardSync: try values.decodeIfPresent(Bool.self, forKey: .clipboardSync) ?? true,
            turnScreenOff: try values.decodeIfPresent(Bool.self, forKey: .turnScreenOff) ?? false,
            powerOffOnClose: try values.decodeIfPresent(Bool.self, forKey: .powerOffOnClose) ?? false,
            cleanupOnDisconnect: try values.decodeIfPresent(Bool.self, forKey: .cleanupOnDisconnect) ?? true,
            keepControllerAwake: try values.decodeIfPresent(Bool.self, forKey: .keepControllerAwake) ?? false,
            keepDeviceAwake: try values.decodeIfPresent(Bool.self, forKey: .keepDeviceAwake) ?? true,
            ignoreVideoEncoderConstraints: try values.decodeIfPresent(Bool.self, forKey: .ignoreVideoEncoderConstraints) ?? false,
            compatibilityMode: try values.decodeIfPresent(Bool.self, forKey: .compatibilityMode) ?? false,
            gameMode: try values.decodeIfPresent(Bool.self, forKey: .gameMode) ?? false,
            showFloatingBall: try values.decodeIfPresent(Bool.self, forKey: .showFloatingBall) ?? true,
            enableHardwareDecoding: try values.decodeIfPresent(Bool.self, forKey: .enableHardwareDecoding) ?? true,
            useADBForward: try values.decodeIfPresent(Bool.self, forKey: .useADBForward) ?? false,
            newDisplayEnabled: try values.decodeIfPresent(Bool.self, forKey: .newDisplayEnabled) ?? false,
            virtualDisplaySystemDecorations: try values.decodeIfPresent(Bool.self, forKey: .virtualDisplaySystemDecorations) ?? true,
            preserveVirtualDisplayContent: try values.decodeIfPresent(Bool.self, forKey: .preserveVirtualDisplayContent) ?? false,
            startApp: try values.decodeIfPresent(String.self, forKey: .startApp) ?? "",
            newDisplayWidth: try values.decodeIfPresent(Int.self, forKey: .newDisplayWidth) ?? 0,
            newDisplayHeight: try values.decodeIfPresent(Int.self, forKey: .newDisplayHeight) ?? 0,
            newDisplayDPI: try values.decodeIfPresent(Int.self, forKey: .newDisplayDPI) ?? 0
        )
    }
}

struct PhoneApp: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    var badge: Int = 0
}

struct PhoneNotification: Identifiable {
    let id = UUID()
    let app: String
    let icon: String
    let color: Color
    let title: String
    let body: String
    let time: String
}

struct Conversation: Identifiable {
    let id = UUID()
    let name: String
    let initials: String
    let preview: String
    let time: String
    let color: Color
    var unread: Bool = false
}

@MainActor
final class AppState: ObservableObject {
    @Published var selection: AppSection = .apps
    let screenWindows = ScreenWindowCoordinator()
    let screenSessions = ScreenSessionManager()
    let deviceApps = DeviceAppsManager()
    @Published var isSidebarCollapsed = false
    @Published var showingSettings = false
    @Published var showingAddDevice = false
    @Published var editingDeviceID: UUID?
    @Published var showingDeviceDiscovery = false
    @Published var showingSDLLogs = false
    @Published var showingCodecTest = false
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
    @Published var sdlLogs: [String] = []
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

    private var isLoadingPersistence = true
    private var screenSessionObserver: AnyCancellable?

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
        isLoadingPersistence = false
        applyThemePreference()
        persistSettings()
        persistDevices()
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
        devices[index] = device
        selectedDevice = index
        appendSDLLog("Device session updated: \(device.name)")
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
        screenSessions.start(
            device: device,
            adbPath: adbPath,
            scrcpyPath: scrcpyPath,
            log: { [weak self] message in self?.appendSDLLog(message) }
        )
    }

    func connectScreenSession(deviceID: UUID) {
        guard let device = devices.first(where: { $0.id == deviceID }) else { return }
        screenSessions.connect(
            device: device,
            adbPath: adbPath,
            log: { [weak self] message in self?.appendSDLLog(message) }
        )
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
                log: { [weak self] message in self?.appendSDLLog(message) }
            )
        }
    }

    func openVirtualDeviceCreator() {
        shouldOpenVirtualDeviceCreator = true
        showingVirtualDevices = true
    }

    func stopScreenSession(deviceID: UUID) {
        screenSessions.stop(deviceID: deviceID) { [weak self] message in
            self?.appendSDLLog(message)
        }
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

    func appendSDLLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        sdlLogs.append("\(formatter.string(from: Date()))  [SDL]  \(message)")
        if sdlLogs.count > 500 { sdlLogs.removeFirst(sdlLogs.count - 500) }
    }

    let apps: [PhoneApp] = []
    let notifications: [PhoneNotification] = []
    let conversations: [Conversation] = []
}
