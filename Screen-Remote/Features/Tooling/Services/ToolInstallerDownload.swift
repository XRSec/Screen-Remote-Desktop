import SwiftUI
import Foundation
import CFNetwork

extension ToolInstaller {
    func beginDownload(_ url: URL) {
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

    func contentLength(at url: URL) async -> Int64? {
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

    func latestDownloadURL() async throws -> URL {
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

    func latestCommandLineToolsURL() async throws -> URL {
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

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: networkConfiguration())
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    func networkConfiguration() -> URLSessionConfiguration {
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

    func downloadProxy() -> DownloadProxy? {
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

    func parallelDownload(
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

    func acceleratedURL(_ original: URL, prefix: String) throws -> URL {
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
}
