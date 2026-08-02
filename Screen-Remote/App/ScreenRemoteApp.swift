import Darwin
import SwiftUI

private final class AppInstanceLock {
    private var fileDescriptor: Int32 = -1

    deinit {
        guard fileDescriptor >= 0 else { return }
        close(fileDescriptor)
    }

    func acquire() -> Bool {
        let fileManager = FileManager.default
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let lockDirectory = applicationSupportDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "ScreenRemote", isDirectory: true)

        do {
            try fileManager.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("Unable to create the app instance lock directory: %@", error.localizedDescription)
            return true
        }

        let lockFileURL = lockDirectory.appendingPathComponent("instance.lock")
        let descriptor = open(lockFileURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            NSLog("Unable to open the app instance lock file. errno=%d", errno)
            return true
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            close(descriptor)

            if lockError != EWOULDBLOCK && lockError != EAGAIN {
                NSLog("Unable to acquire the app instance lock. errno=%d", lockError)
                return true
            }
            return false
        }

        fileDescriptor = descriptor
        return true
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let instanceLock = AppInstanceLock()
    private var statusItem: NSStatusItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !instanceLock.acquire() else { return }
        activateExistingInstance()
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshStatusItem),
            name: .screenRemoteRefreshMenuBar,
            object: nil
        )
    }

    private func installStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle.angled",
                accessibilityDescription: String.localizedKey("menuBarScreenRemote")
            )
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(menuItem("menuBarOpenScreenRemote", action: #selector(openMainWindow)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("menuBarVirtualDevices", action: #selector(openVirtualDevices)))
        menu.addItem(menuItem("menuBarCreateVirtualDevice", action: #selector(createVirtualDevice)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("menuBarQuit", action: #selector(quitApplication)))
        item.menu = menu
        statusItem = item
    }

    @objc private func refreshStatusItem() {
        installStatusItem()
    }

    private func menuItem(_ localizationKey: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: String.localizedKey(localizationKey), action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openMainWindow() {
        activateMainWindow()
    }

    @objc private func openVirtualDevices() {
        activateMainWindow()
        NotificationCenter.default.post(name: .screenRemoteOpenVirtualDevices, object: nil)
    }

    @objc private func createVirtualDevice() {
        activateMainWindow()
        NotificationCenter.default.post(name: .screenRemoteCreateVirtualDevice, object: nil)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func activateMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier }?
            .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}

extension Notification.Name {
    static let screenRemoteOpenVirtualDevices = Notification.Name("ScreenRemote.openVirtualDevices")
    static let screenRemoteCreateVirtualDevice = Notification.Name("ScreenRemote.createVirtualDevice")
    static let screenRemoteRefreshMenuBar = Notification.Name("ScreenRemote.refreshMenuBar")
    static let screenRemoteSelectAllLogs = Notification.Name("ScreenRemote.selectAllLogs")
    static let screenRemoteScrollLogsToBottom = Notification.Name("ScreenRemote.scrollLogsToBottom")
}

@main
struct ScreenRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environment(\.locale, appState.resolvedLocale)
                .frame(
                    minWidth: MainWindowMetrics.minimumWidth,
                    idealWidth: MainWindowMetrics.preferredWidth,
                    maxWidth: .infinity,
                    minHeight: MainWindowMetrics.minimumHeight,
                    idealHeight: MainWindowMetrics.preferredHeight,
                    maxHeight: .infinity
                )
                .appMainWindowSizing(
                    defaultWidth: MainWindowMetrics.preferredWidth,
                    defaultHeight: MainWindowMetrics.preferredHeight,
                    minimumWidth: MainWindowMetrics.minimumWidth,
                    minimumHeight: MainWindowMetrics.minimumHeight
                )
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environment(\.locale, appState.resolvedLocale)
                .id(appState.appLanguage)
                .appPresentationWidth(
                    relativeTo: appState.appWindowWidth,
                    idealWidth: AppPresentationMetrics.IdealWidth.settings
                )
                .appPresentationHeight(relativeTo: appState.appWindowHeight)
        }
    }
}
