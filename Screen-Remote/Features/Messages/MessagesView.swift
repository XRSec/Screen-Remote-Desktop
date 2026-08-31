import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var selectedConversation = 0
    @State private var isShowingConversation = false
    @State private var searchText = ""

    private var filteredConversations: [(offset: Int, element: Conversation)] {
        let indexedConversations = Array(appState.conversations.enumerated())
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return indexedConversations }
        return indexedConversations.filter { _, conversation in
            conversation.name.localizedCaseInsensitiveContains(query)
                || conversation.preview.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        if appState.conversations.isEmpty {
            emptyState
                .padding(isCompact ? 20 : 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
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
    }

    private var conversationList: some View {
        VStack(spacing: 0) {
            PageSearchField(searchText: $searchText, searchPrompt: "messagesSearchPrompt", expands: true)
                .padding(AppSpacing.md)

            Divider()

            ScrollView {
                if filteredConversations.isEmpty {
                    ContentUnavailableViewCompat(
                        icon: "magnifyingglass",
                        title: "messagesSearchNoResults",
                        detail: "messagesSearchPrompt",
                        actionTitle: "commonClear",
                        action: { searchText = "" }
                    )
                    .padding(AppSpacing.lg)
                } else {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredConversations, id: \.element.id) { index, conversation in
                            ConversationRow(conversation: conversation, isSelected: selectedConversation == index) {
                                selectedConversation = index
                                if isCompact {
                                    isShowingConversation = true
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.sm)
                }
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
                        Text(conversation.name).font(AppTypography.headline)
                        Text("messagesSMS").font(AppTypography.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, isCompact ? AppSpacing.lg : AppSpacing.xl)
                .frame(height: 64)
                .background(AppTheme.surface.opacity(0.96))

                Divider()

                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        ContentUnavailableViewCompat(
            icon: "message",
            title: "messagesEmptyTitle",
            detail: "messagesEmptyDetail"
        )
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
                        Text(conversation.name).font(AppTypography.headline.weight(conversation.unread ? .bold : .semibold))
                        Spacer()
                        Text(conversation.time).font(AppTypography.caption2).foregroundColor(Color.secondary.opacity(0.65))
                    }
                    Text(conversation.preview).font(AppTypography.caption).foregroundColor(.secondary).lineLimit(1)
                }
                if conversation.unread { Circle().fill(AppTheme.accent).frame(width: 7, height: 7) }
            }
            .padding(AppSpacing.sm)
            .appBackground(isSelected ? AppTheme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: AppRadius.small))
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
            .font(AppTypography.headline.weight(.bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .appBackground(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
    }
}
