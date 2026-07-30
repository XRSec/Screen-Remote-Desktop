import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedConversation = 0
    @State private var searchText = ""
    @State private var messageText = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("messagesTitle").font(.title2.bold())
                    Spacer()
                    Button(action: {}) { Image(systemName: "square.and.pencil") }.buttonStyle(.plain)
                }
                .padding(18)

                TextField("messagesSearchPrompt", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .appBackground(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(appState.conversations.enumerated()), id: \.element.id) { index, conversation in
                            ConversationRow(conversation: conversation, isSelected: selectedConversation == index) {
                                selectedConversation = index
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 290)
            .background(AppTheme.surface.opacity(0.65))

            Divider()

            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Avatar(initials: "LX", color: .purple, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("messagesContactName").font(.headline)
                        Text("messagesSMS").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {}) { Image(systemName: "info.circle") }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .frame(height: 64)
                .background(AppTheme.surface.opacity(0.96))

                Divider()

                ScrollView {
                    VStack(spacing: 14) {
                        Text("messagesTodayTime").font(.caption2).foregroundColor(Color.secondary.opacity(0.65)).padding(.top, 14)
                        MessageBubble(text: String.localizedKey("messagesIncomingFirst"), isOutgoing: false)
                        MessageBubble(text: String.localizedKey("messagesOutgoing"), isOutgoing: true)
                        MessageBubble(text: String.localizedKey("messagesIncomingLast"), isOutgoing: false)
                    }
                    .padding(.horizontal, 22)
                }

                HStack(spacing: 10) {
                    Button(action: {}) { Image(systemName: "plus.circle.fill").font(.title3) }.buttonStyle(.plain).foregroundColor(.secondary)
                    TextField("messagesSendPrompt", text: $messageText)
                        .textFieldStyle(.plain)
                    Button(action: {}) { Image(systemName: "paperplane.fill").foregroundColor(AppTheme.accent) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .appBackground(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .padding(16)
            }
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

private struct MessageBubble: View {
    let text: String
    let isOutgoing: Bool

    var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 100) }
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundColor(isOutgoing ? .white : .primary)
                .appBackground(isOutgoing ? AppTheme.accent : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !isOutgoing { Spacer(minLength: 100) }
        }
    }
}
