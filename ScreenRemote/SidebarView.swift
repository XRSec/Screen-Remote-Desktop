import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Keep layout clear of the titlebar traffic lights while preserving sidebar spacing.
            Color.clear.frame(height: 28)

            HStack {
                Spacer()
                SidebarToggleButton()
            }
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.bottom, 8)

            if appState.isSidebarCollapsed {
                collapsedContent
            } else {
                expandedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.sidebar)
        .clipped()
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("sidebarDevices")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    appState.showingAddDevice = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)

            ScrollView {
                VStack(spacing: 9) {
                    ForEach(appState.visibleDeviceOffsets(), id: \.element.id) { index, device in
                    DeviceRow(device: device, isSelected: appState.selectedDevice == index) {
                        appState.selectDevice(at: index)
                    }
                }
                }
            }
            .padding(.horizontal, 10)

            Divider().padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 12) {
                Text("sidebarQuickActions")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                QuickAction(icon: "rectangle.inset.filled.and.person.filled", title: "sidebarOpenPhoneScreen", color: .blue)
                QuickAction(icon: "arrow.triangle.2.circlepath", title: "sidebarRefreshDevices", color: .appIndigo)
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 8)
            Button {
                appState.showingVirtualDevices = true
            } label: {
                Label("sidebarVirtualDevices", systemImage: "iphone.gen3")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            SidebarUtilityBar()
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
    }

    private var collapsedContent: some View {
        VStack(spacing: 14) {
            ForEach(appState.visibleDeviceOffsets(), id: \.element.id) { index, device in
                Button {
                    appState.selectDevice(at: index)
                } label: {
                    PhoneGlyph(color: device.accent, compact: true)
                        .padding(7)
                        .background(RoundedRectangle(cornerRadius: 12).fill(appState.selectedDevice == index ? Color.primary.opacity(0.09) : .clear))
                }
                .buttonStyle(.plain)
                .help(device.name)
            }
            Spacer()
            Button { appState.showingVirtualDevices = true } label: {
                Image(systemName: "iphone.gen3")
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("sidebarVirtualDevices")
            Button { appState.showingDeviceDiscovery = true } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("deviceDiscoveryTitle")
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SidebarUtilityBar: View {
    @EnvironmentObject private var appState: AppState

    private var selectedGroupName: String {
        switch appState.selectedGroupID {
        case DeviceGroup.allID: String.localizedKey("sidebarAllDevices")
        case DeviceGroup.ungroupedID: String.localizedKey("sidebarUngrouped")
        default: appState.groups.first { $0.id == appState.selectedGroupID }?.name ?? String.localizedKey("sidebarAllDevices")
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Menu {
                Button("sidebarAllDevices") { appState.selectedGroupID = DeviceGroup.allID }
                Button("sidebarUngrouped") { appState.selectedGroupID = DeviceGroup.ungroupedID }
                Divider()
                ForEach(appState.groups) { group in
                    Button(group.name) { appState.selectedGroupID = group.id }
                }
                Divider()
                Button("sidebarManageGroups") { appState.showingGroupManager = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(selectedGroupName).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                }
                .font(.caption)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity)

            UtilityButton(icon: "dot.radiowaves.left.and.right", help: "sidebarMDNSAndPortScan") {
                appState.showingDeviceDiscovery = true
            }

            Menu {
                Button("diagnosticsSDLLogs") { appState.showingSDLLogs = true }
                Button("diagnosticsCodecTest") { appState.showingCodecTest = true }
            } label: {
                Image(systemName: "stethoscope")
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .help("sidebarDiagnostics")
        }
    }
}

private struct UtilityButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct SidebarToggleButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.isSidebarCollapsed.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(appState.isSidebarCollapsed ? "sidebarExpandDeviceList" : "sidebarCollapseDeviceList")
    }
}

private struct DeviceRow: View {
    let device: Device
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PhoneGlyph(color: device.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(device.isConnected
                        ? String(format: String.localizedKey("sidebarDeviceConnected"), device.battery)
                        : (device.primaryConnection?.displayAddress ?? String.localizedKey("sidebarAddressNotConfigured")))
                        .font(.caption)
                        .foregroundColor(device.isConnected ? Color.secondary : Color.orange)
                }

                Spacer(minLength: 4)
                if device.isConnected {
                    Image(systemName: "battery.75percent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Color.primary.opacity(0.085) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PhoneGlyph: View {
    let color: Color
    var compact = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.35), color], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: compact ? 5 : 6, style: .continuous)
                .stroke(.white.opacity(0.65), lineWidth: 1)
                .padding(4)
            Capsule().fill(.white.opacity(0.7)).frame(width: compact ? 8 : 10, height: 2).offset(y: compact ? -12 : -15)
        }
        .frame(width: compact ? 30 : 36, height: compact ? 40 : 48)
    }
}

private struct QuickAction: View {
    let icon: String
    let title: LocalizedStringKey
    let color: Color

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(title).font(.system(size: 13))
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(Color.secondary.opacity(0.65))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
