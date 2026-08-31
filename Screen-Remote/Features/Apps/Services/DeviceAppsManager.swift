import AppKit
import Foundation

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

    func clearCache() {
        loadTask?.cancel()
        loadTask = nil
        DeviceAppCacheStore.clearAll()
        icons.removeAll()
        apps = apps.map { app in
            ManagedAndroidApp(
                packageName: app.packageName,
                name: app.name,
                isEnabled: app.isEnabled,
                isSystem: app.isSystem,
                versionCode: app.versionCode,
                lastUpdateTime: app.lastUpdateTime,
                iconFileName: nil
            )
        }
        loadedDeviceID = nil
        lastValidationDates.removeAll()
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

                let packagesNeedingIcons = self.packagesNeedingIcons(in: loadedApps, force: force)
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

}

extension DeviceAppsManager {
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

    private func packagesNeedingIcons(in apps: [ManagedAndroidApp], force: Bool) -> [String] {
        apps.compactMap { app in
            guard force || app.iconFileName == nil || icons[app.packageName] == nil else { return nil }
            return app.packageName
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
