import AppKit
import Foundation

struct RemoteAppIcon {
    let packageName: String
    let name: String
    let versionCode: Int64
    let lastUpdateTime: Int64
    let imageData: Data
}

struct DeviceAppCacheEntry: Codable {
    let apps: [ManagedAndroidApp]
    let updatedAt: Date
}

struct DeviceAppCacheFile: Codable {
    var version = 2
    var devices: [String: DeviceAppCacheEntry] = [:]
}

@MainActor
enum DeviceAppCacheStore {
    private static let url = AppPersistence.directory.appendingPathComponent("app-cache.json")
    private static var cache: DeviceAppCacheFile = load()

    static func entry(for deviceID: UUID) -> DeviceAppCacheEntry? {
        cache.devices[deviceID.uuidString]
    }

    static func save(apps: [ManagedAndroidApp], for deviceID: UUID) {
        cache.devices[deviceID.uuidString] = DeviceAppCacheEntry(
            apps: apps,
            updatedAt: Date()
        )
        persist()
    }

    static func reusingCachedIcons(
        in remoteApps: [ManagedAndroidApp],
        cachedApps: [ManagedAndroidApp],
        deviceID: UUID
    ) -> [ManagedAndroidApp] {
        let cachedByPackage = Dictionary(uniqueKeysWithValues: cachedApps.map { ($0.packageName, $0) })
        return remoteApps.map { remoteApp in
            guard let cachedApp = cachedByPackage[remoteApp.packageName],
                  let iconFileName = cachedApp.iconFileName,
                  FileManager.default.isReadableFile(
                    atPath: iconDirectory(for: deviceID).appendingPathComponent(iconFileName).path
                  ),
                  (remoteApp.versionCode == 0 || remoteApp.versionCode == cachedApp.versionCode),
                  (remoteApp.lastUpdateTime == 0 || remoteApp.lastUpdateTime == cachedApp.lastUpdateTime) else {
                return remoteApp
            }
            return ManagedAndroidApp(
                packageName: remoteApp.packageName,
                name: remoteApp.name,
                isEnabled: remoteApp.isEnabled,
                isSystem: remoteApp.isSystem,
                versionCode: remoteApp.versionCode == 0 ? cachedApp.versionCode : remoteApp.versionCode,
                lastUpdateTime: remoteApp.lastUpdateTime == 0 ? cachedApp.lastUpdateTime : remoteApp.lastUpdateTime,
                iconFileName: iconFileName
            )
        }
    }

    static func loadIcons(for apps: [ManagedAndroidApp], deviceID: UUID) -> [String: NSImage] {
        let directory = iconDirectory(for: deviceID)
        return Dictionary(uniqueKeysWithValues: apps.compactMap { app in
            guard let fileName = app.iconFileName,
                  let image = NSImage(contentsOf: directory.appendingPathComponent(fileName)) else {
                return nil
            }
            return (app.packageName, image)
        })
    }

    static func saveIcon(
        _ data: Data,
        packageName: String,
        versionCode: Int64,
        lastUpdateTime: Int64,
        deviceID: UUID
    ) -> String? {
        let fileName = "\(stableFingerprint("\(packageName)\n\(versionCode)\n\(lastUpdateTime)")).webp"
        let directory = iconDirectory(for: deviceID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            NSLog("Screen Remote: failed to save app icon: %@", error.localizedDescription)
            return nil
        }
    }

    static func pruneIcons(for apps: [ManagedAndroidApp], deviceID: UUID) {
        let directory = iconDirectory(for: deviceID)
        let retainedNames = Set(apps.compactMap(\.iconFileName))
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !retainedNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func prune(keeping deviceIDs: Set<UUID>) {
        let validKeys = Set(deviceIDs.map(\.uuidString))
        let previousCount = cache.devices.count
        cache.devices = cache.devices.filter { validKeys.contains($0.key) }
        guard cache.devices.count != previousCount else { return }
        if let deviceDirectories = try? FileManager.default.contentsOfDirectory(
            at: iconsRoot,
            includingPropertiesForKeys: nil
        ) {
            for directory in deviceDirectories where !validKeys.contains(directory.lastPathComponent) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        persist()
    }

    static func diskUsageBytes() -> Int64 {
        fileSize(at: url) + directorySize(at: iconsRoot)
    }

    static func clearAll() {
        cache = DeviceAppCacheFile()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            if FileManager.default.fileExists(atPath: iconsRoot.path) {
                try FileManager.default.removeItem(at: iconsRoot)
            }
        } catch {
            NSLog("Screen Remote: failed to clear app cache: %@", error.localizedDescription)
        }
    }

    private static func fileSize(at file: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func directorySize(at directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func persist() {
        do {
            try FileManager.default.createDirectory(
                at: AppPersistence.directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(cache).write(to: url, options: .atomic)
        } catch {
            NSLog("Screen Remote: failed to save app cache: %@", error.localizedDescription)
        }
    }

    private static func load() -> DeviceAppCacheFile {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(DeviceAppCacheFile.self, from: data) else {
            return DeviceAppCacheFile()
        }
        return value
    }

    private static var iconsRoot: URL {
        AppPersistence.directory.appendingPathComponent("app-icons", isDirectory: true)
    }

    private static func iconDirectory(for deviceID: UUID) -> URL {
        iconsRoot.appendingPathComponent(deviceID.uuidString, isDirectory: true)
    }

    private static func stableFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start..<Swift.min(start + maxCount, count)])
        }
    }
}

struct DeviceAppProcessOutput {
    let status: Int32
    let standardOutput: String
    let standardError: String
    let timedOut: Bool

    var succeeded: Bool { status == 0 && !timedOut }
    var failureDetail: String {
        let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if timedOut { return String.localizedKey("appsManageCommandTimedOut") }
        if !detail.isEmpty { return detail }
        return standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
