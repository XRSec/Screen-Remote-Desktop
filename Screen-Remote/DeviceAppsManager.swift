import AppKit
import Foundation

struct ManagedAndroidApp: Identifiable, Codable, Equatable {
    let packageName: String
    let name: String
    let isEnabled: Bool
    let isSystem: Bool
    let versionCode: Int64
    let lastUpdateTime: Int64
    let iconFileName: String?

    var id: String { packageName }
}

struct DeviceAppActionResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct DeviceAppDetail: Identifiable {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let usesMonospacedFont: Bool
    }

    let id = UUID()
    let app: ManagedAndroidApp
    let title: String
    let rows: [Row]
}

@MainActor
final class DeviceAppsManager: ObservableObject {
    @Published private(set) var apps: [ManagedAndroidApp] = []
    @Published private(set) var icons: [String: NSImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var busyPackageNames: Set<String> = []
    @Published var actionResult: DeviceAppActionResult?
    @Published var presentedDetail: DeviceAppDetail?

    private var loadedDeviceID: UUID?
    private var loadTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var activeDevice: Device?
    private weak var activeAppState: AppState?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var lastValidationDates: [UUID: Date] = [:]

    init() {
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.validateAfterActivation() }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopBackgroundWork() }
        })
    }

    deinit {
        loadTask?.cancel()
        monitorTask?.cancel()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func beginManaging(for device: Device, appState: AppState) {
        DeviceAppCacheStore.prune(keeping: Set(appState.devices.map(\.id)))
        activeDevice = device
        activeAppState = appState
        loadApps(for: device, appState: appState)
        startChangeMonitor()
    }

    func endManaging() {
        activeDevice = nil
        activeAppState = nil
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    func loadApps(for device: Device, appState: AppState, force: Bool = false) {
        loadTask?.cancel()
        activeDevice = device
        activeAppState = appState

        let cachedEntry = DeviceAppCacheStore.entry(for: device.id)
        if loadedDeviceID != device.id {
            apps = cachedEntry?.apps ?? []
            icons = DeviceAppCacheStore.loadIcons(for: apps, deviceID: device.id)
        } else if apps.isEmpty, let cachedEntry {
            apps = cachedEntry.apps
            icons = DeviceAppCacheStore.loadIcons(for: apps, deviceID: device.id)
        }
        loadedDeviceID = device.id
        isLoading = apps.isEmpty

        let adbPath = appState.adbPath
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let serial = try await DeviceAppADB.resolveSerial(for: device, configuredADBPath: adbPath)
                let remoteApps = try await DeviceAppADB.listApps(
                    serial: serial,
                    configuredADBPath: adbPath
                )
                try Task.checkCancellation()
                self.lastValidationDates[device.id] = Date()

                var loadedApps = DeviceAppCacheStore.reusingCachedIcons(
                    in: remoteApps,
                    cachedApps: cachedEntry?.apps ?? [],
                    deviceID: device.id
                )
                self.apps = loadedApps
                self.icons = DeviceAppCacheStore.loadIcons(for: loadedApps, deviceID: device.id)
                self.isLoading = false
                DeviceAppCacheStore.save(
                    apps: loadedApps,
                    for: device.id
                )
                appState.appendSDLLog("Installed apps loaded with DADB helper: \(device.name), count=\(loadedApps.count)")

                let packagesNeedingIcons = loadedApps.compactMap { app -> String? in
                    if force || app.iconFileName == nil || self.icons[app.packageName] == nil {
                        return app.packageName
                    }
                    return nil
                }
                guard !packagesNeedingIcons.isEmpty else {
                    appState.appendSDLLog("Installed app icon cache validated: \(device.name), count=\(self.icons.count)")
                    return
                }

                do {
                    for packageBatch in packagesNeedingIcons.chunked(maxCount: 64) {
                        try Task.checkCancellation()
                        let iconEntries = try await DeviceAppADB.loadAppIcons(
                            packageNames: packageBatch,
                            serial: serial,
                            configuredADBPath: adbPath
                        )
                        try Task.checkCancellation()
                        let iconsByPackage = Dictionary(uniqueKeysWithValues: iconEntries.map { ($0.packageName, $0) })
                        loadedApps = loadedApps.map { app in
                            guard let entry = iconsByPackage[app.packageName],
                                  let fileName = DeviceAppCacheStore.saveIcon(
                                    entry.imageData,
                                    packageName: entry.packageName,
                                    versionCode: entry.versionCode,
                                    lastUpdateTime: entry.lastUpdateTime,
                                    deviceID: device.id
                                  ) else { return app }
                            if let image = NSImage(data: entry.imageData) {
                                self.icons[entry.packageName] = image
                            }
                            return ManagedAndroidApp(
                                packageName: app.packageName,
                                name: entry.name.isEmpty ? app.name : entry.name,
                                isEnabled: app.isEnabled,
                                isSystem: app.isSystem,
                                versionCode: entry.versionCode,
                                lastUpdateTime: entry.lastUpdateTime,
                                iconFileName: fileName
                            )
                        }
                        self.apps = loadedApps
                        DeviceAppCacheStore.save(apps: loadedApps, for: device.id)
                    }
                    DeviceAppCacheStore.pruneIcons(for: loadedApps, deviceID: device.id)
                    appState.appendSDLLog("Installed app icons loaded with DADB helper: \(device.name), count=\(self.icons.count)")
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    appState.appendSDLLog("Failed to load installed app icons: \(device.name), \(error.localizedDescription)")
                }
            } catch is CancellationError {
                self.isLoading = false
            } catch {
                self.isLoading = false
                if self.apps.isEmpty {
                    self.actionResult = DeviceAppActionResult(
                        title: String.localizedKey("appsManageLoadFailedTitle"),
                        message: error.localizedDescription
                    )
                }
                appState.appendSDLLog("Failed to load installed apps: \(device.name), \(error.localizedDescription)")
            }
        }
    }

    func clearData(for app: ManagedAndroidApp, on device: Device, appState: AppState) {
        guard confirm(
            title: String(format: String.localizedKey("appsManageClearDataConfirmTitle"), app.name),
            message: String.localizedKey("appsManageClearDataConfirmMessage"),
            actionTitle: String.localizedKey("appsManageClearData")
        ) else { return }

        perform(app: app, device: device, appState: appState) { serial, adbPath in
            let output = try await DeviceAppADB.runADB(
                configuredADBPath: adbPath,
                arguments: ["-s", serial, "shell", "pm", "clear", app.packageName],
                timeout: 20
            )
            guard output.succeeded, output.standardOutput.localizedCaseInsensitiveContains("success") else {
                throw DeviceAppManagementError.commandFailed(output.failureDetail)
            }
            return DeviceAppActionResult(
                title: String.localizedKey("appsManageClearDataCompleteTitle"),
                message: String(format: String.localizedKey("appsManageClearDataCompleteMessage"), app.name)
            )
        }
    }

    func launchOnDevice(_ app: ManagedAndroidApp, on device: Device, appState: AppState) {
        perform(app: app, device: device, appState: appState) { serial, adbPath in
            let output = try await DeviceAppADB.runADB(
                configuredADBPath: adbPath,
                arguments: [
                    "-s", serial, "shell", "monkey", "-p", app.packageName,
                    "-c", "android.intent.category.LAUNCHER", "1"
                ],
                timeout: 20
            )
            guard output.succeeded else {
                throw DeviceAppManagementError.commandFailed(output.failureDetail)
            }
            return DeviceAppActionResult(
                title: String.localizedKey("appsManageLaunchCompleteTitle"),
                message: String(format: String.localizedKey("appsManageLaunchCompleteMessage"), app.name)
            )
        }
    }

    func setEnabled(_ enabled: Bool, for app: ManagedAndroidApp, on device: Device, appState: AppState) {
        perform(app: app, device: device, appState: appState, refreshAfterCompletion: true) { serial, adbPath in
            let command = enabled ? ["pm", "enable", app.packageName] : ["pm", "disable-user", "--user", "0", app.packageName]
            let output = try await DeviceAppADB.runADB(
                configuredADBPath: adbPath,
                arguments: ["-s", serial, "shell"] + command,
                timeout: 20
            )
            guard output.succeeded else {
                throw DeviceAppManagementError.commandFailed(output.failureDetail)
            }
            return DeviceAppActionResult(
                title: String.localizedKey(enabled ? "appsManageEnableCompleteTitle" : "appsManageDisableCompleteTitle"),
                message: String(
                    format: String.localizedKey(enabled ? "appsManageEnableCompleteMessage" : "appsManageDisableCompleteMessage"),
                    app.name
                )
            )
        }
    }

    func forceStop(_ app: ManagedAndroidApp, on device: Device, appState: AppState) {
        guard confirm(
            title: String(format: String.localizedKey("appsManageForceStopConfirmTitle"), app.name),
            message: String.localizedKey("appsManageForceStopConfirmMessage"),
            actionTitle: String.localizedKey("appsManageForceStop")
        ) else { return }

        perform(app: app, device: device, appState: appState) { serial, adbPath in
            let output = try await DeviceAppADB.runADB(
                configuredADBPath: adbPath,
                arguments: ["-s", serial, "shell", "am", "force-stop", app.packageName],
                timeout: 20
            )
            guard output.succeeded else {
                throw DeviceAppManagementError.commandFailed(output.failureDetail)
            }
            return DeviceAppActionResult(
                title: String.localizedKey("appsManageForceStopCompleteTitle"),
                message: String(format: String.localizedKey("appsManageForceStopCompleteMessage"), app.name)
            )
        }
    }

    func showDetails(for app: ManagedAndroidApp, on device: Device, appState: AppState) {
        guard busyPackageNames.insert(app.packageName).inserted else { return }
        let adbPath = appState.adbPath
        Task { [weak self] in
            guard let self else { return }
            defer { self.busyPackageNames.remove(app.packageName) }
            do {
                let serial = try await DeviceAppADB.resolveSerial(for: device, configuredADBPath: adbPath)
                let output = try await DeviceAppADB.runADB(
                    configuredADBPath: adbPath,
                    arguments: ["-s", serial, "shell", "dumpsys", "package", app.packageName],
                    timeout: 20
                )
                guard output.succeeded else {
                    throw DeviceAppManagementError.commandFailed(output.failureDetail)
                }
                let unknown = String.localizedKey("appsManageUnknownValue")
                let row: (String, String, Bool) -> DeviceAppDetail.Row = {
                    DeviceAppDetail.Row(
                        label: String.localizedKey($0),
                        value: $1,
                        usesMonospacedFont: $2
                    )
                }
                self.presentedDetail = DeviceAppDetail(
                    app: app,
                    title: String.localizedKey("appsManageDetails"),
                    rows: [
                        row("appsManageDetailPackage", app.packageName, true),
                        row(
                            "appsManageDetailType",
                            String.localizedKey(app.isSystem ? "appsSystemAppsFilter" : "appsUserAppsFilter"),
                            false
                        ),
                        row(
                            "appsManageDetailStatus",
                            String.localizedKey(app.isEnabled ? "appsEnabledAppsFilter" : "appsDisabledAppsFilter"),
                            false
                        ),
                        row(
                            "appsManageDetailVersion",
                            DeviceAppADB.packageValue(named: "versionName", in: output.standardOutput) ?? unknown,
                            false
                        ),
                        row(
                            "appsManageDetailVersionCode",
                            DeviceAppADB.packageValue(named: "versionCode", in: output.standardOutput) ?? unknown,
                            false
                        ),
                        row(
                            "appsManageDetailUID",
                            DeviceAppADB.packageValue(named: "userId", in: output.standardOutput) ?? unknown,
                            false
                        ),
                        row(
                            "appsManageDetailNativeABIs",
                            DeviceAppADB.packageValue(named: "primaryCpuAbi", in: output.standardOutput) ?? unknown,
                            false
                        ),
                        row(
                            "appsManageDetailMinSDK",
                            DeviceAppADB.packageValue(named: "minSdk", in: output.standardOutput) ?? unknown,
                            false
                        ),
                        row(
                            "appsManageDetailTargetSDK",
                            DeviceAppADB.packageValue(named: "targetSdk", in: output.standardOutput) ?? unknown,
                            false
                        ),
                        row(
                            "appsManageDetailAPKPath",
                            DeviceAppADB.packageValue(named: "codePath", in: output.standardOutput) ?? unknown,
                            true
                        ),
                        row(
                            "appsManageDetailFirstInstalled",
                            DeviceAppADB.firstValue(named: "firstInstallTime", in: output.standardOutput) ?? unknown,
                            false
                        ),
                        row(
                            "appsManageDetailLastUpdated",
                            DeviceAppADB.firstValue(named: "lastUpdateTime", in: output.standardOutput) ?? unknown,
                            false
                        ),
                    ]
                )
                appState.appendSDLLog("App details loaded: \(app.packageName)")
            } catch {
                self.actionResult = DeviceAppActionResult(
                    title: String.localizedKey("appsManageActionFailedTitle"),
                    message: error.localizedDescription
                )
                appState.appendSDLLog("Failed to load app details: \(app.packageName), \(error.localizedDescription)")
            }
        }
    }

    func exportAPK(for app: ManagedAndroidApp, on device: Device, appState: AppState) {
        let panel = NSSavePanel()
        panel.title = String.localizedKey("appsManageExportAPKPanelTitle")
        panel.nameFieldStringValue = "\(app.packageName).apk"
        panel.canCreateDirectories = true
        panel.allowedFileTypes = ["apk"]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        perform(app: app, device: device, appState: appState) { serial, adbPath in
            let pathOutput = try await DeviceAppADB.runADB(
                configuredADBPath: adbPath,
                arguments: ["-s", serial, "shell", "pm", "path", app.packageName],
                timeout: 20
            )
            guard pathOutput.succeeded,
                  let remotePath = pathOutput.standardOutput
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .first(where: { $0.hasPrefix("package:") })?
                    .dropFirst("package:".count) else {
                throw DeviceAppManagementError.commandFailed(pathOutput.failureDetail)
            }
            let pullOutput = try await DeviceAppADB.runADB(
                configuredADBPath: adbPath,
                arguments: ["-s", serial, "pull", String(remotePath), destination.path],
                timeout: 120
            )
            guard pullOutput.succeeded else {
                throw DeviceAppManagementError.commandFailed(pullOutput.failureDetail)
            }
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
            return DeviceAppActionResult(
                title: String.localizedKey("appsManageExportAPKCompleteTitle"),
                message: String(format: String.localizedKey("appsManageExportAPKCompleteMessage"), destination.lastPathComponent)
            )
        }
    }

    func uninstall(_ app: ManagedAndroidApp, from device: Device, appState: AppState) {
        guard confirm(
            title: String(format: String.localizedKey("appsManageUninstallConfirmTitle"), app.name),
            message: String.localizedKey("appsManageUninstallConfirmMessage"),
            actionTitle: String.localizedKey("appsManageUninstall")
        ) else { return }

        perform(app: app, device: device, appState: appState) { [weak self] serial, adbPath in
            let output = try await DeviceAppADB.runADB(
                configuredADBPath: adbPath,
                arguments: ["-s", serial, "uninstall", app.packageName],
                timeout: 90
            )
            guard output.succeeded, output.standardOutput.localizedCaseInsensitiveContains("success") else {
                throw DeviceAppManagementError.commandFailed(output.failureDetail)
            }
            await MainActor.run {
                self?.apps.removeAll { $0.packageName == app.packageName }
                self?.icons.removeValue(forKey: app.packageName)
                if let self {
                    DeviceAppCacheStore.save(
                        apps: self.apps,
                        for: device.id
                    )
                    DeviceAppCacheStore.pruneIcons(for: self.apps, deviceID: device.id)
                }
            }
            return DeviceAppActionResult(
                title: String.localizedKey("appsManageUninstallCompleteTitle"),
                message: String(format: String.localizedKey("appsManageUninstallCompleteMessage"), app.name)
            )
        }
    }

    private func perform(
        app: ManagedAndroidApp,
        device: Device,
        appState: AppState,
        refreshAfterCompletion: Bool = false,
        operation: @escaping (String, String) async throws -> DeviceAppActionResult
    ) {
        guard busyPackageNames.insert(app.packageName).inserted else { return }
        let adbPath = appState.adbPath
        Task { [weak self] in
            guard let self else { return }
            defer { self.busyPackageNames.remove(app.packageName) }
            do {
                let serial = try await DeviceAppADB.resolveSerial(for: device, configuredADBPath: adbPath)
                self.actionResult = try await operation(serial, adbPath)
                appState.appendSDLLog("App management action completed: \(app.packageName)")
                if refreshAfterCompletion {
                    self.loadApps(for: device, appState: appState, force: true)
                }
            } catch {
                self.actionResult = DeviceAppActionResult(
                    title: String.localizedKey("appsManageActionFailedTitle"),
                    message: error.localizedDescription
                )
                appState.appendSDLLog("App management action failed: \(app.packageName), \(error.localizedDescription)")
            }
        }
    }

    private func confirm(title: String, message: String, actionTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: String.localizedKey("commonCancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func validateAfterActivation() {
        guard let device = activeDevice, let appState = activeAppState else { return }
        if let lastValidation = lastValidationDates[device.id],
           Date().timeIntervalSince(lastValidation) < 5 {
            return
        }
        loadApps(for: device, appState: appState)
    }

    private func startChangeMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      let device = self.activeDevice,
                      let appState = self.activeAppState else { return }
                self.loadApps(for: device, appState: appState)
            }
        }
    }

    private func stopBackgroundWork() {
        loadTask?.cancel()
        monitorTask?.cancel()
    }
}

