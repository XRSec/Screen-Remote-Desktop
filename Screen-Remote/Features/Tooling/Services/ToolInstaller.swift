import SwiftUI
import Foundation
import CFNetwork

final class ToolInstaller: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double?
    @Published var statusText = String.localizedKey("toolDownloadStatusPreparing")
    @Published var errorMessage: String?
    @Published var installedPath: String?
    @Published var isWorking = false
    @Published var isDownloading = false
    @Published var downloadedBytes: Int64 = 0
    @Published var expectedBytes: Int64?

    var isComplete: Bool { installedPath != nil }
    var progressText: String {
        let downloaded = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        guard let progress else {
            return downloadedBytes > 0
                ? String(format: String.localizedKey("toolDownloadDownloadedBytes"), downloaded)
                : String.localizedKey("toolDownloadConnecting")
        }
        guard let expectedBytes, expectedBytes > 0 else { return "\(Int(progress * 100))%" }
        let total = ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file)
        return "\(Int(progress * 100))% · \(downloaded) / \(total)"
    }

    let kind: ToolDownloadKind
    var task: URLSessionDownloadTask?
    var session: URLSession?
    var sourceURL: URL?
    var activeDownloadURL: URL?
    var retriedOfficialSource = false
    var process: Process?
    var parallelTask: Task<Void, Never>?
    var targetSDKRoot = AndroidSDKLocator.defaultSDKRoot
    var targetSkinsRoot = AndroidSDKLocator.defaultSDKRoot
        .appendingPathComponent("skins", isDirectory: true)
    var proxyAddress = "127.0.0.1:7897"
    var proxyType = "http"
    var sdkManagerOutputBuffer = ""

    init(kind: ToolDownloadKind) {
        self.kind = kind
        super.init()
    }

    func start(
        accelerator: String, proxy: String, proxyType: String,
        sdkRoot: String, toolsPath: String, androidCLIPath: String, skinsPath: String
    ) {
        guard !isWorking else { return }
        isWorking = true
        isDownloading = false
        installedPath = nil
        errorMessage = nil
        progress = nil
        downloadedBytes = 0
        expectedBytes = nil
        retriedOfficialSource = false
        statusText = String.localizedKey("toolDownloadStatusCheckingLatest")
        targetSDKRoot = URL(fileURLWithPath: sdkRoot.isEmpty
            ? AndroidSDKLocator.defaultSDKRoot.path : sdkRoot)
        targetSkinsRoot = skinsPath.isEmpty
            ? targetSDKRoot.appendingPathComponent("skins", isDirectory: true)
            : URL(fileURLWithPath: skinsPath, isDirectory: true)
        if kind == .androidCLI,
           let existing = AndroidCLILocator.locate(
               preferredRoot: targetSDKRoot.path,
               preferredTools: toolsPath
           ), existing.root.standardizedFileURL == targetSDKRoot.standardizedFileURL {
            installedPath = existing.executable.path
            progress = 1
            isWorking = false
            statusText = String.localizedKey("toolDownloadStatusUsingExistingCLI")
            return
        }
        proxyAddress = proxy
        self.proxyType = proxyType
        if !proxy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           downloadProxy() == nil {
            fail(String.localizedKey("toolDownloadInvalidProxyAddress"))
            return
        }

        if kind == .emulator,
           let cli = AndroidCLILocator.locate(
               preferredExecutable: androidCLIPath,
               preferredRoot: targetSDKRoot.path,
               preferredTools: toolsPath
           ) {
            installWithAndroidCLI(
                cli,
                package: "emulator",
                installedExecutable: "emulator/emulator",
                legacyToolsPath: toolsPath
            )
            return
        }

        if kind == .adb || kind == .emulator {
            installWithSDKManager(
                package: kind == .adb ? "platform-tools" : "emulator",
                installedExecutable: kind == .adb ? "platform-tools/adb" : "emulator/emulator",
                sdkRoot: sdkRoot,
                toolsPath: toolsPath
            )
            return
        }

        parallelTask = Task {
            do {
                let officialURL = try await latestDownloadURL()
                let downloadURL = try acceleratedURL(officialURL, prefix: accelerator)
                let contentLength = await contentLength(at: downloadURL)
                await MainActor.run {
                    self.sourceURL = officialURL
                    self.expectedBytes = contentLength
                }
                if kind == .androidCLI, let contentLength, contentLength > 5_000_000 {
                    do {
                        let archive = try await parallelDownload(
                            downloadURL, expectedSize: contentLength, connections: 16
                        )
                        await MainActor.run { self.installDownloadedArchive(archive) }
                    } catch ParallelDownloadError.rangeUnsupported {
                        await MainActor.run { self.beginDownload(downloadURL) }
                    }
                } else {
                    await MainActor.run { self.beginDownload(downloadURL) }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { self.fail(error.localizedDescription) }
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        parallelTask?.cancel()
        process?.terminate()
        session?.invalidateAndCancel()
        isWorking = false
        isDownloading = false
        statusText = String.localizedKey("toolDownloadCancelled")
    }
}
