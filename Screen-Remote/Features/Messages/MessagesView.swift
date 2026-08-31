import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var selectedConversationID: UUID?
    @State private var isShowingConversation = false
    @State private var searchText = ""

    private var conversationIDs: [UUID] {
        appState.conversations.map(\.id)
    }

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredConversations: [(offset: Int, element: Conversation)] {
        let indexedConversations = Array(appState.conversations.enumerated())
        guard !normalizedSearchQuery.isEmpty else { return indexedConversations }
        return indexedConversations.filter { _, conversation in
            conversation.name.localizedCaseInsensitiveContains(normalizedSearchQuery)
                || conversation.preview.localizedCaseInsensitiveContains(normalizedSearchQuery)
        }
    }

    var body: some View {
        Group {
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
        .onChange(of: conversationIDs) { _ in
            synchronizeSelectionWithFilteredConversations()
        }
    }

    private var conversationList: some View {
        let listCount = filteredConversations.count == 1
            ? String.localizedKey("messagesConversationCountOne")
            : String(
                format: String.localizedKey("messagesConversationCount"),
                filteredConversations.count
            )
        let countSummary = normalizedSearchQuery.isEmpty ? listCount : String(
            format: String.localizedKey("messagesFilteredConversationCount"),
            filteredConversations.count,
            appState.conversations.count
        )
        let unreadConversationCount = filteredConversations.filter(\.element.unread).count
        let unreadCount = String(
            format: String.localizedKey("messagesUnreadConversationCount"),
            unreadConversationCount
        )
        let listSummary = unreadConversationCount == 0 ? countSummary : String(
            format: String.localizedKey("messagesConversationSummary"),
            countSummary,
            unreadCount
        )
        return VStack(spacing: 0) {
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
                        ForEach(filteredConversations, id: \.element.id) { _, conversation in
                            ConversationRow(conversation: conversation, isSelected: selectedConversationID == conversation.id) {
                                selectedConversationID = conversation.id
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("messagesConversationList"))
        .accessibilityValue(Text(listSummary))
        .onAppear {
            synchronizeSelectionWithFilteredConversations()
        }
        .onChange(of: normalizedSearchQuery) { _ in
            synchronizeSelectionWithFilteredConversations()
        }
    }

    private func synchronizeSelectionWithFilteredConversations() {
        guard !filteredConversations.contains(where: { $0.element.id == selectedConversationID }) else { return }
        selectedConversationID = filteredConversations.first?.element.id
        if selectedConversationID == nil {
            isShowingConversation = false
        }
    }

    @ViewBuilder
    private func conversationDetail(showsBackButton: Bool) -> some View {
        if let conversation = appState.conversations.first(where: { $0.id == selectedConversationID }) {
            let detailLabel = String(
                format: String.localizedKey("messagesConversationDetail"),
                conversation.name
            )
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
                        .keyboardShortcut(.cancelAction)
                        .help("messagesBackToList")
                        .accessibilityLabel(Text("messagesBackToList"))
                    }

                    Avatar(initials: conversation.initials, color: conversation.color, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.name).font(AppTypography.headline)
                        Text("messagesSMS").font(AppTypography.caption).foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(conversation.unread ? Text("messagesUnread") : Text("messagesRead"))
                    Spacer()
                }
                .padding(.horizontal, isCompact ? AppSpacing.lg : AppSpacing.xl)
                .frame(height: 64)
                .background(AppTheme.surface.opacity(0.96))

                Divider()

                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(detailLabel))
        } else {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("messagesEmptyConversationDetail"))
        }
    }

    private var emptyState: some View {
        ContentUnavailableViewCompat(
            icon: "message",
            title: "messagesSyncUnavailableTitle",
            detail: "messagesSyncUnavailableDetail"
        )
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let action: () -> Void

    private var conversationAccessibilitySummary: String {
        [
            conversation.preview,
            conversation.time,
            String.localizedKey(conversation.unread ? "messagesUnread" : "messagesRead"),
        ].joined(separator: ", ")
    }

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
                if conversation.unread {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
            }
            .padding(AppSpacing.sm)
            .appBackground(isSelected ? AppTheme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: AppRadius.small))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(conversation.name))
        .accessibilityHint(Text("messagesOpenConversationHint"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text(conversationAccessibilitySummary))
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
            .accessibilityHidden(true)
    }
}