private enum DeviceAppManagementError: LocalizedError {
    case adbNotFound
    case helperNotFound
    case noConnection
    case unauthorized
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .adbNotFound: String.localizedKey("appsManageADBNotFound")
        case .helperNotFound: String.localizedKey("appsManageHelperNotFound")
        case .noConnection: String.localizedKey("appsManageNoConnection")
        case .unauthorized: String.localizedKey("appsManageUnauthorized")
        case .commandFailed(let detail):
            detail.isEmpty
                ? String.localizedKey("appsManageCommandFailed")
                : String(format: String.localizedKey("appsManageCommandFailedWithDetails"), detail)
        }
    }
}

private enum DeviceAppADB {
    private static let helperMainClass = "dadb.helper.AppIconExportMain"

    static func resolveSerial(for device: Device, configuredADBPath: String) async throws -> String {
        let adbPath = executablePath(configuredADBPath, kind: .adb)
        guard FileManager.default.isExecutableFile(atPath: adbPath) else {
            throw DeviceAppManagementError.adbNotFound
        }

        let devicesOutput = try await runADB(
            configuredADBPath: adbPath,
            arguments: ["devices"],
            timeout: 8
        )
        guard devicesOutput.succeeded else {
            throw DeviceAppManagementError.commandFailed(devicesOutput.failureDetail)
        }
        let states = parseDeviceStates(devicesOutput.standardOutput)
        let candidates = device.connections.sorted { $0.priority < $1.priority }

        for connection in candidates {
            let serial = serial(for: connection)
            guard !serial.isEmpty, let state = matchingState(for: serial, in: states) else { continue }
            if state == "device" { return serial }
            if state == "unauthorized" { throw DeviceAppManagementError.unauthorized }
        }

        throw DeviceAppManagementError.noConnection
    }

