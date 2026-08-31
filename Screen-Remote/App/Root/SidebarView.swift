import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    let isCollapsed: Bool
    let allowsExpansion: Bool
    @StateObject private var virtualDeviceViewModel = VirtualDeviceViewModel()
    @State private var sessionsExpanded = true
    @State private var virtualDevicesExpanded = false
    @State private var sessionPendingDeletion: Device?
    @State private var virtualDevicePendingEdit: AndroidVirtualDevice?

    private enum Layout {
        static let contentTopPadding: CGFloat = 36
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Keep layout clear of the titlebar traffic lights while preserving sidebar spacing.
                Color.clear.frame(height: Layout.contentTopPadding)

                if isCollapsed {
                    collapsedContent
                } else {
                    expandedContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if allowsExpansion {
                SidebarToggleButton(isCollapsed: isCollapsed) {
                    appState.isSidebarCollapsed.toggle()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.sidebar.opacity(0.88))
        .appMaterialBackground(in: Rectangle())
        .clipped()
        .alert(item: $sessionPendingDeletion) { device in
            Alert(
                title: Text("sessionDeleteConfirmationTitle"),
                message: Text(String(
                    format: String.localizedKey("sessionDeleteConfirmationMessage"),
                    device.name
                )),
                primaryButton: .destructive(Text("sessionDeleteAction")) {
                    appState.removeDevice(id: device.id)
                },
                secondaryButton: .cancel(Text("commonCancel"))
            )
        }
        .sheet(item: $virtualDevicePendingEdit) { device in
            VirtualDeviceEditorView(
                viewModel: virtualDeviceViewModel,
                configuration: virtualDeviceConfiguration,
                device: device,
                initialOptions: virtualDeviceViewModel.options(
                    for: device,
                    configuration: virtualDeviceConfiguration
                )
            )
            .environment(\.locale, appState.resolvedLocale)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sessionsSection
                    virtualDevicesSection
                }
                .padding(.bottom, AppSpacing.md)
            }

            SidebarUtilityBar()
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, 14)
        }
        .onAppear {
            if virtualDevicesExpanded {
                virtualDeviceViewModel.refreshDevices(virtualDeviceConfiguration)
            }
        }
        .onChange(of: appState.showingVirtualDevices) { showing in
            if !showing && virtualDevicesExpanded {
                virtualDeviceViewModel.refreshDevices(virtualDeviceConfiguration)
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SidebarSectionHeader(
                title: "sidebarSessions",
                isExpanded: sessionsExpanded,
                addHelp: Text("addDeviceTitle"),
                onToggle: {
                    withAnimation(.easeOut(duration: 0.16)) {
                        sessionsExpanded.toggle()
                    }
                },
                onAdd: { appState.showingAddDevice = true }
            )

            if sessionsExpanded {
                LazyVStack(spacing: AppSpacing.sm) {
                    if appState.visibleDeviceOffsets().isEmpty {
                        Text("sidebarNoSessions")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    } else {
                        ForEach(appState.visibleDeviceOffsets(), id: \.element.id) { index, device in
                            DeviceRow(
                                device: device,
                                isSelected: appState.selectedDevice == index,
                                sessionManager: appState.screenSessions,
                                action: { appState.selectDevice(at: index) },
                                onDoubleClick: {
                                    appState.selectDevice(at: index)
                                    appState.startScreenSession(deviceID: device.id)
                                },
                                onToggleSession: {
                                    let snapshot = appState.screenSessions.session(for: device.id)
                                    if snapshot.isConnected || snapshot.phase.isWorking {
                                        appState.stopScreenSession(deviceID: device.id)
                                    } else {
                                        appState.connectScreenSession(deviceID: device.id)
                                    }
                                },
                                onEdit: { appState.editingDeviceID = device.id }
                            )
                            .contextMenu {
                                let snapshot = appState.screenSessions.session(for: device.id)
                                if snapshot.isConnected || snapshot.phase.isWorking {
                                    Button("sessionStopAction") {
                                        appState.stopScreenSession(deviceID: device.id)
                                    }
                                } else {
                                    Button("sessionStartAction") {
                                        appState.connectScreenSession(deviceID: device.id)
                                    }
                                }
                                Divider()
                                Button("sessionEditTitle") {
                                    appState.editingDeviceID = device.id
                                }
                                Divider()
                                Button("sessionDeleteTitle") {
                                    sessionPendingDeletion = device
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private var virtualDevicesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SidebarSectionHeader(
                title: "sidebarVirtualDevices",
                isExpanded: virtualDevicesExpanded,
                addHelp: Text("virtualDeviceCreateAction"),
                onToggle: {
                    withAnimation(.easeOut(duration: 0.16)) {
                        virtualDevicesExpanded.toggle()
                    }
                    if virtualDevicesExpanded {
                        virtualDeviceViewModel.refreshDevices(virtualDeviceConfiguration)
                    }
                },
                onAdd: { appState.openVirtualDeviceCreator() }
            )

            if virtualDevicesExpanded {
                VStack(spacing: AppSpacing.sm) {
                    if virtualDeviceViewModel.isWorking && virtualDeviceViewModel.devices.isEmpty {
                        HStack(spacing: 7) {
                            ProgressView().scaleEffect(0.65)
                            Text("virtualDeviceStatusReadingSDK")
                                .font(AppTypography.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    } else if virtualDeviceViewModel.devices.isEmpty {
                        Text("virtualDeviceNoDevicesSidebar")
                            .font(AppTypography.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    } else {
                        ForEach(virtualDeviceViewModel.devices) { device in
                            VirtualDeviceRow(
                                device: device,
                                isWorking: virtualDeviceViewModel.isWorking,
                                action: {
                                    virtualDeviceViewModel.toggle(
                                        device,
                                        configuration: virtualDeviceConfiguration
                                    )
                                },
                                onEdit: { editVirtualDevice(device) }
                            )
                            .contextMenu {
                                Button("virtualDeviceEditTitle") {
                                    editVirtualDevice(device)
                                }
                                .disabled(device.isRunning || virtualDeviceViewModel.isWorking)
                            }
                        }
                    }

                    Button {
                        appState.showingVirtualDevices = true
                    } label: {
                        HStack {
                            Text("virtualDeviceManageAction")
                            Spacer()
                            Image(systemName: "chevron.right").font(AppTypography.caption2)
                        }
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private var virtualDeviceConfiguration: VirtualDeviceConfiguration {
        VirtualDeviceConfiguration(
            sdkRoot: appState.androidSDKRoot,
            androidCLIPath: appState.androidCLIPath,
            toolsPath: appState.commandLineToolsPath,
            emulatorPath: appState.emulatorPath,
            skinsPath: appState.skinsPath,
            avdHome: appState.avdHome
        )
    }

    private func editVirtualDevice(_ device: AndroidVirtualDevice) {
        guard !device.isRunning, !virtualDeviceViewModel.isWorking else { return }
        virtualDeviceViewModel.prepareEditorResources(virtualDeviceConfiguration)
        virtualDevicePendingEdit = device
    }

    private var collapsedContent: some View {
        VStack(spacing: 14) {
            ForEach(appState.visibleDeviceOffsets(), id: \.element.id) { index, device in
                collapsedDeviceGlyph(index: index, device: device)
            }
            Spacer()
            Button { appState.showingVirtualDevices = true } label: {
                Image(systemName: "iphone.gen3")
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("sidebarVirtualDevices")
            .accessibilityLabel(Text("sidebarVirtualDevices"))
            Button { appState.showingDeviceDiscovery = true } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("deviceDiscoveryTitle")
            .accessibilityLabel(Text("deviceDiscoveryTitle"))
            Button { appState.openSDLLogsWindow() } label: {
                Image(systemName: "text.alignleft")
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("diagnosticsSDLLogs")
            .accessibilityLabel(Text("diagnosticsSDLLogs"))
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private func collapsedDeviceGlyph(index: Int, device: Device) -> some View {
        let session = appState.screenSessions.session(for: device.id)
        return PhoneGlyph(color: device.accent, compact: true)
            .padding(7)
            .overlay(
                CollapsedSessionStatusIndicator(session: session)
                    .padding(AppSpacing.xs),
                alignment: .bottomTrailing
            )
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(appState.selectedDevice == index ? Color.primary.opacity(0.09) : .clear))
            .contentShape(Rectangle())
            .sessionClickGesture(
                onSingleClick: { appState.selectDevice(at: index) },
                onDoubleClick: {
                    appState.selectDevice(at: index)
                    appState.startScreenSession(deviceID: device.id)
                }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(device.name))
            .accessibilityValue(Text(collapsedSessionStatusText(session)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { appState.selectDevice(at: index) }
            .accessibilityAction(named: Text(collapsedSessionActionKey(session))) {
                if session.isConnected || session.phase.isWorking {
                    appState.stopScreenSession(deviceID: device.id)
                } else {
                    appState.connectScreenSession(deviceID: device.id)
                }
            }
            .help(device.name)
            .contextMenu {
                Button("sessionEditTitle") {
                    appState.editingDeviceID = device.id
                }
                Divider()
                Button("sessionDeleteTitle") {
                    sessionPendingDeletion = device
                }
            }
    }

    private func collapsedSessionStatusText(_ session: ScreenSessionSnapshot) -> String {
        if session.phase.isWorking {
            return String.localizedKey(session.phase.localizationKey)
        }
        if session.phase == .failed {
            return String.localizedKey("screenSessionFailed")
        }
        if session.phase.supportsBatteryInformation {
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

    private func collapsedSessionActionKey(_ session: ScreenSessionSnapshot) -> LocalizedStringKey {
        session.isConnected || session.phase.isWorking ? "sessionStopAction" : "sessionStartAction"
    }
}

private struct CollapsedSessionStatusIndicator: View {
    let session: ScreenSessionSnapshot

    var body: some View {
        Group {
            if session.phase.isWorking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.45)
            } else {
                Circle()
                    .fill(statusColor)
            }
        }
        .frame(width: 10, height: 10)
        .padding(2)
        .background(Circle().fill(AppTheme.sidebar))
        .accessibilityHidden(true)
    }

    private var statusColor: Color {
        if session.phase == .failed { return Color.red }
        if session.phase.supportsBatteryInformation { return Color.green }
        return Color.secondary
    }
}
