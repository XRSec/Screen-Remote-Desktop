import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var selectedConversation = 0
    @State private var isShowingConversation = false
    @State private var searchText = ""

    var body: some View {
        Group {
            if isCompact {
                if isShowingConversation {
                    conversationDetail(showsBackButton: true)
                } else {
                    conversationList
                }
            } else {
                HStack(spacing: 0) {
                    conversationList
                        .frame(width: 290)

                    Divider()

                    conversationDetail(showsBackButton: false)
                }
            }
        }
    }

    private var conversationList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PageSearchField(searchText: $searchText, searchPrompt: "messagesSearchPrompt", expands: true)
                Button(action: {}) { Image(systemName: "square.and.pencil") }.buttonStyle(.plain)
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 3) {
                    if appState.conversations.isEmpty {
                        ContentUnavailableViewCompat(
                            icon: "message",
                            title: "messagesEmptyTitle",
                            detail: "messagesEmptyDetail"
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(Array(appState.conversations.enumerated()), id: \.element.id) { index, conversation in
                            ConversationRow(conversation: conversation, isSelected: selectedConversation == index) {
                                selectedConversation = index
                                if isCompact {
                                    isShowingConversation = true
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(AppTheme.surface.opacity(0.65))
    }

    @ViewBuilder
    private func conversationDetail(showsBackButton: Bool) -> some View {
        if appState.conversations.indices.contains(selectedConversation) {
            let conversation = appState.conversations[selectedConversation]
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    if showsBackButton {
                        Button {
                            isShowingConversation = false
                        } label: {
                            Label("messagesTitle", systemImage: "chevron.left")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                    }

                    Avatar(initials: conversation.initials, color: conversation.color, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.name).font(.headline)
                        Text("messagesSMS").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {}) { Image(systemName: "info.circle") }.buttonStyle(.plain)
                }
                .padding(.horizontal, isCompact ? 16 : 20)
                .frame(height: 64)
                .background(AppTheme.surface.opacity(0.96))

                Divider()

                ContentUnavailableViewCompat(
                    icon: "message",
                    title: "messagesEmptyTitle",
                    detail: "messagesEmptyDetail"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableViewCompat(
                icon: "message",
                title: "messagesEmptyTitle",
                detail: "messagesEmptyDetail"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Avatar(initials: conversation.initials, color: conversation.color, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conversation.name).font(.system(size: 13, weight: conversation.unread ? .bold : .semibold))
                        Spacer()
                        Text(conversation.time).font(.caption2).foregroundColor(Color.secondary.opacity(0.65))
                    }
                    Text(conversation.preview).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                if conversation.unread { Circle().fill(AppTheme.accent).frame(width: 7, height: 7) }
            }
            .padding(10)
            .appBackground(isSelected ? AppTheme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Avatar: View {
    let initials: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.29, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .appBackground(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
    }
}
