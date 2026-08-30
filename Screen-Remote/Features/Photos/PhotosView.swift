import AppKit
import SwiftUI

private enum PhotoCategory: String, CaseIterable, Identifiable {
    case recent
    case camera
    case screenshots

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .recent: "photosRecent"
        case .camera: "photosCamera"
        case .screenshots: "photosScreenshots"
        }
    }

    var directoryPath: String {
        switch self {
        case .recent: "/sdcard/DCIM"
        case .camera: "/sdcard/DCIM/Camera"
        case .screenshots: "/sdcard/Pictures/Screenshots"
        }
    }
}

private struct RemotePhotoItem: Identifiable, Hashable {
    let name: String
    let fullPath: String
    let isVideo: Bool
    let sizeText: String
    let dateText: String

    var id: String { fullPath }
}

struct PhotosView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool

    @State private var selectedCategory: PhotoCategory = .recent
    @State private var photos: [RemotePhotoItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedPhotoID: String?
    @State private var isDownloading = false

    private var filteredPhotos: [RemotePhotoItem] {
        guard !searchText.isEmpty else { return photos }
        return photos.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if managementTarget(from: appState) == nil {
                ManagementUnavailableView()
            } else {
                VStack(spacing: 0) {
                    toolbar
                    Divider()

                    if let errorMessage {
                        ManagementErrorBanner(message: errorMessage)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.top, AppSpacing.md)
                    }

                    contentArea
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .onAppear(perform: loadPhotos)
        .onChange(of: selectedCategory) { _ in loadPhotos() }
        .onChange(of: appState.selectedDevice) { _ in loadPhotos() }
        .onReceive(NotificationCenter.default.publisher(for: .screenRemoteRefreshManagement)) { _ in loadPhotos() }
    }

    private var toolbar: some View {
        HStack(spacing: AppSpacing.md) {
            Picker("photosCategory", selection: $selectedCategory) {
                ForEach(PhotoCategory.allCases) { category in
                    Text(category.titleKey).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            Spacer()

            PageSearchField(
                searchText: $searchText,
                searchPrompt: "photosSearchPrompt",
                expands: false
            )

            Button(action: loadPhotos) {
                Image(systemName: "arrow.clockwise")
                    .font(AppTypography.body)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("commonRefresh")
        }
        .padding(.horizontal, isCompact ? AppSpacing.md : AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            VStack(spacing: AppSpacing.md) {
                ProgressView().scaleEffect(0.8)
                Text("commonLoading")
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredPhotos.isEmpty {
            ContentUnavailableViewCompat(
                icon: "photo.on.rectangle.angled",
                title: "photosEmptyTitle",
                detail: "photosEmptyDetail"
            )
            .padding(isCompact ? AppSpacing.lg : AppSpacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: AppSpacing.md)],
                    spacing: AppSpacing.md
                ) {
                    ForEach(filteredPhotos) { item in
                        photoGridCard(item)
                    }
                }
                .padding(isCompact ? AppSpacing.md : AppSpacing.lg)
            }
        }
    }

    private func photoGridCard(_ item: RemotePhotoItem) -> some View {
        let isSelected = selectedPhotoID == item.id

        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: item.isVideo ? "video.fill" : "photo")
                            .font(AppTypography.title)
                            .foregroundColor(item.isVideo ? .appCyan : .secondary.opacity(0.6))
                    )

                if item.isVideo {
                    Text("MP4")
                        .font(AppTypography.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .padding(AppSpacing.xs)
                }
            }

            Text(item.name)
                .font(AppTypography.caption.weight(.medium))
                .lineLimit(1)

            HStack {
                Text(item.sizeText)
                    .font(AppTypography.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(item.dateText)
                    .font(AppTypography.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPhotoID = item.id
        }
        .contextMenu {
            Button("managementDownloadAction") {
                downloadPhoto(item)
            }
            Divider()
            Button("commonDelete") {
                deletePhoto(item)
            }
        }
    }

    private func loadPhotos() {
        guard let target = managementTarget(from: appState) else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let targetDir = selectedCategory.directoryPath
                let cmd = "ls -la '\(targetDir)' 2>/dev/null"
                let output = try await ManagementADB.shell(target: target, command: cmd)
                let parsed = parsePhotoList(output, directory: targetDir)

                await MainActor.run {
                    self.photos = parsed
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.photos = []
                    self.isLoading = false
                }
            }
        }
    }

    private func parsePhotoList(_ raw: String, directory: String) -> [RemotePhotoItem] {
        let lines = raw.components(separatedBy: .newlines)
        var items: [RemotePhotoItem] = []

        let imageExtensions = ["jpg", "jpeg", "png", "webp", "gif", "heic", "dng"]
        let videoExtensions = ["mp4", "mkv", "mov", "webm", "3gp"]

        for line in lines {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 8 else { continue }
            let name = parts.suffix(from: 7).joined(separator: " ")
            guard !name.hasPrefix("."), name != "." && name != ".." else { continue }

            let ext = (name as NSString).pathExtension.lowercased()
            let isImage = imageExtensions.contains(ext)
            let isVideo = videoExtensions.contains(ext)
            guard isImage || isVideo else { continue }

            let size = parts.count >= 5 ? String(parts[4]) : "0"
            let sizeFormatted = formatFileSize(Int64(size) ?? 0)
            let dateFormatted = parts.count >= 7 ? "\(parts[5]) \(parts[6])" : ""

            let fullPath = "\(directory)/\(name)"
            items.append(RemotePhotoItem(
                name: name,
                fullPath: fullPath,
                isVideo: isVideo,
                sizeText: sizeFormatted,
                dateText: dateFormatted
            ))
        }

        return items.reversed()
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func downloadPhoto(_ item: RemotePhotoItem) {
        guard let target = managementTarget(from: appState) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                _ = try await ManagementADB.run(
                    target: target,
                    arguments: ["pull", item.fullPath, url.path]
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deletePhoto(_ item: RemotePhotoItem) {
        guard let target = managementTarget(from: appState) else { return }

        Task {
            do {
                _ = try await ManagementADB.shell(
                    target: target,
                    command: "rm -f '\(item.fullPath)'"
                )
                loadPhotos()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
