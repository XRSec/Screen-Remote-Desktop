import SwiftUI

struct PageSearchField: View {
    @Binding var searchText: String
    let searchPrompt: LocalizedStringKey
    let expands: Bool

    var body: some View {
        TextField(searchPrompt, text: $searchText)
            .textFieldStyle(.plain)
            .padding(.leading, AppSpacing.md)
            .padding(.trailing, AppSpacing.xl)
            .frame(minWidth: 120, maxWidth: expands ? .infinity : 230, minHeight: 34, maxHeight: 34)
            .background(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous).fill(Color.primary.opacity(0.055)))
            .overlay(
                Group {
                    if searchText.isEmpty {
                        Image(systemName: "magnifyingglass")
                            .accessibilityHidden(true)
                    } else {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("commonClear")
                        .accessibilityLabel(Text("commonClear"))
                    }
                }
                .foregroundColor(.secondary)
                .padding(.trailing, AppSpacing.sm)
                .animation(.easeOut(duration: 0.12), value: searchText.isEmpty),
                alignment: .trailing
            )
    }
}

struct ManagedAppGridItem: View {
    let app: ManagedAndroidApp
    let icon: NSImage?
    let isBusy: Bool
    let isLaunchingApp: Bool
    let openApp: () -> Void
    let launchOnDevice: () -> Void
    let toggleEnabled: () -> Void
    let clearData: () -> Void
    let forceStop: () -> Void
    let showDetails: () -> Void
    let exportAPK: () -> Void
    let uninstall: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                } else {
                    AppIconTile(symbol: "app.fill", color: .appIndigo, size: 48)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                if isBusy || isLaunchingApp {
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .fill(Color.black.opacity(0.42))
                        .frame(width: 48, height: 48)
                    ProgressView().scaleEffect(0.65)
                }
            }
            .animation(.easeOut(duration: 0.18), value: icon != nil)
            Text(app.name)
                .font(AppTypography.caption.weight(.medium))
                .lineLimit(1)
            Text(app.packageName)
                .font(AppTypography.monospacedCaption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.055) : Color.clear)
        )
        .appOverlay(
            Group {
                if !app.isEnabled {
                    Text("appsDisabledAppsFilter")
                        .font(AppTypography.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .padding(AppSpacing.sm)
                }
            },
            alignment: .topTrailing
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: openApp)
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(app.isEnabled ? Text("") : Text("appsDisabledAppsFilter"))
        .accessibilityAction { openApp() }
    }
}
