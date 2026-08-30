import AppKit
import AudioToolbox
import SwiftUI
import VideoToolbox

struct BackupConnectionEditor: View {
    @Binding var endpoint: ConnectionDraft
    let onRemove: () -> Void
    let onDiscover: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("addDeviceConnectionType", selection: $endpoint.transport) {
                    ForEach(DeviceTransport.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("addDeviceRemoveAddress")
            }

            switch endpoint.transport {
            case .tcp:
                HStack(spacing: 8) {
                    TextField("addDeviceIPAddress", text: $endpoint.host).textFieldStyle(.roundedBorder)
                    TextField("addDevicePort", text: $endpoint.port).textFieldStyle(.roundedBorder).frame(width: 100)
                }
            case .usb:
                TextField("addDeviceUSBSerial", text: $endpoint.serial).textFieldStyle(.roundedBorder)
            case .mdns:
                TextField("addDeviceMDNSServiceOrSerial", text: $endpoint.host).textFieldStyle(.roundedBorder)
            }

            ConnectionDiscoveryRow(transport: endpoint.transport, action: onDiscover)
        }
        .padding(14)
        .background(Color.primary.opacity(0.025))
    }
}

struct ConnectionDiscoveryRow: View {
    let transport: DeviceTransport
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: transport == .usb ? "cable.connector" : "dot.radiowaves.left.and.right")
                    .foregroundColor(AppTheme.accent)
                Text(String.localizedKey(transport == .usb ? "sessionSelectUSBDevice" : "sessionDiscoverDevices"))
                    .font(AppTypography.body.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ConnectionDiscoveryPicker: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    let transport: DeviceTransport
    let currentAddress: String
    let onSelect: (DiscoveredADBDevice) -> Void

    @State private var devices: [DiscoveredADBDevice] = []
    @State private var isRefreshing = false
    @State private var statusText = String.localizedKey("deviceDiscoveryWaiting")
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String.localizedKey(transport == .usb ? "sessionSelectUSBDevice" : "sessionDiscoverDevices"))
                        .font(.headline)
                    Text(String(format: String.localizedKey("sessionDiscoveryPickerSubtitle %@"), transport.rawValue))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { refresh() } label: {
                    Label(isRefreshing ? "deviceDiscoveryRefreshing" : "commonRefresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)
                Button("commonClose") { presentationMode.wrappedValue.dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: String.localizedKey("deviceDiscoveryDeviceCount"), "\(devices.count)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if devices.isEmpty && !isRefreshing {
                            ContentUnavailableViewCompat(
                                icon: transport == .usb ? "cable.connector" : "dot.radiowaves.left.and.right",
                                title: "deviceDiscoveryEmptyTitle",
                                detail: "deviceDiscoveryEmptyDetail"
                            )
                            .frame(height: 230)
                        }

                        ForEach(devices) { device in
                            Button {
                                onSelect(device)
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    AppIconTile(
                                        symbol: transport == .usb ? "cable.connector" : "wifi",
                                        color: transport == .mdns ? .appCyan : .blue,
                                        size: 34
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.primary)
                                        Text(device.address)
                                            .font(.appCaptionMonospaced)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(device.state)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if device.address.caseInsensitiveCompare(currentAddress) == .orderedSame {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppTheme.accent)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .appCard(radius: 10)
                        }
                    }
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .onAppear { refresh() }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorText = nil
        statusText = String.localizedKey("deviceDiscoveryReadingDevices")
        let adbPath = appState.adbPath

        Task {
            let deviceResult = await ADBCommandRunner.run(
                executable: adbPath,
                arguments: ["devices", "-l"]
            )
            await MainActor.run {
                statusText = String.localizedKey("deviceDiscoveryReadingMDNS")
            }
            let mdnsResult = await ADBCommandRunner.run(
                executable: adbPath,
                arguments: ["mdns", "services"]
            )
            let discovered = (parseADBDevices(deviceResult.output) + parseMDNSServices(mdnsResult.output))
                .filter { $0.transport == transport }
            var seen = Set<String>()
            let unique = discovered.filter {
                seen.insert($0.address.lowercased()).inserted
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            await MainActor.run {
                devices = unique
                isRefreshing = false
                statusText = String.localizedKey("deviceDiscoveryComplete")
                let errors = [deviceResult, mdnsResult]
                    .filter { $0.exitCode != 0 }
                    .map { $0.error.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                errorText = errors.isEmpty ? nil : errors.joined(separator: " · ")
                appState.appendSDLLog(
                    "Session address discovery complete: transport=\(transport.rawValue), devices=\(unique.count)"
                )
            }
        }
    }
}
