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
        case .none, .idle, .checkingExisting, .racing, .stopped, .failed:
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

private struct DeviceAppDetailView: View {
    @Environment(\.presentationMode) private var presentationMode
    let detail: DeviceAppDetail
    let icon: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 72, height: 1)
                Text(detail.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button("commonClose") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(AppTheme.surface)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Group {
                            if let icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                            } else {
                                AppIconTile(symbol: "app.fill", color: .appIndigo, size: 64)
                            }
                        }
                        .frame(width: 64, height: 64)

                        Text(detail.app.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text(detail.app.packageName)
                            .font(.appCaptionMonospaced)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .appTextSelectionEnabled()
                    }
                    .frame(width: 300)

                    VStack(spacing: 0) {
                        ForEach(Array(detail.rows.enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(row.value)
                                    .font(valueFont(for: row))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .appTextSelectionEnabled()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)

                            if index < detail.rows.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .frame(width: 300)
                    .appCard(radius: 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .background(AppTheme.background)
        }
        .frame(width: 450, height: 640)
    }

    private func valueFont(for row: DeviceAppDetail.Row) -> Font {
        row.usesMonospacedFont ? .appCaptionMonospaced : .body
    }
}

struct PageSearchField: View {
    @Binding var searchText: String
    let searchPrompt: LocalizedStringKey
    let expands: Bool

    var body: some View {
        TextField(searchPrompt, text: $searchText)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(minWidth: 120, maxWidth: expands ? .infinity : 230, minHeight: 34, maxHeight: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.055)))
            .overlay(
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).padding(.trailing, 10),
                alignment: .trailing
            )
    }
}

struct SectionTitle: View {
    let title: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    var action: () -> Void = {}

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(actionTitle, action: action).buttonStyle(.plain).font(.caption).foregroundColor(AppTheme.accent)
        }
    }
}

private struct ManagedAppGridItem: View {
    let app: ManagedAndroidApp
    let icon: NSImage?
    let isBusy: Bool
    let isLaunchingVirtualDisplay: Bool
    let openVirtualDisplay: () -> Void
    let launchOnDevice: () -> Void
    let toggleEnabled: () -> Void
    let clearData: () -> Void
    let forceStop: () -> Void
    let showDetails: () -> Void
    let exportAPK: () -> Void
    let uninstall: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                } else {
                    AppIconTile(symbol: "app.fill", color: .appIndigo, size: 48)
                }
                if isBusy || isLaunchingVirtualDisplay {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color.black.opacity(0.42))
                        .frame(width: 48, height: 48)
                    ProgressView().scaleEffect(0.65)
                }
            }
            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(app.packageName)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
        .appOverlay(
            Group {
                if !app.isEnabled {
                    Text("appsDisabledAppsFilter")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .padding(8)
                }
            },
            alignment: .topTrailing
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: openVirtualDisplay)
        .contextMenu {
            Button(action: showDetails) {
                Label("appsManageDetails", systemImage: "info.circle")
            }
            Button(action: launchOnDevice) {
                Label("appsManageLaunchOnDevice", systemImage: "play.fill")
            }
            Button(action: toggleEnabled) {
                Label(
                    app.isEnabled ? "appsManageDisable" : "appsManageEnable",
                    systemImage: app.isEnabled ? "pause.circle" : "checkmark.circle"
                )
            }
            Divider()
            Button(action: uninstall) {
                Label("appsManageUninstall", systemImage: "trash")
            }
            Button(action: clearData) {
                Label("appsManageClearData", systemImage: "trash.slash")
            }
            Button(action: forceStop) {
                Label("appsManageForceStop", systemImage: "stop.circle")
            }
            Button(action: exportAPK) {
                Label("appsManageExportAPK", systemImage: "square.and.arrow.down")
            }
        }
        .disabled(isBusy)
    }
}

private struct StatCard: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(label).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .appCard()
    }
}

private struct RecentAppCard: View {
    let app: PhoneApp

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 11) {
                AppIconTile(symbol: app.icon, color: app.color, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 13, weight: .semibold))
                    Text("appsOpenAction").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundColor(Color.secondary.opacity(0.65))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .appCard()
        }
        .buttonStyle(.plain)
    }
}

private struct AppGridItem: View {
    let app: PhoneApp

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    AppIconTile(symbol: app.icon, color: app.color, size: 48)
                    if app.badge > 0 {
                        Text(verbatim: "\(app.badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(Color.red))
                            .offset(x: 5, y: -5)
                    }
                }
                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line))
        }
        .buttonStyle(.plain)
    }
}
