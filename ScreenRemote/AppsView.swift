import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var filteredApps: [PhoneApp] {
        searchText.isEmpty ? appState.apps : appState.apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "appsTitle",
                    subtitle: "appsSubtitle",
                    searchText: $searchText,
                    searchPrompt: "appsSearchPrompt"
                )

                HStack(spacing: 14) {
                    StatCard(icon: "apps.iphone", value: "42", label: "appsInstalledCount", color: .blue)
                    StatCard(icon: "clock.arrow.circlepath", value: "4", label: "appsRecentCount", color: .purple)
                    StatCard(icon: "bolt.fill", value: "86%", label: "appsBatteryLevel", color: .green)
                }

                SectionTitle(title: "appsRecentSection", actionTitle: "appsViewAll")
                HStack(spacing: 14) {
                    ForEach(appState.apps.prefix(4)) { app in
                        RecentAppCard(app: app)
                    }
                }

                SectionTitle(title: searchText.isEmpty ? "appsAllSection" : "appsSearchResultsSection", actionTitle: "commonRefresh")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 150), spacing: 12)], spacing: 12) {
                    ForEach(filteredApps) { app in
                        AppGridItem(app: app)
                    }
                }
            }
            .padding(28)
        }
    }
}

struct PageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var searchText: String
    let searchPrompt: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 28, weight: .bold))
                Text(subtitle).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            TextField(searchPrompt, text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(width: 230, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.055)))
                .overlay(
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).padding(.trailing, 10)
                    , alignment: .trailing
                )
        }
    }
}

struct SectionTitle: View {
    let title: LocalizedStringKey
    let actionTitle: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(actionTitle, action: {}).buttonStyle(.plain).font(.caption).foregroundColor(AppTheme.accent)
        }
    }
}

private struct StatCard: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(label).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .appCard()
    }
}

private struct RecentAppCard: View {
    let app: PhoneApp

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 11) {
                AppIconTile(symbol: app.icon, color: app.color, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 13, weight: .semibold))
                    Text("appsOpenAction").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundColor(Color.secondary.opacity(0.65))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .appCard()
        }
        .buttonStyle(.plain)
    }
}

private struct AppGridItem: View {
    let app: PhoneApp

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    AppIconTile(symbol: app.icon, color: app.color, size: 48)
                    if app.badge > 0 {
                        Text("\(app.badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(Color.red))
                            .offset(x: 5, y: -5)
                    }
                }
                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line))
        }
        .buttonStyle(.plain)
    }
}
