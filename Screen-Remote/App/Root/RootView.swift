import SwiftUI

enum MainWindowMetrics {
    static let minimumWidth: CGFloat = 520
    static let preferredWidth: CGFloat = 1000
    static let minimumHeight: CGFloat = 600
    static let preferredHeight: CGFloat = 700
    static let compactContentWidth: CGFloat = 620
    static let collapsedSidebarWidth: CGFloat = 55
    static let expandedSidebarWidth: CGFloat = 260
}

enum AppPresentationMetrics {
    static let minimumWidth: CGFloat = 450
    static let widthRatio: CGFloat = 0.85
    static let minimumHeight: CGFloat = 450
    static let maximumHeight: CGFloat = 680
    static let heightRatio: CGFloat = 0.85

    enum IdealWidth {
        static let sessionEditor: CGFloat = 1080
        static let settings: CGFloat = 620
        static let deviceDiscovery: CGFloat = 660
        static let logs: CGFloat = 760
        static let virtualDevices: CGFloat = 620
        static let virtualDeviceEditor: CGFloat = 880
    }

    static func preferredWidth(
        relativeTo appWidth: CGFloat,
        idealWidth: CGFloat = minimumWidth
    ) -> CGFloat {
        min(max(minimumWidth, appWidth * widthRatio), max(minimumWidth, idealWidth))
    }

    static func preferredHeight(
        relativeTo appHeight: CGFloat,
        maximumHeight: CGFloat? = Self.maximumHeight
    ) -> CGFloat {
        let preferredHeight = max(minimumHeight, appHeight * heightRatio)
        guard let maximumHeight else { return preferredHeight }
        return min(preferredHeight, maximumHeight)
    }
}

extension View {
    func appPresentationWidth(
        relativeTo appWidth: CGFloat,
        idealWidth: CGFloat = AppPresentationMetrics.minimumWidth
    ) -> some View {
        frame(width: AppPresentationMetrics.preferredWidth(
            relativeTo: appWidth,
            idealWidth: idealWidth
        ))
    }

