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
    let searchTerms: [String]
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
                    ProgressView()
                        .scaleEffect(0.65)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.18), value: icon != nil)
            highlightedText(app.name, terms: searchTerms)
                .font(AppTypography.caption.weight(.medium))
                .lineLimit(1)
            highlightedText(app.packageName, terms: searchTerms)
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
        .disabled(isBusy || isLaunchingApp)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(
            isLaunchingApp
                ? Text("appsManageLaunching")
                : (isBusy
                    ? Text("commonLoading")
                    : (app.isEnabled ? Text("appsEnabledAppsFilter") : Text("appsDisabledAppsFilter")))
        )
        .accessibilityAction { openApp() }
        .accessibilityAction(named: Text("appsManageDetails")) { showDetails() }
        .accessibilityAction(named: Text("appsManageLaunchOnDevice")) { launchOnDevice() }
        .accessibilityAction(named: Text(app.isEnabled ? "appsManageDisable" : "appsManageEnable")) {
            toggleEnabled()
        }
        .accessibilityAction(named: Text("appsManageForceStop")) { forceStop() }
        .accessibilityAction(named: Text("appsManageClearData")) { clearData() }
        .accessibilityAction(named: Text("appsManageExportAPK")) { exportAPK() }
        .accessibilityAction(named: Text("appsManageUninstall")) { uninstall() }
    }

    private func highlightedText(_ value: String, terms: [String]) -> Text {
        var segments: [(range: Range<String.Index>, highlighted: Bool)] = []
        var matchedRanges: [Range<String.Index>] = []

        for term in terms where !term.isEmpty {
            var searchStart = value.startIndex
            while searchStart < value.endIndex,
                  let range = value.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<value.endIndex
                  ) {
                if !matchedRanges.contains(where: { $0.overlaps(range) }) {
                    matchedRanges.append(range)
                }
                searchStart = range.upperBound
            }
        }

        var cursor = value.startIndex
        for range in matchedRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if cursor < range.lowerBound {
                segments.append((cursor..<range.lowerBound, false))
            }
            segments.append((range, true))
            cursor = range.upperBound
        }
        if cursor < value.endIndex {
            segments.append((cursor..<value.endIndex, false))
        }

        return segments.reduce(Text("")) { result, segment in
            let text = Text(String(value[segment.range]))
            return result + (segment.highlighted ? text.foregroundColor(AppTheme.accent).bold() : text)
        }
    }
}
