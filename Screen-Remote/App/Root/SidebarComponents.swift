import SwiftUI

struct SidebarSectionHeader: View {
    let title: LocalizedStringKey
    let isExpanded: Bool
    let addHelp: Text
    let onToggle: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.title2.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help(addHelp)
        }
        .padding(.horizontal, 18)
    }
}

struct SidebarUtilityBar: View {
    @EnvironmentObject private var appState: AppState

    private var selectedGroupName: String {
        switch appState.selectedGroupID {
        case DeviceGroup.allID: String.localizedKey("sidebarAllDevices")
        default: appState.groups.first { $0.id == appState.selectedGroupID }?.name ?? String.localizedKey("sidebarAllDevices")
        }
    }

    private var selectedGroupSymbol: String {
        switch appState.selectedGroupID {
        case DeviceGroup.allID: "house.fill"
        default: appState.groups.first { $0.id == appState.selectedGroupID }?.symbol ?? "house.fill"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Menu {
                Button("sidebarAllDevices") { appState.selectedGroupID = DeviceGroup.allID }
                Divider()
                ForEach(appState.flattenedGroups()) { entry in
                    Button {
                        appState.selectedGroupID = entry.group.id
                    } label: {
                        Text(String(repeating: "  ", count: entry.depth) + "↳ " + entry.group.name)
                    }
                }
                Divider()
                Button("sidebarManageGroups") { appState.showingGroupManager = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedGroupSymbol)
                    Text(selectedGroupName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 68)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                }
                .font(.caption)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 120, alignment: .leading)

            UtilityButton(icon: "dot.radiowaves.left.and.right", help: "sidebarMDNSAndPortScan") {
                appState.showingDeviceDiscovery = true
            }

            UtilityButton(icon: "text.alignleft", help: "diagnosticsSDLLogs") {
                appState.openSDLLogsWindow()
            }
        }
    }
}

struct UtilityButton: View {
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

struct SidebarToggleButton: View {
    let isCollapsed: Bool
    let action: () -> Void

    private enum Layout {
        static let width: CGFloat = 20
        static let height: CGFloat = 72
        static let cornerRadius: CGFloat = 8
        static let iconSize: CGFloat = 11
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                .font(.system(size: Layout.iconSize, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: Layout.width, height: Layout.height)
                .background(
                    SidebarToggleHandleShape(radius: Layout.cornerRadius)
                        .fill(AppTheme.sidebar)
                )
                .overlay(
                    SidebarToggleHandleShape(radius: Layout.cornerRadius)
                        .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                )
                .contentShape(SidebarToggleHandleShape(radius: Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "sidebarExpandDeviceList" : "sidebarCollapseDeviceList")
    }
}

struct SidebarToggleHandleShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let cornerRadius = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

struct DeviceRow: View {
    let device: Device
    let isSelected: Bool
    @ObservedObject var sessionManager: ScreenSessionManager
    let action: () -> Void
    let onDoubleClick: () -> Void
    let onToggleSession: () -> Void
    let onEdit: () -> Void

    private var session: ScreenSessionSnapshot {
        sessionManager.session(for: device.id)
    }

    private var isSessionConnected: Bool {
        session.phase.supportsBatteryInformation
    }

    private var statusText: String {
        if session.phase == .failed {
            return String.localizedKey("screenSessionFailed")
        }
        if isSessionConnected {
            guard let batteryLevel = session.batteryLevel else {
                return String.localizedKey("sidebarDeviceConnected")
            }
            return String(
                format: String.localizedKey("sidebarDeviceConnectedBattery %@"),
                String(batteryLevel)
            )
        }
        return String.localizedKey("sidebarDeviceNotConnected")
    }

    private var statusColor: Color {
        if session.phase == .failed { return .red }
        return isSessionConnected ? .secondary : .orange
    }

    private var isSessionActive: Bool {
        session.isConnected || session.phase.isWorking
    }

    private var sessionActionLocalizationKey: LocalizedStringKey {
        isSessionActive ? "sessionStopAction" : "sessionStartAction"
    }

    var body: some View {
        HStack(spacing: 2) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)
                if session.phase.isWorking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.55)
                        .frame(width: 16, height: 16)
                } else if session.phase == .failed {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                } else if isSessionConnected {
                    Image(systemName: "battery.75percent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .sessionClickGesture(onSingleClick: action, onDoubleClick: onDoubleClick)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }

            Button(action: onToggleSession) {
                Image(systemName: isSessionActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSessionActive ? .red : AppTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .help(sessionActionLocalizationKey)
            .accessibilityLabel(Text(sessionActionLocalizationKey))

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? AppTheme.accent : .secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isSelected ? 0.09 : 0.055))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .help("sessionEditTitle")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(device.accent.opacity(isSelected ? 0.20 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(device.accent.opacity(isSelected ? 0.45 : 0.18), lineWidth: 0.5)
        )
    }
}

struct VirtualDeviceRow: View {
    let device: AndroidVirtualDevice
    let isWorking: Bool
    let action: () -> Void
    let onEdit: () -> Void

    private var actionLocalizationKey: LocalizedStringKey {
        device.isRunning ? "virtualDeviceActionStop" : "virtualDeviceActionStart"
    }

    var body: some View {
        HStack(spacing: 2) {
            HStack(spacing: 12) {
                PhoneGlyph(color: device.isRunning ? .green : .gray)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(device.target)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }

            Button(action: action) {
                Image(systemName: device.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(device.isRunning ? .red : AppTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .help(actionLocalizationKey)
            .accessibilityLabel(Text(actionLocalizationKey))

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(device.isRunning || isWorking)
            .help("virtualDeviceEditTitle")
            .accessibilityLabel(Text("virtualDeviceEditTitle"))
        }
        .padding(10)
    }
}

struct SessionClickGestureModifier: ViewModifier {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    func body(content: Content) -> some View {
        content.gesture(
            TapGesture(count: 2)
                .onEnded(onDoubleClick)
                .exclusively(before: TapGesture(count: 1).onEnded(onSingleClick))
        )
    }
}

extension View {
    func sessionClickGesture(
        onSingleClick: @escaping () -> Void,
        onDoubleClick: @escaping () -> Void
    ) -> some View {
        modifier(SessionClickGestureModifier(
            onSingleClick: onSingleClick,
            onDoubleClick: onDoubleClick
        ))
    }
}

struct PhoneGlyph: View {
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
