import AppKit
import Foundation
import SwiftUI

struct AppSettings: Codable {
    var version = 1
    var appLanguage = AppLanguagePreference.system
    var appTheme = AppThemePreference.system
    var adbPath = ""
    var scrcpyPath = ""
    var androidSDKRoot = AndroidSDKLocator.defaultSDKRoot.path
    var androidCLIPath = ""
    var commandLineToolsPath = ""
    var emulatorPath = ""
    var skinsPath = AndroidSDKLocator.defaultSDKRoot.appendingPathComponent("skins", isDirectory: true).path
    var avdHome = ""
    var downloadAccelerator = "https://v4.gh-proxy.org/"
    var useDownloadAccelerator = false
    var downloadProxy = "127.0.0.1:7897"
    var useDownloadProxy = false
    var downloadProxyType = "http"

    init(
        version: Int = 1, appLanguage: AppLanguagePreference = .system, appTheme: AppThemePreference = .system,
        adbPath: String = "", scrcpyPath: String = "",
        androidSDKRoot: String = AndroidSDKLocator.defaultSDKRoot.path,
        androidCLIPath: String = "", commandLineToolsPath: String = "",
        emulatorPath: String = "",
        skinsPath: String = AndroidSDKLocator.defaultSDKRoot.appendingPathComponent("skins", isDirectory: true).path,
        avdHome: String = "",
        downloadAccelerator: String = "https://v4.gh-proxy.org/", useDownloadAccelerator: Bool = false,
        downloadProxy: String = "127.0.0.1:7897", useDownloadProxy: Bool = false,
        downloadProxyType: String = "http"
    ) {
        self.version = version
        self.appLanguage = appLanguage
        self.appTheme = appTheme
        self.adbPath = adbPath
        self.scrcpyPath = scrcpyPath
        self.androidSDKRoot = androidSDKRoot
        self.androidCLIPath = androidCLIPath
        self.commandLineToolsPath = commandLineToolsPath
        self.emulatorPath = emulatorPath
        self.skinsPath = skinsPath
        self.avdHome = avdHome
        self.downloadAccelerator = downloadAccelerator
        self.useDownloadAccelerator = useDownloadAccelerator
        self.downloadProxy = downloadProxy
        self.useDownloadProxy = useDownloadProxy
        self.downloadProxyType = downloadProxyType
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try values.decodeIfPresent(Int.self, forKey: .version) ?? 1,
            appLanguage: try values.decodeIfPresent(AppLanguagePreference.self, forKey: .appLanguage) ?? .system,
            appTheme: try values.decodeIfPresent(AppThemePreference.self, forKey: .appTheme) ?? .system,
            adbPath: try values.decodeIfPresent(String.self, forKey: .adbPath) ?? "",
            scrcpyPath: try values.decodeIfPresent(String.self, forKey: .scrcpyPath) ?? "",
            androidSDKRoot: try values.decodeIfPresent(String.self, forKey: .androidSDKRoot)
                ?? AndroidSDKLocator.defaultSDKRoot.path,
            androidCLIPath: try values.decodeIfPresent(String.self, forKey: .androidCLIPath) ?? "",
            commandLineToolsPath: try values.decodeIfPresent(String.self, forKey: .commandLineToolsPath) ?? "",
            emulatorPath: try values.decodeIfPresent(String.self, forKey: .emulatorPath) ?? "",
            skinsPath: try values.decodeIfPresent(String.self, forKey: .skinsPath)
                ?? AndroidSDKLocator.defaultSDKRoot.appendingPathComponent("skins", isDirectory: true).path,
            avdHome: try values.decodeIfPresent(String.self, forKey: .avdHome) ?? "",
            downloadAccelerator: try values.decodeIfPresent(String.self, forKey: .downloadAccelerator)
                ?? "https://v4.gh-proxy.org/",
            useDownloadAccelerator: try values.decodeIfPresent(Bool.self, forKey: .useDownloadAccelerator) ?? false,
            downloadProxy: try values.decodeIfPresent(String.self, forKey: .downloadProxy)
                ?? "127.0.0.1:7897",
            useDownloadProxy: try values.decodeIfPresent(Bool.self, forKey: .useDownloadProxy) ?? false,
            downloadProxyType: try values.decodeIfPresent(String.self, forKey: .downloadProxyType) ?? "http"
        )
    }
}

struct StoredDevices: Codable {
    var version = 2
    var groups: [DeviceGroup]
    var devices: [StoredDevice]
}

