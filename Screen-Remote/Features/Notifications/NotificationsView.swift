import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var searchText = ""

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var notificationsCountText: String {
        let totalCount = appState.notifications.count
        guard !normalizedSearchQuery.isEmpty else {
            if totalCount == 1 {
                return String.localizedKey("notificationsCountOne")
            }
            return String(format: String.localizedKey("notificationsCount"), totalCount)
        }
        let matchCount = filteredNotifications.count
        if matchCount == 1 {
            return String(
                format: String.localizedKey("notificationsFilteredCountOne"),
                totalCount
            )
        }
        return String(
            format: String.localizedKey("notificationsFilteredCount"),
            matchCount,
            totalCount
        )
    }

    private var filteredNotifications: [PhoneNotification] {
        guard !normalizedSearchQuery.isEmpty else { return appState.notifications }
        return appState.notifications.filter { notification in
            notification.app.localizedCaseInsensitiveContains(normalizedSearchQuery)
                || notification.title.localizedCaseInsensitiveContains(normalizedSearchQuery)
                || notification.body.localizedCaseInsensitiveContains(normalizedSearchQuery)
        }
    }

    var body: some View {
        ScrollView {
            if appState.notifications.isEmpty {
                ContentUnavailableViewCompat(
                    icon: "bell.slash",
                    title: "notificationsSyncUnavailableTitle",
                    detail: "notificationsSyncUnavailableDetail"
                )
                .padding(isCompact ? AppSpacing.lg : AppSpacing.xxl)
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    PageSearchField(
                        searchText: $searchText,
                        searchPrompt: "notificationsSearchPrompt",
                        expands: true
                    )

                    HStack {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "bell.badge.fill")
                                .accessibilityHidden(true)
                            Text(notificationsCountText)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppTheme.accent)
                        Spacer()
                        Button("notificationsClearAll") {
                            appState.notifications.removeAll()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }

                    if filteredNotifications.isEmpty {
                        ContentUnavailableViewCompat(
                            icon: "magnifyingglass",
                            title: "notificationsSearchNoResults",
                            detail: "notificationsSearchPrompt",
                            actionTitle: "commonClear",
                            action: { searchText = "" }
                        )
                        .padding(AppSpacing.lg)
                    } else {
                        VStack(spacing: AppSpacing.md) {
                            ForEach(filteredNotifications) { notification in
                                NotificationCard(notification: notification)
                            }
                        }
                    }
                }
                .padding(isCompact ? AppSpacing.lg : AppSpacing.xxl)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct NotificationCard: View {
    @EnvironmentObject private var appState: AppState
    let notification: PhoneNotification

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            AppIconTile(symbol: notification.icon, color: notification.color, size: 40)
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text(notification.app).font(AppTypography.caption.weight(.semibold)).foregroundColor(.secondary)
                    Text(verbatim: "· \(notification.time)").font(AppTypography.caption).foregroundColor(Color.secondary.opacity(0.65))
                    Spacer()
                    Button(action: dismissNotification) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("notificationsDismiss")
                    .accessibilityLabel(Text("notificationsDismiss"))
                }
                Text(notification.title)
                    .font(AppTypography.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(notification.body).font(AppTypography.subheadline).foregroundColor(.secondary)
                if notification.icon == "message.fill" {
                    Label("notificationsReplyUnavailable", systemImage: "info.circle")
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(AppSpacing.lg)
        .appCard()
        .accessibilityAction(named: Text("notificationsDismiss"), dismissNotification)
    }

    private func dismissNotification() {
        if let index = appState.notifications.firstIndex(where: { $0.id == notification.id }) {
            appState.notifications.remove(at: index)
        }
    }
}
