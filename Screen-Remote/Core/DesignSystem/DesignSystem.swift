import SwiftUI

enum AppTheme {
    static let background = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.075, alpha: 1)
            : NSColor(calibratedRed: 0.965, green: 0.969, blue: 0.978, alpha: 1)
    })
    static let sidebar = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.105, alpha: 1)
            : NSColor(calibratedRed: 0.925, green: 0.937, blue: 0.957, alpha: 1)
    })
    static let surface = Color(NSColor.controlBackgroundColor)
    static let line = Color.primary.opacity(0.09)
    static let accent = Color(red: 0.18, green: 0.42, blue: 0.93)
}

extension Color {
    static let appIndigo = Color(red: 0.345, green: 0.337, blue: 0.839)
    static let appCyan = Color(red: 0.333, green: 0.745, blue: 0.941)
    static let appMint = Color(red: 0.20, green: 0.78, blue: 0.62)
    static let appTeal = Color(red: 0.18, green: 0.62, blue: 0.66)
}

// MARK: - Unified UI Tokens
// Centralized values prevent individual views from drifting visually.
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
}

enum AppTypography {
    static let largeTitle = Font.system(size: 28, weight: .bold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let section = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(AppTypography.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .appBackground(color.opacity(0.12), in: Capsule())
    }
}

struct CardModifier: ViewModifier {
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .appMaterialBackground(in: shape)
            .appOverlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

extension View {
    func appCard(radius: CGFloat = 14) -> some View {
        modifier(CardModifier(radius: radius))
    }
}

struct AppIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.78), color], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.2), radius: 4, y: 2)
    }
}

struct ContentUnavailableViewCompat: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            AppIconTile(symbol: icon, color: AppTheme.accent, size: 48)
            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.section)
                Text(detail)
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
    }
}