struct StoredDevice: Codable {
    let id: UUID
    let name: String
    let model: String
    let systemVersion: String
    let battery: Int
    let accent: StoredColor
    let isConnected: Bool
    let groupIDs: [String]
    let connections: [DeviceConnection]
    let scrcpyOptions: ScrcpyDeviceOptions

    init(_ device: Device) {
        id = device.id
        name = device.name
        model = device.model
        systemVersion = device.systemVersion
        battery = device.battery
        accent = StoredColor(device.accent)
        isConnected = device.isConnected
        groupIDs = device.groupIDs.sorted()
        connections = device.connections
        scrcpyOptions = device.scrcpyOptions
    }

    var device: Device {
        Device(
            id: id, name: name, model: model, systemVersion: systemVersion,
            battery: battery, accent: accent.color, isConnected: isConnected,
            groupIDs: Set(groupIDs), connections: connections, scrcpyOptions: scrcpyOptions
        )
    }
}

struct StoredColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .systemIndigo
        func stable(_ value: CGFloat) -> Double { Double((value * 255).rounded() / 255) }
        red = stable(converted.redComponent)
        green = stable(converted.greenComponent)
        blue = stable(converted.blueComponent)
        alpha = stable(converted.alphaComponent)
    }

    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}

enum AppPersistence {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Screen Remote", isDirectory: true)
    static let settingsURL = directory.appendingPathComponent("settings.json")
    static let devicesURL = directory.appendingPathComponent("devices.json")
    static let logsURL = directory.appendingPathComponent("logs.json")
    static let logPageSize = 200
    private static let maxPersistedLogs = 5_000

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            var migrated = AppSettings()
            migrated.adbPath = UserDefaults.standard.string(forKey: "adbPath") ?? ""
            migrated.scrcpyPath = UserDefaults.standard.string(forKey: "scrcpyPath") ?? ""
            migrated.downloadAccelerator = UserDefaults.standard.string(forKey: "downloadAccelerator")
                ?? migrated.downloadAccelerator
            return migrated
        }
        return settings
    }

    static func loadDevices() -> StoredDevices? {
        guard let data = try? Data(contentsOf: devicesURL) else { return nil }
        return try? JSONDecoder().decode(StoredDevices.self, from: data)
    }

    static func loadLogs() -> [SDLLogEntry] {
        loadLogs(offsetFromEnd: 0, limit: nil)
    }

    static func loadLatestLogs(limit: Int = logPageSize) -> [SDLLogEntry] {
        loadLogs(offsetFromEnd: 0, limit: limit)
    }

    static func loadOlderLogs(offsetFromEnd: Int, limit: Int = logPageSize) -> [SDLLogEntry] {
        loadLogs(offsetFromEnd: offsetFromEnd, limit: limit)
    }

    static func hasOlderLogs(afterLoadedCount count: Int) -> Bool {
        loadLogCount() > count
    }

    private static func loadLogs(offsetFromEnd: Int, limit: Int?) -> [SDLLogEntry] {
        guard let data = try? Data(contentsOf: logsURL),
              let logs = try? JSONDecoder().decode([SDLLogEntry].self, from: data) else {
            return []
        }
        guard let limit else { return logs }
        let end = max(0, logs.count - max(0, offsetFromEnd))
        let start = max(0, end - max(0, limit))
        return Array(logs[start..<end])
    }

    private static func loadLogCount() -> Int {
        guard let data = try? Data(contentsOf: logsURL),
              let logs = try? JSONDecoder().decode([SDLLogEntry].self, from: data) else {
            return 0
        }
        return logs.count
    }

    static func saveSettings(_ value: AppSettings) {
        save(value, to: settingsURL)
    }

    static func saveDevices(_ devices: [Device], groups: [DeviceGroup]) {
        save(StoredDevices(groups: groups, devices: devices.map(StoredDevice.init)), to: devicesURL)
    }

    static func saveLogs(_ logs: [SDLLogEntry]) {
        guard !logs.isEmpty else { return }
        var merged = loadLogs()
        var knownIDs = Set(merged.map(\.id))
        for log in logs where knownIDs.insert(log.id).inserted {
            merged.append(log)
        }
        save(Array(merged.suffix(maxPersistedLogs)), to: logsURL)
    }

    static func clearLogs() {
        do {
            try FileManager.default.removeItem(at: logsURL)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            NSLog("Screen Remote: failed to clear %@: %@", logsURL.path, error.localizedDescription)
        }
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Screen Remote: failed to save %@: %@", url.path, error.localizedDescription)
        }
    }
}
