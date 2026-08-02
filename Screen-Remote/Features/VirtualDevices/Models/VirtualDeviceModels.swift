import AppKit
import Foundation
import SwiftUI

enum VirtualDeviceFormFactor: String, CaseIterable, Identifiable {
    case phone
    case tablet
    case tv
    case wear
    case automotive
    case desktop
    case xr
    case other

    var id: String { rawValue }
    var localizationKey: LocalizedStringKey {
        switch self {
        case .phone: "virtualDeviceFormFactorPhone"
        case .tablet: "virtualDeviceFormFactorTablet"
        case .tv: "virtualDeviceFormFactorTV"
        case .wear: "virtualDeviceFormFactorWear"
        case .automotive: "virtualDeviceFormFactorAutomotive"
        case .desktop: "virtualDeviceFormFactorDesktop"
        case .xr: "virtualDeviceFormFactorXR"
        case .other: "virtualDeviceFormFactorOther"
        }
    }
    var icon: String {
        switch self {
        case .phone: "iphone.gen3"
        case .tablet: "ipad"
        case .tv: "tv"
        case .wear: "applewatch"
        case .automotive: "car"
        case .desktop: "desktopcomputer"
        case .xr: "visionpro"
        case .other: "square.grid.2x2"
        }
    }
}

enum AndroidImageService: String, CaseIterable, Identifiable {
    case googlePlay
    case googleAPIs
    case aosp

    var id: String { rawValue }
    var localizationKey: LocalizedStringKey {
        switch self {
        case .googlePlay: "virtualDeviceImageServiceGooglePlay"
        case .googleAPIs: "virtualDeviceImageServiceGoogleAPIs"
        case .aosp: "virtualDeviceImageServiceAOSP"
        }
    }
}

struct AndroidSystemImage: Identifiable, Hashable {
    let id: String
    let description: String
    let isInstalled: Bool

    var displayName: String {
        let parts = packageParts
        guard parts.count >= 4 else { return description }
        let api = parts[1].replacingOccurrences(of: "android-", with: "API ")
        let flavor: String
        switch parts[2] {
        case "google_apis": flavor = "Google APIs"
        case "google_apis_playstore": flavor = "Google Play"
        case "default": flavor = "AOSP"
        case "android-tv": flavor = "Android TV"
        case "android-wear": flavor = "Wear OS"
        default: flavor = parts[2]
        }
        return "\(api) · \(flavor) · \(parts[3])"
    }

    private var packageParts: [String] {
        let separator: Character = id.contains(";") ? ";" : "/"
        return id.split(separator: separator).map(String.init)
    }

    var canonicalID: String {
        Self.canonicalID(id)
    }

    static func canonicalID(_ value: String) -> String {
        let parts = value
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: ";", with: "/")
            .split(separator: "/")
            .map(String.init)
        guard let systemImagesIndex = parts.lastIndex(of: "system-images") else {
            return parts.joined(separator: ";")
        }
        return parts[systemImagesIndex...].joined(separator: ";")
    }

    var apiLevel: String { packageParts.count > 1 ? packageParts[1].replacingOccurrences(of: "android-", with: "") : "" }
    var apiCategory: String {
        let majorLevel = apiLevel.prefix { $0.isNumber }
        return majorLevel.isEmpty ? apiLevel : String(majorLevel)
    }
    var variant: String { packageParts.count > 2 ? packageParts[2] : "" }
    var architecture: String { packageParts.count > 3 ? packageParts[3] : "" }

    var formFactor: VirtualDeviceFormFactor {
        let value = variant.lowercased()
        if value.contains("wear") { return .wear }
        if value.contains("automotive") || value.contains("atd") { return .automotive }
        if value.contains("tv") { return .tv }
        if value.contains("tablet") { return .tablet }
        if value.contains("desktop") { return .desktop }
        if value.contains("xr") { return .xr }
        return .phone
    }

    var service: AndroidImageService {
        let value = variant.lowercased()
        if value.contains("playstore") || value.contains("google_play") || value.contains("google-tv") {
            return .googlePlay
        }
        if value.contains("google") { return .googleAPIs }
        return .aosp
    }
}

struct AndroidVirtualDevice: Identifiable {
    var id: String { name }
    let name: String
    let device: String
    let path: String
    let target: String
    var serial: String?
    var isRunning: Bool { serial != nil }
}

struct AndroidHardwareProfile: Identifiable, Hashable {
    let id: String
    let name: String
}

struct AndroidSkin: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let formFactor: VirtualDeviceFormFactor
    let displayWidth: Int?
    let displayHeight: Int?
    let previewPath: String?
    let isCustom: Bool

    var detail: String {
        guard let displayWidth, let displayHeight else { return path }
        return "\(displayWidth) × \(displayHeight)"
    }
}

enum VirtualDeviceBootMode: String, CaseIterable, Identifiable {
    case quick
    case cold

    var id: String { rawValue }
    var localizationKey: LocalizedStringKey {
        switch self {
        case .quick: "virtualDeviceBootModeQuick"
        case .cold: "virtualDeviceBootModeCold"
        }
    }
}

struct VirtualDeviceOptions: Equatable {
    var systemImageID = ""
    var formFactor: VirtualDeviceFormFactor = .phone
    var skinName = ""
    var skinPath = ""
    var ramMB = 2_048
    var heapMB = 512
    var storageMB = 6_144
    var sdCardMB = 512
    var cpuCores = 4
    var width = 1_080
    var height = 2_400
    var density = 420
    var gpuMode = "auto"
    var bootMode: VirtualDeviceBootMode = .quick
    var cameraBack = "emulated"
    var keyboard = true
    var audioInput = true
    var audioOutput = true
    var showDeviceFrame = true
}

struct VirtualDeviceConfiguration {
    let sdkRoot: String
    let androidCLIPath: String
    let toolsPath: String
    let emulatorPath: String
    let skinsPath: String
    let avdHome: String
}
