import SwiftUI

private enum AppVisibilityFilter: String, CaseIterable, Identifiable {
    case user
    case system
    case all

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .user: "appsUserAppsFilter"
        case .system: "appsSystemAppsFilter"
        case .all: "appsAllSection"
        }
    }
}

private enum AppEnabledFilter: String, CaseIterable, Identifiable {
    case enabled
    case disabled
    case all

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .enabled: "appsEnabledAppsFilter"
        case .disabled: "appsDisabledAppsFilter"
        case .all: "appsAllStatesFilter"
        }
    }
}

struct AppsView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @ObservedObject var appManager: DeviceAppsManager
    @ObservedObject var sessionManager: ScreenSessionManager
    @State private var searchText = ""
    @State private var appFilter = AppVisibilityFilter.user
    @State private var enabledFilter = AppEnabledFilter.enabled

    private var filteredManagedApps: [ManagedAndroidApp] {
        let visibleApps: [ManagedAndroidApp]
        switch appFilter {
        case .user:
            visibleApps = appManager.apps.filter { !$0.isSystem }
        case .system:
            visibleApps = appManager.apps.filter(\.isSystem)
        case .all:
            visibleApps = appManager.apps
        }
        let stateFilteredApps: [ManagedAndroidApp]
        switch enabledFilter {
        case .enabled:
            stateFilteredApps = visibleApps.filter(\.isEnabled)
        case .disabled:
            stateFilteredApps = visibleApps.filter { !$0.isEnabled }
        case .all:
            stateFilteredApps = visibleApps
        }
        guard !searchText.isEmpty else { return stateFilteredApps }
        let terms = searchText.split(whereSeparator: \.isWhitespace)
        return stateFilteredApps.filter { app in
            terms.allSatisfy { term in
                app.name.localizedCaseInsensitiveContains(term)
                    || app.packageName.localizedCaseInsensitiveContains(term)
            }
        }
    }

    private var currentDevice: Device? {
        appState.devices.indices.contains(appState.selectedDevice)
            ? appState.devices[appState.selectedDevice]
            : nil
    }

    private var currentSessionPhase: ScreenSessionPhase? {
        currentDevice.map { sessionManager.session(for: $0.id).phase }
    }

    private var connectedDevice: Device? {
        guard let currentDevice else { return nil }
        switch currentSessionPhase {
        case .connected, .buildingCommand, .launching, .running:
            return currentDevice
        case .none, .idle, .checkingExisting, .racing, .reconnecting, .stopped, .failed:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(
                    columns: statColumns,
                    spacing: 14
                ) {
                    StatCard(
                        icon: "person.crop.square",
                        value: "\(userInstalledAppCount)",
                        label: "appsUserInstalledCount",
                        color: .green
                    )
                    StatCard(
                        icon: "apps.iphone",
                        value: "\(connectedDevice == nil ? 0 : appManager.apps.count)",
                        label: "appsInstalledCount",
                        color: .blue
                    )
                }

                appsContent
            }
            .padding(isCompact ? 20 : 28)
        }
        .alert(item: $appManager.actionResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("commonOK"))
            )
        }
        .sheet(item: $appManager.presentedDetail) { detail in
            DeviceAppDetailView(
                detail: detail,
                icon: appManager.icons[detail.app.packageName]
            )
        }
        .onChange(of: currentDevice?.id) { _ in
            synchronizeAppManager()
        }
        .onChange(of: currentSessionPhase) { _ in
            synchronizeAppManager()
        }
        .onAppear {
            synchronizeAppManager()
        }
        .onDisappear {
            appManager.endManaging()
        }
    }

    @ViewBuilder
    private var appsContent: some View {
        if let device = connectedDevice {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    PageSearchField(
                        searchText: $searchText,
                        searchPrompt: "appsSearchPrompt",
                        expands: true
                    )
                    appListControls
                }
            } else {
                HStack(spacing: 10) {
                    appListTitle
                    Spacer(minLength: 12)
                    PageSearchField(
                        searchText: $searchText,
                        searchPrompt: "appsSearchPrompt",
                        expands: false
                    )
                    appFilters
                }
            }

            if appManager.isLoading {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.75)
                    Text("appsManageLoading")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if filteredManagedApps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: searchText.isEmpty ? "apps.iphone" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "appsManageEmpty" : "appsManageNoSearchResults")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filteredManagedApps) { app in
                        ManagedAppGridItem(
                            app: app,
                            icon: appManager.icons[app.packageName],
                            isBusy: appManager.busyPackageNames.contains(app.packageName),
                            isLaunchingVirtualDisplay: sessionManager.isLaunchingAppVirtualDisplay(
                                deviceID: device.id,
                                packageName: app.packageName
                            ),
                            openVirtualDisplay: {
                                sessionManager.openAppOnVirtualDisplay(
                                    app: app,
                                    device: device,
                                    adbPath: appState.adbPath,
                                    scrcpyPath: appState.scrcpyPath,
                                    log: { appState.appendSDLLog($0) }
                                )
                            },
                            launchOnDevice: { appManager.launchOnDevice(app, on: device, appState: appState) },
                            toggleEnabled: {
                                appManager.setEnabled(!app.isEnabled, for: app, on: device, appState: appState)
                            },
                            clearData: { appManager.clearData(for: app, on: device, appState: appState) },
                            forceStop: { appManager.forceStop(app, on: device, appState: appState) },
                            showDetails: { appManager.showDetails(for: app, on: device, appState: appState) },
                            exportAPK: { appManager.exportAPK(for: app, on: device, appState: appState) },
                            uninstall: { appManager.uninstall(app, from: device, appState: appState) }
                        )
                    }
                }
            }
        } else if currentDevice == nil {
            Text("appsManageNoDevice")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            ContentUnavailableViewCompat(
                icon: "cable.connector",
                title: "appsSessionRequiredTitle",
                detail: "appsSessionRequiredDetail"
            )
            .frame(minHeight: 260)
        }
    }

    private func synchronizeAppManager() {
        guard let connectedDevice else {
            appManager.endManaging()
            return
        }
        appManager.beginManaging(for: connectedDevice, appState: appState)
    }

    private var appListTitle: some View {
        Text(searchText.isEmpty ? "appsManageInstalledSection" : "appsSearchResultsSection")
            .font(.headline)
    }

    private var userInstalledAppCount: Int {
        guard connectedDevice != nil else { return 0 }
        return appManager.apps.lazy.filter { !$0.isSystem }.count
    }

    private var statColumns: [GridItem] {
        if isCompact {
            return [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 14)]
        }
        return Array(
            repeating: GridItem(.flexible(minimum: 200, maximum: 320), spacing: 14),
            count: 2
        )
    }

    private var appListControls: some View {
        HStack(spacing: 10) {
            appListTitle
            Spacer()
            appFilters
        }
    }

    private var appFilters: some View {
        HStack(spacing: 10) {
            Picker("appsTypeFilterTitle", selection: $appFilter) {
                ForEach(AppVisibilityFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Picker("appsStateFilterTitle", selection: $enabledFilter) {
                ForEach(AppEnabledFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

}