    static func listApps(
        serial: String,
        configuredADBPath: String
    ) async throws -> [ManagedAndroidApp] {
        let helper = try await preparedHelper(
            serial: serial,
            configuredADBPath: configuredADBPath
        )

        let pageSize = 250
        var offset = 0
        var result: [ManagedAndroidApp] = []
        while true {
            let output = try await helper.invoke(
                mainClass: helperMainClass,
                arguments: ["list", String(offset), String(pageSize), "1"],
                timeout: 40
            )
            let page = try parseAppList(output.standardOutput)
            result.append(contentsOf: page)
            guard page.count == pageSize else { break }
            offset += page.count
        }
        return result.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func loadAppIcons(
        packageNames: [String],
        serial: String,
        configuredADBPath: String
    ) async throws -> [RemoteAppIcon] {
        guard !packageNames.isEmpty else { return [] }
        let request = packageNames.joined(separator: "\n")
        let payload = Data(request.utf8).base64EncodedString()
        let helper = try await preparedHelper(
            serial: serial,
            configuredADBPath: configuredADBPath
        )
        let output = try await helper.invoke(
            mainClass: helperMainClass,
            arguments: ["icons", payload],
            timeout: 90
        )
        return try await parseIconBatch(output.standardOutput)
    }

    private static func preparedHelper(
        serial: String,
        configuredADBPath: String
    ) async throws -> PreparedDADBHelper {
        do {
            return try await DADBHelperRuntime.prepare(
                serial: serial,
                configuredADBPath: configuredADBPath
            )
        } catch let error as DADBHelperRuntimeError {
            switch error {
            case .adbNotFound:
                throw DeviceAppManagementError.adbNotFound
            case .helperNotFound:
                throw DeviceAppManagementError.helperNotFound
            case .commandFailed(let detail):
                throw DeviceAppManagementError.commandFailed(detail)
            }
        }
    }

    private static func parseAppList(_ output: String) throws -> [ManagedAndroidApp] {
        try output.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 7,
                  let labelData = Data(base64Encoded: fields[1]),
                  let label = String(data: labelData, encoding: .utf8),
                  let versionCode = Int64(fields[5]),
                  let lastUpdateTime = Int64(fields[6]) else {
                throw DeviceAppManagementError.commandFailed("DADB helper returned an invalid app list record.")
            }
            return ManagedAndroidApp(
                packageName: fields[0],
                name: label.isEmpty ? fields[0] : label,
                isEnabled: fields[2] == "1",
                isSystem: fields[3] == "1",
                versionCode: versionCode,
                lastUpdateTime: lastUpdateTime,
                iconFileName: nil
            )
        }
    }

