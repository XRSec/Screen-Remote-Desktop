import AppKit
import Foundation

enum ScreenSessionPhase: String, Equatable {
    case idle
    case checkingExisting
    case racing
    case connected
    case reconnecting
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
        case .reconnecting: "screenSessionReconnecting"
        case .buildingCommand: "screenSessionBuildingCommand"
        case .launching: "screenSessionLaunching"
        case .running: "screenSessionRunning"
        case .stopped: "screenSessionStopped"
        case .failed: "screenSessionFailed"
        }
    }

    var isWorking: Bool {
        switch self {
        case .checkingExisting, .racing, .reconnecting, .buildingCommand, .launching:
            true
        case .idle, .connected, .running, .stopped, .failed:
            false
        }
    }

    var supportsBatteryInformation: Bool {
        switch self {
        case .connected, .reconnecting, .buildingCommand, .launching, .running:
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
    var displayInfo: ScreenTargetDisplayInfo?
    var batteryLevel: Int?
}

struct ScreenTargetDisplayInfo: Equatable {
    let width: Int
    let height: Int
    let densityDPI: Int?
    let physicalWidth: Int?
    let physicalHeight: Int?
    let physicalDensityDPI: Int?

    var isValid: Bool { width > 0 && height > 0 }

    /// The display configuration Android returns to after `wm size reset` and
    /// `wm density reset`. `width`/`height` and `densityDPI` describe the
    /// current effective configuration, which can be an existing override.
    var deviceDefault: ScreenTargetDisplayInfo {
        ScreenTargetDisplayInfo(
            width: physicalWidth ?? width,
            height: physicalHeight ?? height,
            densityDPI: physicalDensityDPI ?? densityDPI,
            physicalWidth: physicalWidth,
            physicalHeight: physicalHeight,
            physicalDensityDPI: physicalDensityDPI
        )
    }
}

struct ScreenResolutionAdjustmentState: Equatable {
    var currentDisplay: ScreenTargetDisplayInfo?
    var isAdjusted = false
    var isBusy = false
    var feedback = ""
    var feedbackIsError = false
}

struct ScreenLayoutInspectorState: Equatable {
    var isEnabled = false
    var isVisible = false
    var isLoading = false
    var isTargetKeyboardVisible = false
    var snapshot: RemoteUiLayoutSnapshot?
    var feedback = ""
    var feedbackIsError = false
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

struct SessionLaunchConfiguration {
    let adbPath: String
    let scrcpyPath: String
}

enum ScreenQualityPreset: CaseIterable, Identifiable, Equatable {
    case smooth720
    case high1080
    case ultra1920
    case original

    var id: Self { self }

    var maxSize: Int {
        switch self {
        case .smooth720: 720
        case .high1080: 1080
        case .ultra1920: 1920
        case .original: 0
        }
    }

    var localizationKey: String {
        switch self {
        case .smooth720: "screensImageQuality720"
        case .high1080: "screensImageQuality1080"
        case .ultra1920: "screensImageQuality1920"
        case .original: "addDeviceOriginalSize"
        }
    }
}

struct RemoteVideoEncoder: Hashable {
    let codec: String
    let name: String
}

struct AppVirtualDisplayKey: Hashable {
    let launchID: UUID
    let deviceID: UUID
    let packageName: String
}

struct AppVirtualDisplayIdentifier: Hashable {
    let deviceID: UUID
    let packageName: String
}

struct ADBConnectedDevice {
    let serial: String
    let state: String
}

struct ResolvedConnectionCandidate {
    let connection: DeviceConnection
    let adbSerial: String

    var transport: DeviceTransport { connection.transport }
}

struct ConnectionRaceOutcome {
    let candidate: ResolvedConnectionCandidate
    let preflight: ScreenDevicePreflight?
    let error: String?

    var succeeded: Bool { preflight != nil }
}

struct SessionCommandResult {
    let exitCode: Int32
    let output: String
    let error: String
    let timedOut: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut }
}

final class ScrcpyOutputCapture {
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
