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
                        .font(AppTypography.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(AppTypography.subheadline.weight(.semibold))
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
            .accessibilityLabel(addHelp)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
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
                    Image(systemName: "chevron.up.chevron.down").font(AppTypography.caption2)
                }
                .font(.caption)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .appMaterialBackground(
                    in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                )
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
                .appMaterialBackground(
                    in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(LocalizedStringKey(help)))
    }
}

struct SidebarToggleButton: View {
    let isCollapsed: Bool
    let action: () -> Void
    @State private var isHovered = false

    private enum Layout {
        static let width: CGFloat = 14
        static let height: CGFloat = 44
        static let cornerRadius: CGFloat = AppRadius.small
        static let iconSize: CGFloat = 9.5
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundColor(isHovered ? .primary : .secondary.opacity(0.85))
                .frame(width: Layout.width, height: Layout.height)
                .background(
                    SidebarToggleHandleShape(radius: Layout.cornerRadius)
                        .fill(AppTheme.sidebar.opacity(isHovered ? 0.95 : 0.75))
                )
                .overlay(
                    SidebarToggleHandleShape(radius: Layout.cornerRadius)
                        .stroke(AppTheme.line.opacity(isHovered ? 1.0 : 0.6), lineWidth: 0.75)
                )
                .contentShape(SidebarToggleHandleShape(radius: Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "sidebarExpandDeviceList" : "sidebarCollapseDeviceList")
        .accessibilityLabel(Text(isCollapsed ? "sidebarExpandDeviceList" : "sidebarCollapseDeviceList"))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
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
    @State private var isHovered = false

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
        if isSessionConnected { return .green }
        return .secondary
    }

    private var isSessionActive: Bool {
        session.isConnected || session.phase.isWorking
    }

    private var sessionActionLocalizationKey: LocalizedStringKey {
        isSessionActive ? "sessionStopAction" : "sessionStartAction"
    }

    private var showsSessionAction: Bool {
        isHovered || isSelected || isSessionActive
    }

    private var showsEditAction: Bool {
        isHovered || isSelected
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if session.phase.isWorking {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.48)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(statusColor.opacity(isSessionConnected || session.phase == .failed ? 1 : 0.62))
                .frame(width: 7, height: 7)
                .frame(width: 10, height: 10)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                statusIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(AppTypography.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(statusText)
                        .font(AppTypography.caption)
                        .foregroundColor(session.phase == .failed ? .red : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .sessionClickGesture(onSingleClick: action, onDoubleClick: onDoubleClick)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }

            Button(action: onToggleSession) {
                Image(systemName: isSessionActive ? "stop.fill" : "play.fill")
                    .font(AppTypography.caption2.weight(.semibold))
                    .foregroundColor(isSessionActive ? .red : AppTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
            }
            .buttonStyle(.plain)
            .help(sessionActionLocalizationKey)
            .accessibilityLabel(Text(sessionActionLocalizationKey))
            .opacity(showsSessionAction ? 1 : 0)
            .allowsHitTesting(showsSessionAction)

            Button(action: onEdit) {
                Image(systemName: "ellipsis")
                    .font(AppTypography.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
            }
            .buttonStyle(.plain)
            .help("sessionEditTitle")
            .accessibilityLabel(Text("sessionEditTitle"))
            .opacity(showsEditAction ? 1 : 0)
            .allowsHitTesting(showsEditAction)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.17)
                        : (isHovered ? Color.primary.opacity(0.045) : Color.clear)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(sessionActionLocalizationKey), onToggleSession)
        .accessibilityAction(named: Text("sessionEditTitle"), onEdit)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct VirtualDeviceRow: View {
    let device: AndroidVirtualDevice
    let isWorking: Bool
    let action: () -> Void
    let onEdit: () -> Void
    @State private var isHovered = false

    private var actionLocalizationKey: LocalizedStringKey {
        device.isRunning ? "virtualDeviceActionStop" : "virtualDeviceActionStart"
    }

    private var showsPrimaryAction: Bool {
        isHovered || device.isRunning || isWorking
    }

    private var showsEditAction: Bool {
        isHovered && !device.isRunning && !isWorking
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isWorking {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.48)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill((device.isRunning ? Color.green : Color.secondary).opacity(device.isRunning ? 1 : 0.62))
                .frame(width: 7, height: 7)
                .frame(width: 10, height: 10)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                statusIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(AppTypography.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(device.target)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }

            Button(action: action) {
                Image(systemName: device.isRunning ? "stop.fill" : "play.fill")
                    .font(AppTypography.caption2.weight(.semibold))
                    .foregroundColor(device.isRunning ? .red : AppTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .help(actionLocalizationKey)
            .accessibilityLabel(Text(actionLocalizationKey))
            .opacity(showsPrimaryAction ? 1 : 0)
            .allowsHitTesting(showsPrimaryAction)

            Button(action: onEdit) {
                Image(systemName: "ellipsis")
                    .font(AppTypography.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.055)))
            }
            .buttonStyle(.plain)
            .disabled(device.isRunning || isWorking)
            .help("virtualDeviceEditTitle")
            .accessibilityLabel(Text("virtualDeviceEditTitle"))
            .opacity(showsEditAction ? 1 : 0)
            .allowsHitTesting(showsEditAction)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.045) : Color.clear)
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(actionLocalizationKey)) {
            if !isWorking { action() }
        }
        .accessibilityAction(named: Text("virtualDeviceEditTitle")) {
            if !device.isRunning && !isWorking { onEdit() }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
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
