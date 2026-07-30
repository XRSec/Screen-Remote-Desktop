import SwiftUI
import Foundation
import CFNetwork

enum ToolDownloadKind: String, Identifiable {
    case adb
    case scrcpy
    case androidCLI
    case emulator
    case skins

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .adb: "ADB"
        case .scrcpy: "scrcpy"
        case .androidCLI: "Android CLI"
        case .emulator: "Android Emulator"
        case .skins: String.localizedKey("toolDownloadSkinsName")
        }
    }

    var installLocation: String {
        switch self {
        case .adb: "SDK/platform-tools/"
        case .scrcpy: "SDK/scrcpy/"
        case .androidCLI: "SDK/cmdline-tools/latest/"
        case .emulator: "SDK/emulator/"
        case .skins: "SDK/skins/"
        }
    }
}

enum ToolLocator {
    static func find(_ kind: ToolDownloadKind) -> String? {
        let name = kind.rawValue
        var candidates: [String] = []

        if let commandPath = commandPath(for: name) {
            candidates.append(commandPath)
        }

        let home = NSHomeDirectory()
        let support = "\(home)/Library/Application Support/Screen Remote/Tools"
        switch kind {
        case .adb:
            candidates += [
                "\(home)/Library/Android/sdk/platform-tools/adb",
                "/opt/homebrew/bin/adb",
                "/usr/local/bin/adb",
                "\(support)/platform-tools/adb",
                "\(home)/Library/Application Support/adb"
            ]
        case .scrcpy:
            candidates += [
                "\(home)/Library/Android/sdk/scrcpy/scrcpy",
                "/opt/homebrew/bin/scrcpy",
                "/usr/local/bin/scrcpy",
                "\(support)/scrcpy/scrcpy",
                "\(home)/Library/Application Support/scrcpy"
            ]
        case .androidCLI, .emulator, .skins:
            break
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func commandPath(for name: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; whence -p \(name)"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first
        } catch {
            return nil
        }
    }
}

struct ToolDownloadView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    @StateObject private var installer: ToolInstaller
    let kind: ToolDownloadKind
    let installed: (String) -> Void

