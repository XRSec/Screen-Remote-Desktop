import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: appState.isSidebarCollapsed ? 78 : 260)

            Divider().opacity(0.55)

            VStack(spacing: 0) {
                TopBar()
                Divider().opacity(0.55)

                Group {
                    switch appState.selection {
                    case .apps: AppsView()
                    case .notifications: NotificationsView()
                    case .messages: MessagesView()
                    case .photos: PhotosView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.background)
        }
        .background(AppTheme.background)
        .appBackground(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { appState.appWindowHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { height in
                        appState.appWindowHeight = height
                    }
            }
        )
        .animation(.snappy(duration: 0.24), value: appState.isSidebarCollapsed)
        .sheet(isPresented: $appState.showingSettings) {
            SettingsView()
                .environmentObject(appState)
                .frame(
                    width: 620,
                    height: SettingsWindowMetrics.preferredHeight(relativeTo: appState.appWindowHeight)
                )
        }
        .sheet(isPresented: $appState.showingAddDevice) {
            AddDeviceView()
                .environmentObject(appState)
                .frame(width: 820, height: 720)
        }
        .sheet(isPresented: $appState.showingDeviceDiscovery) {
            DeviceDiscoveryView()
                .environmentObject(appState)
                .frame(width: 660, height: 560)
        }
        .sheet(isPresented: $appState.showingSDLLogs) {
            SDLLogView()
                .environmentObject(appState)
                .frame(width: 760, height: 500)
        }
        .sheet(isPresented: $appState.showingCodecTest) {
            CodecTestView()
                .frame(width: 620, height: 500)
        }
        .sheet(isPresented: $appState.showingGroupManager) {
            GroupManagerView()
                .environmentObject(appState)
                .frame(width: 460, height: 420)
        }
        .sheet(isPresented: $appState.showingVirtualDevices) {
            VirtualDeviceView()
                .environmentObject(appState)
        }
    }
}

private struct TopBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { appState.selection = section }
                    } label: {
                        Label(section.rawValue, systemImage: section.icon)
                            .font(.system(size: 13, weight: appState.selection == section ? .semibold : .regular))
                            .foregroundColor(appState.selection == section ? Color.primary : Color.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .appBackground(
                                Group {
                                if appState.selection == section {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.075))
                                }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

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