    private static func parseIconBatch(_ output: String) async throws -> [RemoteAppIcon] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3, lines[0] == "BATCH" else {
            throw DeviceAppManagementError.commandFailed("DADB helper returned an invalid icon batch header.")
        }
        guard lines[1] != "-", lines[2] != "-" else { return [] }
        guard let manifestData = Data(base64Encoded: lines[1]),
              let manifest = String(data: manifestData, encoding: .utf8),
              let zipData = Data(base64Encoded: lines[2]) else {
            throw DeviceAppManagementError.commandFailed("DADB helper returned invalid icon batch data.")
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-remote-icons-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = temporaryDirectory.appendingPathComponent("icons.zip")
        let extractedURL = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(at: extractedURL, withIntermediateDirectories: true)
        try zipData.write(to: archiveURL, options: .atomic)
        let extraction = try await run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractedURL.path],
            environment: [:],
            timeout: 20
        )
        guard extraction.succeeded else {
            throw DeviceAppManagementError.commandFailed(extraction.failureDetail)
        }

        return try manifest.split(whereSeparator: \.isNewline).map { rawLine in
            let fields = String(rawLine).components(separatedBy: "\t")
            guard fields.count >= 6,
                  !fields[5].contains("/"),
                  !fields[5].contains(".."),
                  let labelData = Data(base64Encoded: fields[1]),
                  let label = String(data: labelData, encoding: .utf8),
                  let versionCode = Int64(fields[2]),
                  let lastUpdateTime = Int64(fields[4]) else {
                throw DeviceAppManagementError.commandFailed("DADB helper returned an invalid icon manifest record.")
            }
            let imageData = try Data(contentsOf: extractedURL.appendingPathComponent(fields[5]))
            guard NSImage(data: imageData) != nil else {
                throw DeviceAppManagementError.commandFailed("DADB helper returned invalid app icon image data.")
            }
            return RemoteAppIcon(
                packageName: fields[0],
                name: label,
                versionCode: versionCode,
                lastUpdateTime: lastUpdateTime,
                imageData: imageData
            )
        }
    }

    static func runADB(
        configuredADBPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> DeviceAppProcessOutput {
        let adbPath = executablePath(configuredADBPath, kind: .adb)
        guard FileManager.default.isExecutableFile(atPath: adbPath) else {
            throw DeviceAppManagementError.adbNotFound
        }
        return try await run(executable: adbPath, arguments: arguments, environment: [:], timeout: timeout)
    }

    static func firstValue(named key: String, in output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("\(key)=") })?
            .dropFirst(key.count + 1)
            .description
    }

    static func packageValue(named key: String, in output: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        guard let expression = try? NSRegularExpression(
            pattern: "(?:^|\\s)\(escapedKey)=([^\\s]+)",
            options: [.anchorsMatchLines]
        ) else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = expression.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        let value = String(output[valueRange])
        return value == "null" ? nil : value
    }

    private static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) async throws -> DeviceAppProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                var processEnvironment = ProcessInfo.processInfo.environment
                environment.forEach { processEnvironment[$0.key] = $0.value }
                process.environment = processEnvironment

                do {
                    try process.run()
                    let lock = NSLock()
                    var timedOut = false
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard process.isRunning else { return }
                        timedOut = true
                        process.terminate()
                    }
                    let group = DispatchGroup()
                    var stdout = Data()
                    var stderr = Data()
                    group.enter()
                    DispatchQueue.global().async {
                        stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    process.waitUntilExit()
                    group.wait()
                    lock.lock()
                    let didTimeOut = timedOut
                    lock.unlock()
                    continuation.resume(returning: DeviceAppProcessOutput(
                        status: process.terminationStatus,
                        standardOutput: String(decoding: stdout, as: UTF8.self),
                        standardError: String(decoding: stderr, as: UTF8.self),
                        timedOut: didTimeOut
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func parseDeviceStates(_ output: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> (String, String)? in
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count >= 2 else { return nil }
                return (normalize(fields[0]), fields[1].lowercased())
            })
    }

    private static func matchingState(for serial: String, in states: [String: String]) -> String? {
        states[normalize(serial)]
    }

    private static func serial(for connection: DeviceConnection) -> String {
        switch connection.transport {
        case .usb:
            return connection.serial.trimmingCharacters(in: .whitespacesAndNewlines)
        case .tcp:
            let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return "" }
            if host.hasPrefix("[") || host.filter({ $0 == ":" }).count <= 1 {
                return "\(host):\(connection.port)"
            }
            return "[\(host)]:\(connection.port)"
        case .mdns:
            return connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func normalize(_ value: String) -> String {
        sanitizedSerial(value)
            .lowercased()
    }

    private static func sanitizedSerial(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".:", with: ":")
    }

    private static func executablePath(_ configured: String, kind: ToolDownloadKind) -> String {
        FileManager.default.isExecutableFile(atPath: configured)
            ? configured
            : (ToolLocator.find(kind) ?? configured)
    }

}

private struct RemoteAppIcon {
    let packageName: String
    let name: String
    let versionCode: Int64
    let lastUpdateTime: Int64
    let imageData: Data
}

private struct DeviceAppCacheEntry: Codable {
    let apps: [ManagedAndroidApp]
    let updatedAt: Date
}

private struct DeviceAppCacheFile: Codable {
    var version = 2
    var devices: [String: DeviceAppCacheEntry] = [:]
}

@MainActor
private enum DeviceAppCacheStore {
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

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start..<Swift.min(start + maxCount, count)])
        }
    }
}

private extension String {
    var firstNonemptyLine: String? {
        split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
}

private struct DeviceAppProcessOutput {
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