    init(kind: ToolDownloadKind, installed: @escaping (String) -> Void) {
        self.kind = kind
        self.installed = installed
        _installer = StateObject(wrappedValue: ToolInstaller(kind: kind))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: String.localizedKey("toolDownloadTitle"), kind.displayName)).font(.title2.bold())
                    Text("toolDownloadSubtitle").foregroundColor(.secondary)
                }
                Spacer()
                Button("toolDownloadClose") { presentationMode.wrappedValue.dismiss() }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("toolDownloadUseProxy", isOn: $appState.useDownloadProxy)
                    .font(.headline)
                    .disabled(installer.isWorking)
                if appState.useDownloadProxy {
                    HStack(spacing: 8) {
                        Picker("toolDownloadProxyType", selection: $appState.downloadProxyType) {
                            Text(verbatim: "HTTP").tag("http")
                            Text(verbatim: "SOCKS5").tag("socks5")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 126)
                        TextField("toolDownloadProxyDefaultAddress", text: $appState.downloadProxy)
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(installer.isWorking)
                    Text("toolDownloadProxyHelp")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("toolDownloadDirectConnect")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if kind == .scrcpy {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("toolDownloadUseAccelerator", isOn: $appState.useDownloadAccelerator)
                        .font(.headline)
                        .disabled(installer.isWorking)
                    if appState.useDownloadAccelerator {
                        TextField("toolDownloadAcceleratorPlaceholder", text: $appState.downloadAccelerator)
                            .textFieldStyle(.roundedBorder)
                            .disabled(installer.isWorking)
                        Text("toolDownloadAcceleratorHelp")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("toolDownloadScrcpyOfficialSource")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if kind == .skins {
                Text("toolDownloadSkinsSource")
                    .font(.caption).foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(installer.statusText)
                    Spacer()
                    if installer.isDownloading { Text(installer.progressText).appMonospacedDigit() }
                }
                .font(.subheadline)

                ProgressView(value: installer.progress)
                    .progressViewStyle(.linear)

                Text(String(
                    format: String.localizedKey("toolDownloadInstallLocation"),
                    kind == .skins ? resolvedSkinsPath : kind.installLocation
                ))
                    .font(.caption).foregroundColor(.secondary)
            }

            if let error = installer.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                if installer.isWorking {
                    Button("commonCancel") { installer.cancel() }
                }
                Spacer()
                Button(installer.isComplete ? "toolDownloadDone" : "toolDownloadDownloadAndInstall") {
                    if installer.isComplete {
                        if let path = installer.installedPath { installed(path) }
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        installer.start(
                            accelerator: kind == .scrcpy && appState.useDownloadAccelerator
                                ? appState.downloadAccelerator : "",
                            proxy: appState.useDownloadProxy ? appState.downloadProxy : "",
                            proxyType: appState.downloadProxyType,
                            sdkRoot: appState.androidSDKRoot,
                            toolsPath: appState.commandLineToolsPath,
                            androidCLIPath: appState.androidCLIPath,
                            skinsPath: appState.skinsPath
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(installer.isWorking)
            }
        }
        .padding(22)
        .appPresentationWidth(relativeTo: appState.appWindowWidth)
        .appPresentationHeight(relativeTo: appState.appWindowHeight)
        .background(AppTheme.background)
    }

    private var resolvedSkinsPath: String {
        appState.skinsPath.isEmpty
            ? URL(fileURLWithPath: appState.androidSDKRoot.isEmpty
                ? AndroidSDKLocator.defaultSDKRoot.path : appState.androidSDKRoot)
                .appendingPathComponent("skins", isDirectory: true).path
            : appState.skinsPath
    }
}

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

    private let kind: ToolDownloadKind
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var sourceURL: URL?
    private var activeDownloadURL: URL?
    private var retriedOfficialSource = false
    private var process: Process?
    private var parallelTask: Task<Void, Never>?
    private var targetSDKRoot = AndroidSDKLocator.defaultSDKRoot
    private var targetSkinsRoot = AndroidSDKLocator.defaultSDKRoot
        .appendingPathComponent("skins", isDirectory: true)
    private var proxyAddress = "127.0.0.1:7897"
    private var proxyType = "http"
    private var sdkManagerOutputBuffer = ""

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

    private func beginDownload(_ url: URL) {
        activeDownloadURL = url
        statusText = String(format: String.localizedKey("toolDownloadDownloading"), kind.displayName)
        isDownloading = true
        let configuration = networkConfiguration()
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.setValue("ScreenRemote/0.1", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        self.task = task
        task.resume()
    }

    private func contentLength(at url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue("ScreenRemote/0.1", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await fetch(request)
            let length = response.expectedContentLength
            return length > 0 ? length : nil
        } catch {
            return nil
        }
    }

    private func latestDownloadURL() async throws -> URL {
        if kind == .androidCLI {
            return try await latestCommandLineToolsURL()
        }
        if kind == .skins {
            return URL(
                string: "https://android.googlesource.com/platform/tools/adt/idea/+archive/HEAD/artwork/resources/device-art-resources.tar.gz"
            )!
        }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Genymobile/scrcpy/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ScreenRemote/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorFetchScrcpyLatestFailed"))
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
#if arch(arm64)
        let architecture = "aarch64"
#else
        let architecture = "x86_64"
#endif
        guard let asset = release.assets.first(where: {
            let name = $0.name.lowercased()
            return name.contains("macos") && name.contains(architecture) && name.hasSuffix(".tar.gz")
        }), let url = URL(string: asset.browserDownloadURL) else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorNoCompatibleScrcpyArchive"))
        }
        return url
    }

    private func latestCommandLineToolsURL() async throws -> URL {
        let repositoryURL = URL(string: "https://dl.google.com/android/repository/repository2-3.xml")!
        let (data, response) = try await fetch(URLRequest(url: repositoryURL))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let xml = String(data: data, encoding: .utf8) else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorReadSdkRepository"))
        }
        guard let packageRange = xml.range(
            of: #"<remotePackage path="cmdline-tools;latest">[\s\S]*?</remotePackage>"#,
            options: .regularExpression
        ) else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorNoCommandLineToolsLatest"))
        }
        let package = String(xml[packageRange])
#if arch(arm64)
        let architecture = "aarch64"
#else
        let architecture = "x64"
#endif
        let archiveRegex = try NSRegularExpression(pattern: #"<archive>[\s\S]*?</archive>"#)
        let archive = archiveRegex.matches(
            in: package, range: NSRange(package.startIndex..., in: package)
        ).compactMap { match -> String? in
            guard let range = Range(match.range, in: package) else { return nil }
            return String(package[range])
        }.first {
            $0.contains("<host-os>macosx</host-os>")
                && $0.contains("<host-arch>\(architecture)</host-arch>")
        }
        guard let archive else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorNoCompatibleCommandLineToolsArchive"))
        }
        guard let urlRange = archive.range(of: #"<url>[^<]+</url>"#, options: .regularExpression) else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorInvalidCommandLineToolsDownloadURL"))
        }
        let filename = archive[urlRange].dropFirst(5).dropLast(6)
        guard let url = URL(string: "https://dl.google.com/android/repository/\(filename)") else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorInvalidCommandLineToolsDownloadURL"))
        }
        return url
    }

    private func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: networkConfiguration())
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    private func networkConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        guard let proxy = downloadProxy() else { return configuration }
        switch proxy.kind {
        case .http:
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: proxy.port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: proxy.host,
                kCFNetworkProxiesHTTPSPort as String: proxy.port,
            ]
        case .socks:
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: proxy.host,
                kCFNetworkProxiesSOCKSPort as String: proxy.port,
            ]
        }
        return configuration
    }

    private func downloadProxy() -> DownloadProxy? {
        let trimmed = proxyAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let address = trimmed.components(separatedBy: "://").last ?? trimmed
        let selectedScheme = proxyType == "socks5" ? "socks5" : "http"
        let value = "\(selectedScheme)://\(address)"
        guard let components = URLComponents(string: value),
              let host = components.host,
              let port = components.port else {
            return nil
        }
        let scheme = components.scheme?.lowercased()
        let kind: ProxyKind
        switch scheme {
        case "http": kind = .http
        case "socks", "socks5": kind = .socks
        default: return nil
        }
        return DownloadProxy(kind: kind, host: host, port: port)
    }

    private func parallelDownload(
        _ url: URL, expectedSize: Int64, connections: Int
    ) async throws -> URL {
        let fileManager = FileManager.default
        let support = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Screen Remote", isDirectory: true)
        let workDirectory = support.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        let downloads = support.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        await MainActor.run {
            self.isDownloading = true
            self.statusText = String(
                format: String.localizedKey("toolDownloadParallelDownloading"),
                connections,
                self.kind.displayName
            )
            self.progress = 0
            self.downloadedBytes = 0
        }

        let configuration = networkConfiguration()
        configuration.timeoutIntervalForRequest = 60
        let chunkSize = (expectedSize + Int64(connections) - 1) / Int64(connections)
        var parts = Array<URL?>(repeating: nil, count: connections)
        var completedBytes: Int64 = 0

        try await withThrowingTaskGroup(of: (Int, URL, Int64).self) { group in
            for index in 0..<connections {
                let start = Int64(index) * chunkSize
                let end = min(start + chunkSize - 1, expectedSize - 1)
                guard start <= end else { continue }
                group.addTask {
                    try Task.checkCancellation()
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 60
                    request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                    request.setValue("ScreenRemote/0.1", forHTTPHeaderField: "User-Agent")
                    let partSession = URLSession(configuration: configuration)
                    defer { partSession.finishTasksAndInvalidate() }
                    let (temporaryURL, response) = try await partSession.appDownload(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
                        throw ParallelDownloadError.rangeUnsupported
                    }
                    let partURL = workDirectory.appendingPathComponent("part-\(index)")
                    try? fileManager.removeItem(at: partURL)
                    try fileManager.moveItem(at: temporaryURL, to: partURL)
                    let attributes = try fileManager.attributesOfItem(atPath: partURL.path)
                    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                    guard size == end - start + 1 else {
                        throw ParallelDownloadError.invalidPart
                    }
                    return (index, partURL, size)
                }
            }

            for try await (index, partURL, size) in group {
                parts[index] = partURL
                completedBytes += size
                let downloaded = completedBytes
                await MainActor.run {
                    self.downloadedBytes = downloaded
                    self.progress = min(Double(downloaded) / Double(expectedSize), 1)
                }
            }
        }

        try Task.checkCancellation()
        let filename = sourceURL?.lastPathComponent ?? url.lastPathComponent
        let archive = downloads.appendingPathComponent(filename)
        try? fileManager.removeItem(at: archive)
        guard fileManager.createFile(atPath: archive.path, contents: nil) else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorCannotCreateArchive"))
        }
        let output = try FileHandle(forWritingTo: archive)
        defer { try? output.close() }
        for index in 0..<connections {
            guard let partURL = parts[index] else {
                throw ParallelDownloadError.invalidPart
            }
            try output.write(contentsOf: Data(contentsOf: partURL))
        }
        let attributes = try fileManager.attributesOfItem(atPath: archive.path)
        let finalSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard finalSize == expectedSize else { throw ParallelDownloadError.invalidPart }
        return archive
    }

    private func acceleratedURL(_ original: URL, prefix: String) throws -> URL {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return original }
        let value = trimmed.contains("{url}")
            ? trimmed.replacingOccurrences(of: "{url}", with: original.absoluteString)
            : trimmed + original.absoluteString
        guard let url = URL(string: value) else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorInvalidAccelerator"))
        }
        return url
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            self.downloadedBytes = totalBytesWritten
            let total = totalBytesExpectedToWrite > 0
                ? totalBytesExpectedToWrite
                : (downloadTask.response?.expectedContentLength ?? self.expectedBytes ?? -1)
            if total > 0 {
                self.expectedBytes = total
                self.progress = min(Double(totalBytesWritten) / Double(total), 1)
            } else {
                self.progress = nil
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        let support = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Screen Remote", isDirectory: true)
        let downloads = support.appendingPathComponent("Downloads", isDirectory: true)
        let filename = sourceURL?.lastPathComponent ?? "\(kind.rawValue)-download"
        let archive = downloads.appendingPathComponent(filename)

        do {
            try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: archive)
            try fileManager.copyItem(at: location, to: archive)
        } catch {
            DispatchQueue.main.async {
                self.fail(String(format: String.localizedKey("toolDownloadSaveFileFailed"), error.localizedDescription))
            }
            return
        }

        DispatchQueue.main.async { self.installDownloadedArchive(archive) }
    }

    private func installDownloadedArchive(_ archive: URL) {
        isDownloading = false
        statusText = String.localizedKey("toolDownloadInstalling")
        progress = 1
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Screen Remote", isDirectory: true)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let path = try self.install(archive: archive, support: support)
                DispatchQueue.main.async {
                    self.installedPath = path
                    self.isWorking = false
                    self.statusText = String.localizedKey("toolDownloadStatusCompleted")
                    self.session?.finishTasksAndInvalidate()
                }
            } catch {
                DispatchQueue.main.async { self.fail(error.localizedDescription) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async {
            if let officialURL = self.sourceURL,
               self.activeDownloadURL != officialURL,
               !self.retriedOfficialSource {
                self.retriedOfficialSource = true
                self.session?.invalidateAndCancel()
                self.progress = nil
                self.downloadedBytes = 0
                self.expectedBytes = nil
                self.statusText = String.localizedKey("toolDownloadSwitchToOfficialSource")
                self.beginDownload(officialURL)
            } else {
                self.fail(String(format: String.localizedKey("toolDownloadErrorDownloadFailed"), error.localizedDescription))
            }
        }
    }

    private func install(archive: URL, support: URL) throws -> String {
        let fileManager = FileManager.default
        let staging = support.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        if kind == .androidCLI {
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
            let source = staging.appendingPathComponent("cmdline-tools", isDirectory: true)
            let destination = targetSDKRoot.appendingPathComponent("cmdline-tools/latest", isDirectory: true)
            guard fileManager.fileExists(atPath: source.appendingPathComponent("bin/android").path) else {
                throw InstallerError.message(String.localizedKey("toolDownloadErrorMissingAndroidCLI"))
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try replaceItem(at: destination, with: source)
            try makeExecutable(destination.appendingPathComponent("bin/sdkmanager"))
            try makeExecutable(destination.appendingPathComponent("bin/avdmanager"))
            try makeExecutable(destination.appendingPathComponent("bin/android"))
            try registerCommandLineTools(at: destination)
            return destination.appendingPathComponent("bin/android").path
        }

        if kind == .skins {
            try run("/usr/bin/tar", ["-xzf", archive.path, "-C", staging.path])
            var sourceRoot = staging
            let initialEntries = try fileManager.contentsOfDirectory(
                at: staging,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            if initialEntries.count == 1,
               initialEntries[0].lastPathComponent == "device-art-resources" {
                sourceRoot = initialEntries[0]
            }
            let entries = try fileManager.contentsOfDirectory(
                at: sourceRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let skinDirectories = entries.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && directoryContainsSkin($0)
            }
            guard !skinDirectories.isEmpty else {
                throw InstallerError.message(String.localizedKey("toolDownloadErrorMissingSkins"))
            }
            try fileManager.createDirectory(at: targetSkinsRoot, withIntermediateDirectories: true)
            for source in skinDirectories {
                try replaceItem(
                    at: targetSkinsRoot.appendingPathComponent(source.lastPathComponent, isDirectory: true),
                    with: source
                )
            }
            let notice = """
            Android Emulator device art resources
            Copyright (C) The Android Open Source Project

            Source: https://android.googlesource.com/platform/tools/adt/idea/+/HEAD/artwork/resources/device-art-resources/
            Licensed under the Apache License, Version 2.0:
            https://www.apache.org/licenses/LICENSE-2.0
            """
            try notice.write(
                to: targetSkinsRoot.appendingPathComponent("ANDROID_STUDIO_SKINS_NOTICE.txt"),
                atomically: true,
                encoding: .utf8
            )
            return targetSkinsRoot.path
        }

        try run("/usr/bin/tar", ["-xzf", archive.path, "-C", staging.path])
        guard let executable = findExecutable(named: "scrcpy", below: staging) else {
            throw InstallerError.message(String.localizedKey("toolDownloadErrorMissingScrcpyExecutable"))
        }
        let source = executable.deletingLastPathComponent()
        let destination = targetSDKRoot.appendingPathComponent("scrcpy", isDirectory: true)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try replaceItem(at: destination, with: source)
        let installedExecutable = destination.appendingPathComponent("scrcpy")
        try makeExecutable(installedExecutable)
        return installedExecutable.path
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.moveItem(at: source, to: destination)
            return
        }

        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent)-backup-\(UUID().uuidString)")
        try fileManager.moveItem(at: destination, to: backup)
        do {
            try fileManager.moveItem(at: source, to: destination)
            try? fileManager.removeItem(at: backup)
        } catch {
            try? fileManager.moveItem(at: backup, to: destination)
            throw error
        }
    }

    private func findExecutable(named name: String, below directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return url
        }
        return nil
    }

    private func directoryContainsSkin(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appendingPathComponent("layout").path) {
            return true
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }
        for case let file as URL in enumerator where file.lastPathComponent == "layout" {
            return true
        }
        return false
    }

    private func makeExecutable(_ url: URL) throws {
        var attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        attributes[.posixPermissions] = NSNumber(value: permissions | 0o111)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private func registerCommandLineTools(at directory: URL) throws {
        let propertiesURL = directory.appendingPathComponent("source.properties")
        let properties = try String(contentsOf: propertiesURL, encoding: .utf8)
        let revision = properties.split(separator: "\n").first { $0.hasPrefix("Pkg.Revision=") }
            .map { String($0.dropFirst("Pkg.Revision=".count)) } ?? "0.0.0"
        let numbers = revision.split(separator: ".").map { Int($0) ?? 0 }
        let major = numbers.indices.contains(0) ? numbers[0] : 0
        let minor = numbers.indices.contains(1) ? numbers[1] : 0
        let micro = numbers.indices.contains(2) ? numbers[2] : 0
        let packageXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <ns2:repository xmlns:ns2="http://schemas.android.com/repository/android/common/02"
            xmlns:ns3="http://schemas.android.com/repository/android/generic/02"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <localPackage path="cmdline-tools;latest" obsolete="false">
                <type-details xsi:type="ns3:genericDetailsType"/>
                <revision>
                    <major>\(major)</major>
                    <minor>\(minor)</minor>
                    <micro>\(micro)</micro>
                </revision>
                <display-name>Android SDK Command-line Tools (latest)</display-name>
            </localPackage>
        </ns2:repository>
        """
        try packageXML.write(
            to: directory.appendingPathComponent("package.xml"), atomically: true, encoding: .utf8
        )
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallerError.message(detail?.isEmpty == false ? detail! : String.localizedKey("toolDownloadErrorArchiveExtractionFailed"))
        }
    }

    private func fail(_ message: String) {
        isWorking = false
        isDownloading = false
        statusText = String.localizedKey("toolDownloadNotCompleted")
        errorMessage = message
        session?.invalidateAndCancel()
    }

    private func installWithAndroidCLI(
        _ installation: AndroidCLIInstallation,
        package: String,
        installedExecutable: String,
        legacyToolsPath: String
    ) {
        let targetRoot = targetSDKRoot
        let startedAt = Date()
        statusText = String(format: String.localizedKey("toolDownloadInstallingWithAndroidCLI"), package)
        progress = nil
        downloadedBytes = 0
        expectedBytes = nil
        isDownloading = true
        sdkManagerOutputBuffer = ""

        Task {
            let size = try? await self.sdkPackageArchiveSize(package: package)
            await MainActor.run { self.expectedBytes = size }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = installation.executable
            process.arguments = ["--sdk=\(targetRoot.path)", "sdk", "install", package]
            process.standardOutput = output
            process.standardError = output
            var environment = ProcessInfo.processInfo.environment
            environment["ANDROID_HOME"] = targetRoot.path
            environment["ANDROID_SDK_ROOT"] = targetRoot.path
            process.environment = environment
            self.process = process

            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self.publishAndroidCLIProgress(from: text)
            }

            do {
                try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
                try process.run()
                var peakDownloadedBytes: Int64 = 0
                while process.isRunning {
                    peakDownloadedBytes = max(
                        peakDownloadedBytes,
                        self.androidCLITemporaryDownloadSize(sdkRoot: targetRoot, since: startedAt)
                    )
                    let downloaded = peakDownloadedBytes
                    DispatchQueue.main.async {
                        self.downloadedBytes = downloaded
                        if let expected = self.expectedBytes, expected > 0, downloaded > 0 {
                            self.progress = min(Double(downloaded) / Double(expected), 0.99)
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.25)
                }
                process.waitUntilExit()
                output.fileHandleForReading.readabilityHandler = nil
                let remaining = output.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                    self.publishAndroidCLIProgress(from: text)
                }
                let installedURL = targetRoot.appendingPathComponent(installedExecutable)
                DispatchQueue.main.async {
                    self.process = nil
                    guard self.isWorking else { return }
                    if process.terminationStatus == 0,
                       FileManager.default.isExecutableFile(atPath: installedURL.path) {
                        self.progress = 1
                        if let expected = self.expectedBytes { self.downloadedBytes = expected }
                        self.installedPath = installedURL.path
                        self.isWorking = false
                        self.isDownloading = false
                        self.statusText = String.localizedKey("toolDownloadStatusCompleted")
                    } else if AndroidSDKLocator.locate(
                        preferredRoot: targetRoot.path,
                        preferredTools: legacyToolsPath
                    ) != nil {
                        self.installWithSDKManager(
                            package: package,
                            installedExecutable: installedExecutable,
                            sdkRoot: targetRoot.path,
                            toolsPath: legacyToolsPath
                        )
                    } else {
                        self.fail(String(
                            format: String.localizedKey("toolDownloadErrorInstallWithAndroidCLIFailed"),
                            package,
                            process.terminationStatus
                        ))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.isWorking else { return }
                    self.fail(String(
                        format: String.localizedKey("toolDownloadErrorStartAndroidCLI"),
                        error.localizedDescription
                    ))
                }
            }
        }
    }

    private func publishAndroidCLIProgress(from text: String) {
        let logText = text.replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !logText.isEmpty { NSLog("[android-cli] %@", logText) }

        sdkManagerOutputBuffer += text
        if sdkManagerOutputBuffer.count > 4096 {
            sdkManagerOutputBuffer = String(sdkManagerOutputBuffer.suffix(2048))
        }
        let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3})\s*%"#)
        let range = NSRange(sdkManagerOutputBuffer.startIndex..., in: sdkManagerOutputBuffer)
        guard let match = regex?.matches(in: sdkManagerOutputBuffer, range: range).last,
              let capture = Range(match.range(at: 1), in: sdkManagerOutputBuffer),
              let value = Double(sdkManagerOutputBuffer[capture]) else { return }
        DispatchQueue.main.async { self.progress = min(value / 100, 0.99) }
    }

    private func androidCLITemporaryDownloadSize(sdkRoot: URL, since startDate: Date) -> Int64 {
        let fileManager = FileManager.default
        let archiveRoot = sdkRoot.appendingPathComponent(".sdk/arch", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: archiveRoot,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "part" {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            ),
            let modified = values.contentModificationDate,
            modified >= startDate.addingTimeInterval(-1) else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func installWithSDKManager(
        package: String, installedExecutable: String, sdkRoot: String, toolsPath: String
    ) {
        guard let installation = AndroidSDKLocator.locate(
            preferredRoot: sdkRoot, preferredTools: toolsPath
        ) else {
            fail(String.localizedKey("toolDownloadErrorSdkManagerMissing"))
            return
        }

        let targetRoot = URL(fileURLWithPath: sdkRoot.isEmpty ? AndroidSDKLocator.defaultSDKRoot.path : sdkRoot)
        statusText = String(format: String.localizedKey("toolDownloadInstallingWithSdkManager"), package)
        progress = nil
        downloadedBytes = 0
        expectedBytes = nil
        isDownloading = true
        sdkManagerOutputBuffer = ""

        Task {
            let size = try? await self.sdkPackageArchiveSize(package: package)
            await MainActor.run { self.expectedBytes = size }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            let input = Pipe()
            process.executableURL = installation.sdkmanager
            var arguments = ["--sdk_root=\(targetRoot.path)"]
            if let proxy = self.downloadProxy() {
                arguments += [
                    "--proxy=\(proxy.kind.sdkManagerValue)",
                    "--proxy_host=\(proxy.host)", "--proxy_port=\(proxy.port)"
                ]
            }
            arguments += ["--install", package]
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            process.standardInput = input
            var environment = ProcessInfo.processInfo.environment
            environment["ANDROID_HOME"] = targetRoot.path
            environment["ANDROID_SDK_ROOT"] = targetRoot.path
            process.environment = environment
            self.process = process

            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                self.publishSDKManagerProgress(from: text)
            }

            do {
                try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
                try process.run()
                DispatchQueue.global().async {
                    for _ in 0..<10 where process.isRunning {
                        try? input.fileHandleForWriting.write(contentsOf: Data("y\n".utf8))
                        Thread.sleep(forTimeInterval: 0.5)
                    }
                }
                while process.isRunning {
                    let size = self.sdkManagerTemporaryDownloadSize(sdkRoot: targetRoot)
                    DispatchQueue.main.async {
                        self.downloadedBytes = size
                        if let expected = self.expectedBytes, expected > 0 {
                            self.progress = min(Double(size) / Double(expected), 0.99)
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.25)
                }
                process.waitUntilExit()
                output.fileHandleForReading.readabilityHandler = nil
                let remaining = output.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: remaining, encoding: .utf8) {
                    self.publishSDKManagerProgress(from: text)
                }
                let installedURL = targetRoot.appendingPathComponent(installedExecutable)
                DispatchQueue.main.async {
                    self.process = nil
                    guard self.isWorking else { return }
                    if process.terminationStatus == 0,
                       FileManager.default.isExecutableFile(atPath: installedURL.path) {
                        self.progress = 1
                        self.installedPath = installedURL.path
                        self.isWorking = false
                        self.isDownloading = false
                        self.statusText = String.localizedKey("toolDownloadStatusCompleted")
                    } else {
                        self.fail(String(format: String.localizedKey("toolDownloadErrorInstallWithSdkManagerFailed"), package, process.terminationStatus))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.isWorking else { return }
                    self.fail(String(format: String.localizedKey("toolDownloadErrorStartSdkManager"), error.localizedDescription))
                }
            }
        }
    }

    private func publishSDKManagerProgress(from text: String) {
        let logText = text.replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !logText.isEmpty { NSLog("[sdkmanager] %@", logText) }

        sdkManagerOutputBuffer += text
        if sdkManagerOutputBuffer.count > 4096 {
            sdkManagerOutputBuffer = String(sdkManagerOutputBuffer.suffix(2048))
        }
        let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3})\s*%"#)
        let range = NSRange(sdkManagerOutputBuffer.startIndex..., in: sdkManagerOutputBuffer)
        guard let match = regex?.matches(in: sdkManagerOutputBuffer, range: range).last,
              let capture = Range(match.range(at: 1), in: sdkManagerOutputBuffer),
              let value = Double(sdkManagerOutputBuffer[capture]) else { return }
        DispatchQueue.main.async { self.progress = min(value / 100, 1) }
    }

    private func sdkManagerTemporaryDownloadSize(sdkRoot: URL) -> Int64 {
        let fileManager = FileManager.default
        let roots = [
            sdkRoot.appendingPathComponent(".temp", isDirectory: true),
            sdkRoot.appendingPathComponent(".downloadIntermediates", isDirectory: true),
        ]
        var total: Int64 = 0
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    private func sdkPackageArchiveSize(package: String) async throws -> Int64? {
        let repositoryURL = URL(string: "https://dl.google.com/android/repository/repository2-3.xml")!
        let (data, response) = try await fetch(URLRequest(url: repositoryURL))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let xml = String(data: data, encoding: .utf8) else { return nil }
        let escapedPackage = NSRegularExpression.escapedPattern(for: package)
        guard let packageRange = xml.range(
            of: "<remotePackage path=\"\(escapedPackage)\">[\\s\\S]*?</remotePackage>",
            options: .regularExpression
        ) else { return nil }
        let packageXML = String(xml[packageRange])
        let archiveRegex = try NSRegularExpression(pattern: #"<archive>[\s\S]*?</archive>"#)
#if arch(arm64)
        let architecture = "aarch64"
#else
        let architecture = "x64"
#endif
        let archives = archiveRegex.matches(
            in: packageXML, range: NSRange(packageXML.startIndex..., in: packageXML)
        ).compactMap { match -> String? in
            guard let range = Range(match.range, in: packageXML) else { return nil }
            return String(packageXML[range])
        }
        guard let archive = archives.first(where: { value in
            guard value.contains("<host-os>macosx</host-os>") else { return false }
            if value.contains("<host-arch>") {
                return value.contains("<host-arch>\(architecture)</host-arch>")
            }
            return true
        }),
        let sizeRange = archive.range(of: #"<size>\d+</size>"#, options: .regularExpression),
        let size = Int64(archive[sizeRange].dropFirst(6).dropLast(7)) else { return nil }
        return size
    }
}

private enum ProxyKind {
    case http
    case socks

    var sdkManagerValue: String {
        switch self {
        case .http: "http"
        case .socks: "socks"
        }
    }
}

private struct DownloadProxy {
    let kind: ProxyKind
    let host: String
    let port: Int
}

private enum ParallelDownloadError: LocalizedError {
    case rangeUnsupported
    case invalidPart

    var errorDescription: String? {
        switch self {
        case .rangeUnsupported: String.localizedKey("toolDownloadParallelDownloadRangeUnsupported")
        case .invalidPart: String.localizedKey("toolDownloadParallelDownloadInvalidPart")
        }
    }
}

private struct GitHubRelease: Decodable {
    let assets: [GitHubAsset]
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private enum InstallerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(message) = self { return message }
        return nil
    }
}
