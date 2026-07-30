import SwiftUI

struct PhotosView: View {
    @State private var searchText = ""
    @State private var selectedPhoto: Int?

    private let palettes: [[Color]] = [
        [.pink.opacity(0.8), .orange], [.appMint, .appCyan], [.appIndigo, .purple], [.orange, .yellow],
        [.blue, .appTeal], [.purple.opacity(0.7), .pink], [.green, .appMint], [.appCyan, .blue],
        [.yellow, .orange], [.appIndigo.opacity(0.7), .blue], [.pink, .purple], [.appTeal, .green]
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "photosTitle", subtitle: "photosSubtitle", searchText: $searchText, searchPrompt: "photosSearchPrompt")

                HStack {
                    Picker("", selection: .constant(0)) {
                        Text("photosRecent").tag(0)
                        Text("photosScreenshots").tag(1)
                        Text("photosCamera").tag(2)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 270)
                    Spacer()
                    Text("photosTodayCount").font(.caption).foregroundColor(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(palettes.indices, id: \.self) { index in
                        PhotoTile(index: index, colors: palettes[index], isSelected: selectedPhoto == index)
                            .onTapGesture { selectedPhoto = index }
                    }
                }
            }
            .padding(28)
        }
    }
}

private struct PhotoTile: View {
    let index: Int
    let colors: [Color]
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            Image(systemName: photoSymbol)
                .font(.system(size: 42, weight: .light))
                .foregroundColor(.white.opacity(0.82))

            VStack {
                Spacer()
                HStack {
                    Text(index < 4 ? "photosToday" : "photosYesterday")
                    Spacer()
                    Text(String(format: "%02d:%02d", 9 + index / 4, (index * 7) % 60))
                }
                .font(.caption2.weight(.medium))
                .foregroundColor(.white)
                .padding(9)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            }
        }
        .aspectRatio(1.32, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? AppTheme.accent : .white.opacity(0.16), lineWidth: isSelected ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var photoSymbol: String {
        ["leaf.fill", "cup.and.saucer.fill", "building.2.fill", "sun.horizon.fill", "mountain.2.fill", "camera.fill"][index % 6]
    }
}
