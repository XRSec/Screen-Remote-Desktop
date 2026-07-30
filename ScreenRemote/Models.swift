import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case apps = "appSectionApps"
    case notifications = "appSectionNotifications"
    case messages = "appSectionMessages"
    case photos = "appSectionPhotos"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .apps: "square.grid.2x2"
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
    var groupID: String? = nil
    let connections: [DeviceConnection]
    let scrcpyOptions: ScrcpyDeviceOptions

    init(
        id: UUID = UUID(), name: String, model: String, systemVersion: String,
        battery: Int, accent: Color, isConnected: Bool, groupID: String? = nil,
        connections: [DeviceConnection], scrcpyOptions: ScrcpyDeviceOptions
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.systemVersion = systemVersion
        self.battery = battery
        self.accent = accent
        self.isConnected = isConnected
        self.groupID = groupID
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

    static let allID = "all_devices"
    static let ungroupedID = "ungrouped"
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
    var videoBitrate: String = "8M"
    var maxFPS: Int = 60
    var enableAudio = false
    var clipboardSync = true
    var turnScreenOff = false
    var keepDeviceAwake = true
    var fullscreen = false
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
    @Published var isSidebarCollapsed = false
    @Published var showingSettings = false
    @Published var showingAddDevice = false
    @Published var showingDeviceDiscovery = false
    @Published var showingSDLLogs = false
    @Published var showingCodecTest = false
    @Published var showingGroupManager = false
    @Published var showingVirtualDevices = false
    @Published var appWindowHeight: CGFloat = 680
    @Published var appLanguage: AppLanguagePreference = .system { didSet { persistSettings() } }
    @Published var appTheme: AppThemePreference = .system {
        didSet {
            persistSettings()
            if !isLoadingPersistence { applyThemePreference() }
        }
    }
    @Published var selectedDevice = 0
    @Published var selectedGroupID = DeviceGroup.allID
    @Published var groups = [
        DeviceGroup(id: "work", name: String.localizedKey("deviceGroupWork"), symbol: "briefcase.fill"),
        DeviceGroup(id: "personal", name: String.localizedKey("deviceGroupPersonal"), symbol: "person.fill")
    ] { didSet { persistDevices() } }
    @Published var sdlLogs: [String] = []
    @Published var adbPath = "" { didSet { persistSettings() } }
    @Published var scrcpyPath = "" { didSet { persistSettings() } }
    @Published var androidSDKRoot = AndroidSDKLocator.defaultSDKRoot.path { didSet { persistSettings() } }
    @Published var androidCLIPath = "" { didSet { persistSettings() } }
    @Published var commandLineToolsPath = "" { didSet { persistSettings() } }
    @Published var emulatorPath = "" { didSet { persistSettings() } }
    @Published var avdHome = "" { didSet { persistSettings() } }
    @Published var downloadAccelerator = "https://v4.gh-proxy.org/" { didSet { persistSettings() } }
    @Published var useDownloadAccelerator = false { didSet { persistSettings() } }
    @Published var downloadProxy = "127.0.0.1:7897" { didSet { persistSettings() } }
    @Published var useDownloadProxy = false { didSet { persistSettings() } }
    @Published var downloadProxyType = "http" { didSet { persistSettings() } }

    @Published var devices = [
        Device(
            name: "Pixel 9 Pro",
            model: "Google Pixel",
            systemVersion: "Android 16",
            battery: 86,
            accent: .appIndigo,
            isConnected: true,
            groupID: "personal",
            connections: [
                DeviceConnection(transport: .usb, serial: "10AEAG2YZS0020P", priority: 0),
                DeviceConnection(transport: .tcp, host: "192.168.1.18", port: 5555, priority: 1)
            ],
            scrcpyOptions: ScrcpyDeviceOptions()
        ),
        Device(
            name: "Work Phone",
            model: "Samsung S24",
            systemVersion: "Android 15",
            battery: 42,
            accent: .appCyan,
            isConnected: false,
            groupID: "work",
            connections: [DeviceConnection(transport: .tcp, host: "192.168.1.26", port: 5555)],
            scrcpyOptions: ScrcpyDeviceOptions(enableAudio: true)
        )
    ] { didSet { persistDevices() } }

    private var isLoadingPersistence = true

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
        avdHome = settings.avdHome
        downloadAccelerator = settings.downloadAccelerator
        useDownloadAccelerator = settings.useDownloadAccelerator
        downloadProxy = settings.downloadProxy
        useDownloadProxy = settings.useDownloadProxy
        downloadProxyType = settings.downloadProxyType
        if let stored = AppPersistence.loadDevices() {
            groups = stored.groups
            devices = stored.devices.map(\.device)
        }
        isLoadingPersistence = false
        applyThemePreference()
        persistSettings()
        persistDevices()
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
        appendSDLLog("Device session added: \(device.name) [\(device.primaryConnection?.displayAddress ?? String.localizedKey("deviceConnectionAddressNotConfigured"))], total \(device.connections.count) addresses")
    }

    func selectDevice(at index: Int) {
        guard devices.indices.contains(index) else { return }
        if selectedDevice == index {
            // TODO: When ScrcpyProcessManager is available, re-tap current device to bring its session to foreground.
            appendSDLLog("Waiting for scrcpy process manager: \(devices[index].name)")
            return
        }
        selectedDevice = index
    }

    func visibleDeviceOffsets() -> [(offset: Int, element: Device)] {
        Array(devices.enumerated()).filter { _, device in
            switch selectedGroupID {
            case DeviceGroup.allID: true
            case DeviceGroup.ungroupedID: device.groupID == nil
            default: device.groupID == selectedGroupID
            }
        }
    }

    func addGroup(named name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        groups.append(DeviceGroup(id: UUID().uuidString, name: normalized, symbol: "folder.fill"))
    }

    func removeGroup(id: String) {
        groups.removeAll { $0.id == id }
        for index in devices.indices where devices[index].groupID == id {
            devices[index].groupID = nil
        }
        if selectedGroupID == id { selectedGroupID = DeviceGroup.allID }
    }

    func appendSDLLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        sdlLogs.append("\(formatter.string(from: Date()))  [SDL]  \(message)")
        if sdlLogs.count > 500 { sdlLogs.removeFirst(sdlLogs.count - 500) }
    }

    let apps = [
        PhoneApp(name: "Camera", icon: "camera.fill", color: .purple),
        PhoneApp(name: "Chrome", icon: "globe", color: .blue),
        PhoneApp(name: "Files", icon: "folder.fill", color: .appCyan),
        PhoneApp(name: "Maps", icon: "map.fill", color: .green),
        PhoneApp(name: "Messages", icon: "message.fill", color: .green, badge: 3),
        PhoneApp(name: "Calendar", icon: "calendar", color: .red),
        PhoneApp(name: "Clock", icon: "clock.fill", color: .appIndigo),
        PhoneApp(name: "Music", icon: "music.note", color: .pink),
        PhoneApp(name: "Contacts", icon: "person.crop.circle.fill", color: .blue),
        PhoneApp(name: "Calculator", icon: "plus.forwardslash.minus", color: .orange),
        PhoneApp(name: "Weather", icon: "cloud.sun.fill", color: .appCyan),
        PhoneApp(name: "Settings", icon: "gearshape.fill", color: .gray)
    ]

    let notifications = [
        PhoneNotification(app: "Messages", icon: "message.fill", color: .green, title: "Lina", body: "Got your file, I will reply later.", time: "just now"),
        PhoneNotification(app: "Calendar", icon: "calendar", color: .red, title: "Team standup", body: "Meeting starts in 15 minutes • Remote call", time: "10:15"),
        PhoneNotification(app: "Downloads", icon: "arrow.down.circle.fill", color: .blue, title: "Download finished", body: "design-review.pdf saved to device", time: "09:48")
    ]

    let conversations = [
        Conversation(name: "Lina", initials: "LX", preview: "Got your file, I will reply later.", time: "10:31", color: .purple, unread: true),
        Conversation(name: "Product team", initials: "PX", preview: "Finish first review cycle by Friday.", time: "yesterday", color: .blue),
        Conversation(name: "Chen Yuan", initials: "CY", preview: "Sure, see you tomorrow!", time: "Tuesday", color: .orange),
        Conversation(name: "Verification code", initials: "86", preview: "Your login code is 302814", time: "Monday", color: .gray)
    ]
}
