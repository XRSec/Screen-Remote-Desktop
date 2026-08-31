import SwiftUI

struct UtilitySheetHeader: View {
    let title: LocalizedStringKey
    let close: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: close) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("commonClose")
                .accessibilityLabel(Text("commonClose"))
        }
        .padding(20)
    }
}

struct UtilityForm<Content: View>: View {
    let detail: LocalizedStringKey
    let primaryTitle: LocalizedStringKey
    let primaryEnabled: Bool
    let primaryAction: () -> Void
    var secondaryTitle: LocalizedStringKey?
    var secondaryAction: (() -> Void)?
    let content: Content

    init(
        detail: LocalizedStringKey,
        primaryTitle: LocalizedStringKey,
        primaryEnabled: Bool,
        primaryAction: @escaping () -> Void,
        secondaryTitle: LocalizedStringKey? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.detail = detail
        self.primaryTitle = primaryTitle
        self.primaryEnabled = primaryEnabled
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(detail).font(AppTypography.subheadline).foregroundColor(.secondary)
            content
            HStack {
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                }
                Spacer()
                Button(primaryTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!primaryEnabled)
            }
        }
    }
}

struct UtilityTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text(title))
        }
    }
}

struct UtilityOptionList<Content: View>: View {
    let detail: LocalizedStringKey
    let content: Content

    init(detail: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(detail).font(AppTypography.subheadline).foregroundColor(.secondary)
            VStack(spacing: AppSpacing.sm) { content }
        }
    }
}

struct UtilityOptionButton: View {
    let title: LocalizedStringKey?
    let titleText: String?
    let icon: String
    var badge: String?
    var enabled = true
    var isDestructive = false
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        icon: String,
        badge: String? = nil,
        enabled: Bool = true,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.titleText = nil
        self.icon = icon
        self.badge = badge
        self.enabled = enabled
        self.isDestructive = isDestructive
        self.action = action
    }

    init(
        titleText: String,
        icon: String,
        badge: String? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.titleText = titleText
        self.icon = icon
        self.badge = badge
        self.enabled = enabled
        self.isDestructive = false
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                if let title { Text(title) } else if let titleText { Text(titleText) }
                Spacer()
                if let badge {
                    Text(badge).font(AppTypography.caption2).foregroundColor(.secondary)
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, AppSpacing.xs)
                        .accessibilityHidden(true)
                        .appBackground(Color.primary.opacity(0.06), in: Capsule())
                }
                Image(systemName: "chevron.right").font(AppTypography.caption2).foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.md)
            .contentShape(Rectangle())
            .appCard(radius: AppRadius.card)
            .accessibilityElement(children: .combine)
            .accessibilityValue(badge.map { Text($0) } ?? Text(""))
        }
        .buttonStyle(.plain)
        .foregroundColor(isDestructive ? .red : .primary)
        .disabled(!enabled)
    }
}