    func appPresentationHeight(
        relativeTo appHeight: CGFloat,
        maximumHeight: CGFloat? = AppPresentationMetrics.maximumHeight
    ) -> some View {
        frame(height: AppPresentationMetrics.preferredHeight(
            relativeTo: appHeight,
            maximumHeight: maximumHeight
        ))
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GeometryReader { proxy in
            let isSidebarCollapsed = appState.isSidebarCollapsed
            let sidebarWidth = isSidebarCollapsed
                ? MainWindowMetrics.collapsedSidebarWidth
                : MainWindowMetrics.expandedSidebarWidth
            let contentWidth = proxy.size.width - sidebarWidth

            mainContent(
                isSidebarCollapsed: isSidebarCollapsed,
                usesCompactContent: contentWidth < MainWindowMetrics.compactContentWidth
            )
            .onAppear {
                appState.appWindowWidth = proxy.size.width
                appState.appWindowHeight = proxy.size.height
            }
            .onChange(of: proxy.size.width) { width in
                appState.appWindowWidth = width
            }
            .onChange(of: proxy.size.height) { height in
                appState.appWindowHeight = height
            }
        }
        .background(AppTheme.background)
        .appDismissTextFieldFocusOnTap()
        .animation(.easeOut(duration: 0.24), value: appState.isSidebarCollapsed)
        .sheet(isPresented: $appState.showingSettings) {
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
        .sheet(isPresented: $appState.showingAddDevice) {
            AddDeviceView()
                .environmentObject(appState)
                .environment(\.locale, appState.resolvedLocale)
                .appPresentationWidth(
                    relativeTo: appState.appWindowWidth,
                    idealWidth: AppPresentationMetrics.IdealWidth.sessionEditor
                )
                .appPresentationHeight(relativeTo: appState.appWindowHeight)
        }
        .sheet(isPresented: Binding(
            get: { appState.editingDeviceID != nil },
            set: { if !$0 { appState.editingDeviceID = nil } }
        )) {
            if let deviceID = appState.editingDeviceID,
               let device = appState.devices.first(where: { $0.id == deviceID }) {
                AddDeviceView(editing: device)
                    .environmentObject(appState)
                    .environment(\.locale, appState.resolvedLocale)
                    .appPresentationWidth(
                        relativeTo: appState.appWindowWidth,
                        idealWidth: AppPresentationMetrics.IdealWidth.sessionEditor
                    )
                    .appPresentationHeight(
                        relativeTo: appState.appWindowHeight,
                        maximumHeight: nil
                    )
            }
        }
        .sheet(isPresented: $appState.showingDeviceDiscovery) {
            DeviceDiscoveryView()
                .environmentObject(appState)
                .environment(\.locale, appState.resolvedLocale)
                .appPresentationWidth(
                    relativeTo: appState.appWindowWidth,
                    idealWidth: AppPresentationMetrics.IdealWidth.deviceDiscovery
                )
                .appPresentationHeight(relativeTo: appState.appWindowHeight)
        }
        .sheet(isPresented: $appState.showingGroupManager) {
            GroupManagerView()
                .environmentObject(appState)
                .environment(\.locale, appState.resolvedLocale)
                .appPresentationWidth(relativeTo: appState.appWindowWidth)
                .appPresentationHeight(relativeTo: appState.appWindowHeight)
        }
        .sheet(isPresented: $appState.showingVirtualDevices) {
            VirtualDeviceView()
                .environmentObject(appState)
                .environment(\.locale, appState.resolvedLocale)
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenRemoteOpenVirtualDevices)) { _ in
            appState.showingVirtualDevices = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenRemoteCreateVirtualDevice)) { _ in
            appState.openVirtualDeviceCreator()
        }
        .onAppear {
            NotificationCenter.default.post(name: .screenRemoteRefreshMenuBar, object: nil)
        }
        .onChange(of: appState.appLanguage) { _ in
            NotificationCenter.default.post(name: .screenRemoteRefreshMenuBar, object: nil)
        }
    }

    private func mainContent(
        isSidebarCollapsed: Bool,
        usesCompactContent: Bool
    ) -> some View {
        HStack(spacing: 0) {
            SidebarView(
                isCollapsed: isSidebarCollapsed,
                allowsExpansion: true
            )
            .frame(
                width: isSidebarCollapsed
                    ? MainWindowMetrics.collapsedSidebarWidth
                    : MainWindowMetrics.expandedSidebarWidth
            )

            Divider().opacity(0.55)

            VStack(spacing: 0) {
                TopBar(isCompact: usesCompactContent)
                Divider().opacity(0.55)

                Group {
                    switch appState.selection {
                    case .screens: ScreensView()
                    case .deviceInfo: DeviceInformationView(isCompact: usesCompactContent)
                    case .utilities: DeviceUtilitiesView(isCompact: usesCompactContent)
                    case .files: DeviceFilesView(isCompact: usesCompactContent)
                    case .apps:
                        AppsView(
                            isCompact: usesCompactContent,
                            appManager: appState.deviceApps,
                            sessionManager: appState.screenSessions
                        )
                    case .processes: DeviceProcessesView(isCompact: usesCompactContent)
                    case .portForward: PortForwardView(isCompact: usesCompactContent)
                    case .notifications: NotificationsView(isCompact: usesCompactContent)
                    case .messages: MessagesView(isCompact: usesCompactContent)
                    case .photos: PhotosView(isCompact: usesCompactContent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.background)
        }
        .background(AppTheme.background)
    }
}

private struct TopBar: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(AppSection.allCases) { section in
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { appState.selection = section }
                        } label: {
                            Label(section.titleKey, systemImage: section.icon)
                                .labelStyle(TopBarLabelStyle(isCompact: isCompact))
                                .font(.system(size: 13, weight: appState.selection == section ? .semibold : .regular))
                                .foregroundColor(appState.selection == section ? Color.primary : Color.secondary)
                                .padding(.horizontal, isCompact ? 10 : 13)
                                .padding(.vertical, 8)
                                .appBackground(
                                    Group {
                                    if appState.selection == section {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.primary.opacity(0.075))
                                    }
                                    }
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(section.titleKey)
                    }
                }
            }

            Spacer()

            Button {
                if appState.devices.indices.contains(appState.selectedDevice) {
                    let device = appState.devices[appState.selectedDevice]
                    let session = appState.screenSessions.session(for: device.id)
                    if !session.isConnected && !session.phase.isWorking {
                        appState.connectScreenSession(deviceID: device.id)
                        return
                    }
                }
                if appState.selection == .apps {
                    appState.refreshSelectedDeviceApps()
                }
                NotificationCenter.default.post(name: .screenRemoteRefreshManagement, object: nil)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .appBackground(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(appState.devices.isEmpty)
            .help("topBarRefreshApps")

            Button {
                appState.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .appBackground(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("topBarSettings")
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .frame(height: 54)
        .background(AppTheme.surface.opacity(0.96))
    }
}

private struct TopBarLabelStyle: LabelStyle {
    let isCompact: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            if !isCompact {
                configuration.title
            }
        }
    }
}
