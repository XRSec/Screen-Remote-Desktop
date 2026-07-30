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

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !instanceLock.acquire() else { return }
        activateExistingInstance()
        NSApp.terminate(nil)
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

@main
struct ScreenRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environment(\.locale, appState.resolvedLocale)
                .frame(minWidth: 1_040, minHeight: 680)
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
                .frame(
                    width: 620,
                    height: SettingsWindowMetrics.preferredHeight(relativeTo: appState.appWindowHeight)
                )
        }
    }
}
