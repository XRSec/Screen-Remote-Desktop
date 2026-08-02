import AppKit
import Combine
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case screens = "appSectionScreens"
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
        case .screens: "rectangle.inset.filled"
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
