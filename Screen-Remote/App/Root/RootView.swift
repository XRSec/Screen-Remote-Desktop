import AppKit
import SwiftUI

enum MainWindowMetrics {
    static let minimumWidth: CGFloat = 520
    static let preferredWidth: CGFloat = 1000
    static let minimumHeight: CGFloat = 600
    static let preferredHeight: CGFloat = 700
    static let compactContentWidth: CGFloat = 620
    static let compactNavigationWidth: CGFloat = 1060
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
                usesCompactContent: contentWidth < MainWindowMetrics.compactContentWidth,
                usesCompactNavigation: contentWidth < MainWindowMetrics.compactNavigationWidth
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
        usesCompactContent: Bool,
        usesCompactNavigation: Bool
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
                TopBar(isCompact: usesCompactNavigation)
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
                HStack(spacing: AppSpacing.xs) {
                    ForEach(AppSection.allCases) { section in
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { appState.selection = section }
                        } label: {
                            Label(section.titleKey, systemImage: section.icon)
                                .labelStyle(TopBarLabelStyle(
                                    showsTitle: !isCompact || appState.selection == section
                                ))
                                .font(appState.selection == section ? AppTypography.subheadline : AppTypography.body)
                                .foregroundColor(appState.selection == section ? Color.primary : Color.secondary)
                                .padding(.horizontal, isCompact ? 9 : 11)
                                .padding(.vertical, 7)
                                .appBackground(
                                    Group {
                                    if appState.selection == section {
                                        RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                                            .fill(Color.primary.opacity(0.075))
                                    }
                                    }
                                )
                                .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(section.titleKey)
                        .accessibilityLabel(Text(section.titleKey))
                        .accessibilityAddTraits(
                            appState.selection == section ? .isSelected : []
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("topBarWorkspaces"))
            }

            Spacer()

            let isSelectedDeviceConnected = appState.devices.indices.contains(appState.selectedDevice)
                && appState.screenSessions.session(for: appState.devices[appState.selectedDevice].id).isConnected
            let isRefreshEnabled = !appState.devices.isEmpty && (appState.selection == .screens || isSelectedDeviceConnected)
            let refreshLabelKey: LocalizedStringKey = appState.selection == .apps
                ? "topBarRefreshApps"
                : "commonRefresh"
            let refreshHelpKey: LocalizedStringKey = isRefreshEnabled
                ? refreshLabelKey
                : (appState.devices.isEmpty ? "sidebarNoSessions" : "managementNeedsConnection")

            Button {
                if appState.selection == .apps {
                    appState.refreshSelectedDeviceApps()
                }
                NotificationCenter.default.post(name: .screenRemoteRefreshManagement, object: nil)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(AppTypography.subheadline)
                    .foregroundColor(isRefreshEnabled ? .primary : .secondary.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .appBackground(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isRefreshEnabled)
            .help(refreshHelpKey)
            .accessibilityLabel(Text(refreshLabelKey))
            .accessibilityHint(isRefreshEnabled ? Text("") : Text(refreshHelpKey))

            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(AppTypography.subheadline)
                    .frame(width: 30, height: 30)
                    .appBackground(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("topBarSettings")
            .accessibilityLabel(Text("topBarSettings"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .frame(height: 48)
        .background(AppTheme.surface.opacity(0.96))
    }

    private func openSettingsWindow() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for rootItem in mainMenu.items {
            guard let settingsItem = rootItem.submenu?.items.first(where: {
                $0.keyEquivalent == ","
            }), let action = settingsItem.action else {
                continue
            }
            NSApp.sendAction(action, to: settingsItem.target, from: settingsItem)
            return
        }
    }
}

private struct TopBarLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            if showsTitle {
                configuration.title
            }
        }
    }
}
