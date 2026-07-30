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
        emulatorPath: String = "", avdHome: String = "",
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
    var version = 1
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
    let groupID: String?
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
        groupID = device.groupID
        connections = device.connections
        scrcpyOptions = device.scrcpyOptions
    }

    var device: Device {
        Device(
            id: id, name: name, model: model, systemVersion: systemVersion,
            battery: battery, accent: accent.color, isConnected: isConnected,
            groupID: groupID, connections: connections, scrcpyOptions: scrcpyOptions
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

    static func saveSettings(_ value: AppSettings) {
        save(value, to: settingsURL)
    }

    static func saveDevices(_ devices: [Device], groups: [DeviceGroup]) {
        save(StoredDevices(groups: groups, devices: devices.map(StoredDevice.init)), to: devicesURL)
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
