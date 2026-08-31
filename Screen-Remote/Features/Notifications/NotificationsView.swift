import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var searchText = ""

    private var filteredNotifications: [PhoneNotification] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.notifications }
        return appState.notifications.filter { notification in
            notification.app.localizedCaseInsensitiveContains(query)
                || notification.title.localizedCaseInsensitiveContains(query)
                || notification.body.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            if appState.notifications.isEmpty {
                ContentUnavailableViewCompat(
                    icon: "bell.slash",
                    title: "notificationsEmptyTitle",
                    detail: "notificationsEmptyDetail"
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
                        Label("notificationsNewCount", systemImage: "bell.badge.fill")
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
    @State private var reply = ""

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            AppIconTile(symbol: notification.icon, color: notification.color, size: 40)
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text(notification.app).font(AppTypography.caption.weight(.semibold)).foregroundColor(.secondary)
                    Text(verbatim: "· \(notification.time)").font(AppTypography.caption).foregroundColor(Color.secondary.opacity(0.65))
                    Spacer()
                    Button {
                        if let index = appState.notifications.firstIndex(where: { $0.id == notification.id }) {
                            appState.notifications.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                Text(notification.title).font(AppTypography.headline)
                Text(notification.body).font(AppTypography.subheadline).foregroundColor(.secondary)
                if notification.icon == "message.fill" {
                    HStack(spacing: AppSpacing.sm) {
                        TextField("notificationsQuickReply", text: $reply)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .appBackground(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: AppRadius.small))
                        Button {
                            guard !reply.isEmpty else { return }
                            reply = ""
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .appBackground(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppRadius.small))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(AppSpacing.lg)
        .appCard()
    }
}
