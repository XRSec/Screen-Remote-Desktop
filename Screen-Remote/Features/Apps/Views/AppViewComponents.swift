import SwiftUI

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

struct ManagedAppGridItem: View {
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

struct StatCard: View {
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

struct RecentAppCard: View {
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

struct AppGridItem: View {
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
