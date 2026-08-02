import AppKit
import Foundation

enum ScreenSessionConstants {
    static let batteryRefreshIntervalNanoseconds: UInt64 = 60_000_000_000
    static let modelMarker = "__SCREEN_REMOTE_MODEL__"
    static let androidMarker = "__SCREEN_REMOTE_ANDROID__"
    static let serialMarker = "__SCREEN_REMOTE_SERIAL__"
    static let fingerprintMarker = "__SCREEN_REMOTE_FINGERPRINT__"
    static let displayMarker = "__SCREEN_REMOTE_DISPLAY__"
    static let batteryMarker = "__SCREEN_REMOTE_BATTERY__"

    static let preflightCommand =
        "echo '\(modelMarker)'; getprop ro.product.model; " +
        "echo '\(androidMarker)'; getprop ro.build.version.release; " +
        "echo '\(serialMarker)'; getprop ro.serialno; " +
        "echo '\(fingerprintMarker)'; getprop ro.build.fingerprint; " +
        "echo '\(displayMarker)'; wm size; wm density; " +
        "echo '\(batteryMarker)'; dumpsys battery 2>/dev/null || true"
}

enum ScreenSessionError: LocalizedError {
    case adbNotFound
    case scrcpyNotFound
    case noConnectionCandidates
    case usbUnavailable
    case connectionRaceFailed(String)
    case commandFailed(String)
    case invalidPreflight
    case scrcpyLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .adbNotFound: String.localizedKey("screenSessionErrorADBNotFound")
        case .scrcpyNotFound: String.localizedKey("screenSessionErrorScrcpyNotFound")
        case .noConnectionCandidates: String.localizedKey("screenSessionErrorNoCandidates")
        case .usbUnavailable: String.localizedKey("screenSessionErrorUSBUnavailable")
        case .connectionRaceFailed(let detail):
            String(format: String.localizedKey("screenSessionErrorRaceFailed %@"), detail)
        case .commandFailed(let detail):
            String(format: String.localizedKey("screenSessionErrorADBCommand %@"), detail)
        case .invalidPreflight:
            String.localizedKey("screenSessionErrorInvalidPreflight")
        case .scrcpyLaunchFailed(let detail):
            String(format: String.localizedKey("screenSessionErrorScrcpyLaunch %@"), detail)
        }
    }
}

extension SessionCommandResult {
    var failureDetail: String {
        if timedOut { return "timed out" }
        let detail = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { return detail }
        let standardOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return standardOutput.isEmpty ? "exit status \(exitCode)" : standardOutput
    }
}

extension String {
    var screenSessionFirstNonemptyLine: String {
        components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

}
