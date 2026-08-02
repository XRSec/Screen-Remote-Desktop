import SwiftUI
import Foundation
import CFNetwork

extension ToolInstaller {
    func installDownloadedArchive(_ archive: URL) {
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

    func install(archive: URL, support: URL) throws -> String {
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

    func replaceItem(at destination: URL, with source: URL) throws {
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

    func findExecutable(named name: String, below directory: URL) -> URL? {
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

    func directoryContainsSkin(_ directory: URL) -> Bool {
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

    func makeExecutable(_ url: URL) throws {
        var attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        attributes[.posixPermissions] = NSNumber(value: permissions | 0o111)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }

    func registerCommandLineTools(at directory: URL) throws {
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

    func run(_ executable: String, _ arguments: [String]) throws {
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

    func fail(_ message: String) {
        isWorking = false
        isDownloading = false
        statusText = String.localizedKey("toolDownloadNotCompleted")
        errorMessage = message
        session?.invalidateAndCancel()
    }
}
