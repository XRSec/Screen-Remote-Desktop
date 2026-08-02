import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageSearchField(
                    searchText: $searchText,
                    searchPrompt: "notificationsSearchPrompt",
                    expands: true
                )

                if appState.notifications.isEmpty {
                    ContentUnavailableViewCompat(
                        icon: "bell.slash",
                        title: "notificationsEmptyTitle",
                        detail: "notificationsEmptyDetail"
                    )
                    .frame(minHeight: 260)
                } else {
                    HStack {
                        Label("notificationsNewCount", systemImage: "bell.badge.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AppTheme.accent)
                        Spacer()
                        Button("notificationsClearAll", action: {}).buttonStyle(.plain).foregroundColor(.secondary)
                    }

                    VStack(spacing: 12) {
                        ForEach(appState.notifications) { notification in
                            NotificationCard(notification: notification)
                        }
                    }
                }
            }
            .padding(isCompact ? 20 : 28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NotificationCard: View {
    let notification: PhoneNotification
    @State private var reply = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconTile(symbol: notification.icon, color: notification.color, size: 40)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(notification.app).font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    Text(verbatim: "· \(notification.time)").font(.caption).foregroundColor(Color.secondary.opacity(0.65))
                    Spacer()
                    Button(action: {}) { Image(systemName: "ellipsis") }.buttonStyle(.plain).foregroundColor(.secondary)
                    Button(action: {}) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundColor(.secondary)
                }
                Text(notification.title).font(.headline)
                Text(notification.body).font(.subheadline).foregroundColor(.secondary)
                if notification.icon == "message.fill" {
                    HStack(spacing: 8) {
                        TextField("notificationsQuickReply", text: $reply)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .appBackground(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        Button(action: {}) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .appBackground(AppTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .appCard()
    }
}
