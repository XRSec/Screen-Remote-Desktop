import AppKit
import SwiftUI

private let managementCardColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let managementCardGridMaxWidth: CGFloat = 914

extension Notification.Name {
    static let screenRemoteRefreshManagement = Notification.Name("screenRemoteRefreshManagement")
}

struct ManagementTarget {
    let device: Device
    let serial: String
    let adbPath: String
}

@MainActor
func managementTarget(from appState: AppState) -> ManagementTarget? {
    guard appState.devices.indices.contains(appState.selectedDevice) else { return nil }
    let device = appState.devices[appState.selectedDevice]
    let session = appState.screenSessions.session(for: device.id)
    guard session.isConnected, !session.adbSerial.isEmpty else { return nil }
    return ManagementTarget(device: device, serial: session.adbSerial, adbPath: appState.adbPath)
}

struct ManagementCommandOutput {
    let status: Int32
    let data: Data
    let error: String
    let timedOut: Bool

    var text: String { String(decoding: data, as: UTF8.self) }
    var succeeded: Bool { status == 0 && !timedOut }
    var failureDetail: String {
        if timedOut { return String.localizedKey("managementCommandTimedOut") }
        let stderr = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : stderr
    }
}

enum ManagementADB {
    static func run(
        target: ManagementTarget,
        arguments: [String],
        timeout: TimeInterval = 20
    ) async throws -> ManagementCommandOutput {
        guard FileManager.default.isExecutableFile(atPath: target.adbPath) else {
            throw ManagementError.message(String.localizedKey("managementADBMissing"))
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: target.adbPath)
                process.arguments = ["-s", target.serial] + arguments
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                let lock = NSLock()
                var didTimeOut = false
                do {
                    try process.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard process.isRunning else { return }
                        didTimeOut = true
                        process.terminate()
                    }
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let error = String(decoding: errorData, as: UTF8.self)
                    lock.lock()
                    let timedOut = didTimeOut
                    lock.unlock()
                    continuation.resume(returning: ManagementCommandOutput(
                        status: process.terminationStatus,
                        data: data,
                        error: error,
                        timedOut: timedOut
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func shell(
        target: ManagementTarget,
        command: String,
        timeout: TimeInterval = 20
    ) async throws -> String {
        let output = try await run(target: target, arguments: ["shell", command], timeout: timeout)
        guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
        return output.text
    }

    static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

enum ManagementError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

struct ManagementUnavailableView: View {
    @EnvironmentObject private var appState: AppState

    private var hasSelectedDevice: Bool {
        appState.devices.indices.contains(appState.selectedDevice)
    }

    var body: some View {
        ContentUnavailableViewCompat(
            icon: "cable.connector",
            title: hasSelectedDevice ? "managementSessionRequiredTitle" : "managementNoDeviceTitle",
            detail: hasSelectedDevice ? "managementSessionRequiredDetail" : "managementNoDeviceDetail",
            actionTitle: hasSelectedDevice ? "sessionStartAction" : "addDeviceTitle",
            action: {
                if hasSelectedDevice {
                    let device = appState.devices[appState.selectedDevice]
                    appState.connectScreenSession(deviceID: device.id)
                } else {
                    appState.showingAddDevice = true
                }
            }
        )
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct ManagementErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(AppTypography.subheadline)
            .foregroundColor(.red)
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appBackground(
                Color.red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            )
            .appOverlay(
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(Color.red.opacity(0.16), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(message))
    }
}

// MARK: - Files
