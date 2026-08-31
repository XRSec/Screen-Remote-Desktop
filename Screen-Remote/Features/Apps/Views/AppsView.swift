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

    private var searchTerms: [String] {
        searchText.split(whereSeparator: \.isWhitespace).map(String.init)
    }

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
        guard !searchTerms.isEmpty else { return stateFilteredApps }
        return stateFilteredApps.filter { app in
            searchTerms.allSatisfy { term in
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
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                HStack(spacing: 18) {
                    summaryMetric(
                        icon: "person.crop.square",
                        value: "\(userInstalledAppCount)",
                        label: "appsUserInstalledCount",
                        color: .green
                    )
                    Divider().frame(height: 28)
                    summaryMetric(
                        icon: "apps.iphone",
                        value: "\(connectedDevice == nil ? 0 : appManager.apps.count)",
                        label: "appsInstalledCount",
                        color: .blue
                    )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)

                appsContent
            }
            .padding(isCompact ? 20 : 28)
        }
        .background(AppTheme.background)
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
                VStack(spacing: AppSpacing.md) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .accessibilityHidden(true)
                    Text("appsManageLoading")
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                }
                .padding(AppSpacing.xl)
                .frame(maxWidth: .infinity, minHeight: 220)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("appsManageLoading"))
            } else if filteredManagedApps.isEmpty {
                ContentUnavailableViewCompat(
                    icon: appManager.apps.isEmpty ? "apps.iphone" : "magnifyingglass",
                    title: appManager.apps.isEmpty ? "appsManageEmpty" : "appsManageNoSearchResults",
                    detail: "appsSearchPrompt",
                    actionTitle: appManager.apps.isEmpty ? "commonRefresh" : "commonClear",
                    action: {
                        if appManager.apps.isEmpty {
                            appManager.loadApps(for: device, appState: appState, force: true)
                        } else {
                            searchText = ""
                            appFilter = .all
                            enabledFilter = .all
                        }
                    }
                )
                .padding(AppSpacing.xl)
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filteredManagedApps) { app in
                        ManagedAppGridItem(
                            app: app,
                            icon: appManager.icons[app.packageName],
                            searchTerms: searchTerms,
                            isBusy: appManager.busyPackageNames.contains(app.packageName),
                            isLaunchingApp: sessionManager.isLaunchingAppVirtualDisplay(
                                deviceID: device.id,
                                packageName: app.packageName
                            ),
                            openApp: {
                                sessionManager.openAppInNativeVirtualDisplay(
                                    app: app,
                                    device: device,
                                    appState: appState,
                                    adbPath: appState.adbPath,
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
            ContentUnavailableViewCompat(
                icon: "iphone.slash",
                title: "appsNoDeviceTitle",
                detail: "appsManageNoDevice",
                actionTitle: "addDeviceTitle",
                action: { appState.showingAddDevice = true }
            )
            .padding(AppSpacing.xl)
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            ContentUnavailableViewCompat(
                icon: "cable.connector",
                title: "appsSessionRequiredTitle",
                detail: "appsSessionRequiredDetail",
                actionTitle: "sessionStartAction",
                action: {
                    if let currentDevice {
                        appState.connectScreenSession(deviceID: currentDevice.id)
                    }
                }
            )
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 260)
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
            .font(AppTypography.headline)
    }

    private var userInstalledAppCount: Int {
        guard connectedDevice != nil else { return 0 }
        return appManager.apps.lazy.filter { !$0.isSystem }.count
    }

    private func summaryMetric(
        icon: String,
        value: String,
        label: LocalizedStringKey,
        color: Color
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppTypography.subheadline)
                .foregroundColor(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(AppTypography.subheadline.weight(.semibold))
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
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
            .accessibilityLabel(Text("appsTypeFilterTitle"))
            .pickerStyle(.segmented)
            .fixedSize()
            Picker("appsStateFilterTitle", selection: $enabledFilter) {
                ForEach(AppEnabledFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .accessibilityLabel(Text("appsStateFilterTitle"))
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

}
