import SwiftUI
import VideoToolbox
import CoreMedia

struct SDLLogView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @State private var searchText = ""

    private var visibleLogs: [String] {
        searchText.isEmpty ? appState.sdlLogs : appState.sdlLogs.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("diagnosticsSDLLogs").font(.title2.bold())
                    Text("diagnosticsSDLLogsSubtitle").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                TextField("diagnosticsFilterLogs", text: $searchText).textFieldStyle(.roundedBorder).frame(width: 190)
                Button("diagnosticsClear") { appState.sdlLogs.removeAll() }.disabled(appState.sdlLogs.isEmpty)
                Button("commonClose") { presentationMode.wrappedValue.dismiss() }
            }
            .padding(18)
            Divider()

            if visibleLogs.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 34)).foregroundColor(Color.secondary.opacity(0.65))
                    Text("diagnosticsNoSDLLogs").font(.headline)
                    Text("diagnosticsNoSDLLogsDetail")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(visibleLogs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .appTextSelectionEnabled()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(16)
                }
                .background(Color.black.opacity(0.84))
                .foregroundColor(Color.white.opacity(0.9))
            }
        }
        .background(AppTheme.background)
    }
}

struct CodecTestView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var hasRun = false

    private var codecs: [CodecTestItem] {
        [
            CodecTestItem(name: "H.264", kind: String.localizedKey("diagnosticsVideoDecoding"), status: hasRun ? hardwareStatus(kCMVideoCodecType_H264) : .waiting),
            CodecTestItem(name: "HEVC", kind: String.localizedKey("diagnosticsVideoDecoding"), status: hasRun ? hardwareStatus(kCMVideoCodecType_HEVC) : .waiting),
            CodecTestItem(name: "AAC / ALAC", kind: String.localizedKey("diagnosticsAudioDecoding"), status: hasRun ? .available : .waiting),
            CodecTestItem(name: String.localizedKey("diagnosticsAndroidVideoEncoder"), kind: String.localizedKey("diagnosticsRemoteEncoding"), status: .needsDevice),
            CodecTestItem(name: String.localizedKey("diagnosticsAndroidAudioEncoder"), kind: String.localizedKey("diagnosticsRemoteEncoding"), status: .needsDevice)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("diagnosticsCodecTest").font(.title2.bold())
                    Text("diagnosticsCodecTestSubtitle").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("diagnosticsRunLocalTest") { hasRun = true }
                Button("commonClose") { presentationMode.wrappedValue.dismiss() }
            }
            .padding(20)
            Divider()

            VStack(spacing: 10) {
                ForEach(codecs) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.kind == String.localizedKey("diagnosticsVideoDecoding") ? "film" : (item.kind == String.localizedKey("diagnosticsAudioDecoding") ? "waveform" : "iphone"))
                            .foregroundColor(AppTheme.accent)
                            .frame(width: 34, height: 34)
                            .appBackground(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Text(item.kind).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Label(item.status.title, systemImage: item.status.icon)
                            .font(.caption.weight(.medium))
                            .foregroundColor(item.status.color)
                    }
                    .padding(13)
                    .appCard(radius: 10)
                }

                Text("diagnosticsCodecTestDetail")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .appBackground(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            }
            .padding(20)
            Spacer()
        }
        .background(AppTheme.background)
    }

    private func hardwareStatus(_ codec: CMVideoCodecType) -> CodecTestStatus {
        VTIsHardwareDecodeSupported(codec) ? .available : .softwareOnly
    }
}

private struct CodecTestItem: Identifiable {
    let id = UUID()
    let name: String
    let kind: String
    let status: CodecTestStatus
}

private enum CodecTestStatus {
    case waiting, available, softwareOnly, needsDevice

    var title: String {
        switch self {
        case .waiting: String.localizedKey("diagnosticsStatusWaiting")
        case .available: String.localizedKey("settingsStatusReady")
        case .softwareOnly: String.localizedKey("diagnosticsStatusSoftwareOnly")
        case .needsDevice: String.localizedKey("diagnosticsStatusNeedsDevice")
        }
    }

    var icon: String {
        switch self {
        case .waiting: "circle.dashed"
        case .available: "checkmark.circle.fill"
        case .softwareOnly: "exclamationmark.circle.fill"
        case .needsDevice: "cable.connector"
        }
    }

    var color: Color {
        switch self {
        case .waiting: .secondary
        case .available: .green
        case .softwareOnly: .orange
        case .needsDevice: .blue
        }
    }
}

struct GroupManagerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.presentationMode) private var presentationMode
    @State private var newGroupName = ""
    @State private var parentID = DeviceGroup.allID

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("diagnosticsDeviceGroups").font(.title2.bold())
                    Text("diagnosticsDeviceGroupsSubtitle").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
            }
            .padding(20)
            Divider()

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("diagnosticsNewGroupName", text: $newGroupName).textFieldStyle(.roundedBorder)
                    Button("commonAdd") {
                        appState.addGroup(named: newGroupName, parentID: parentID)
                        newGroupName = ""
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Text("groupParent").font(.caption).foregroundColor(.secondary)
                    Picker("groupParent", selection: $parentID) {
                        Text("sidebarAllDevices").tag(DeviceGroup.allID)
                        ForEach(appState.flattenedGroups()) { entry in
                            Text(String(repeating: "  ", count: entry.depth) + "↳ " + entry.group.name)
                                .tag(entry.group.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)

            List {
                HStack {
                    Image(systemName: "house.fill").foregroundColor(AppTheme.accent)
                    Text("sidebarAllDevices").fontWeight(.semibold)
                    Spacer()
                    Text(String(format: String.localizedKey("diagnosticsDeviceCount"), appState.devices.count))
                        .font(.caption).foregroundColor(.secondary)
                }

                OutlineGroup(appState.groupTree(), children: \.children) { node in
                    groupRow(node.group)
                }
            }
            .listStyle(.inset)
        }
        .background(AppTheme.background)
    }

    private func groupRow(_ group: DeviceGroup) -> some View {
        HStack {
            Image(systemName: group.symbol).foregroundColor(AppTheme.accent)
            Text(group.name)
            Spacer()
            Text(String(
                format: String.localizedKey("diagnosticsDeviceCount"),
                appState.devices.filter { $0.groupIDs.contains(group.id) }.count
            ))
            .font(.caption).foregroundColor(.secondary)
            Button {
                parentID = group.id
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .help("groupAddChild")
            Button {
                appState.removeGroup(id: group.id)
                if parentID == group.id || !appState.groups.contains(where: { $0.id == parentID }) {
                    parentID = DeviceGroup.allID
                }
            } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("groupDeleteSubtree")
        }
    }
}
