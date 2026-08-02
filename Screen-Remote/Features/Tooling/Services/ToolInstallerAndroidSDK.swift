import SwiftUI
import Foundation
import CFNetwork

extension ToolInstaller {
    func installWithAndroidCLI(
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

    func publishAndroidCLIProgress(from text: String) {
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

    func androidCLITemporaryDownloadSize(sdkRoot: URL, since startDate: Date) -> Int64 {
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

    func installWithSDKManager(
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

    func publishSDKManagerProgress(from text: String) {
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

    func sdkManagerTemporaryDownloadSize(sdkRoot: URL) -> Int64 {
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

    func sdkPackageArchiveSize(package: String) async throws -> Int64? {
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
