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

    var searchDepth: Int {
        self == .recent ? 3 : 1
    }
}

private struct RemotePhotoItem: Identifiable, Hashable {
    let name: String
    let fullPath: String
    let isVideo: Bool
    let sizeText: String
    let dateText: String
    let modifiedAt: Date

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

            if !photos.isEmpty {
                Text("\(filteredPhotos.count)")
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .accessibilityLabel(Text(String(format: String.localizedKey("photosMediaCount"), filteredPhotos.count)))
            }

            Button(action: loadPhotos) {
                Image(systemName: "arrow.clockwise")
                    .font(AppTypography.body)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("commonRefresh")
            .accessibilityLabel(Text("commonRefresh"))
            .accessibilityValue(isLoading ? Text("commonLoading") : Text(""))
        }
        .padding(.horizontal, isCompact ? AppSpacing.md : AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            VStack(spacing: AppSpacing.md) {
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityHidden(true)
                Text("commonLoading")
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredPhotos.isEmpty {
            let hasSearchQuery = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Group {
                if hasSearchQuery {
                    ContentUnavailableViewCompat(
                        icon: "magnifyingglass",
                        title: "photosSearchNoResults",
                        detail: "photosSearchPrompt",
                        actionTitle: "commonClear",
                        action: { searchText = "" }
                    )
                } else {
                    ContentUnavailableViewCompat(
                        icon: "photo.on.rectangle.angled",
                        title: "photosEmptyTitle",
                        detail: "photosEmptyDetail"
                    )
                }
            }
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
        .onTapGesture(count: 2) {
            selectedPhotoID = item.id
            downloadPhoto(item)
        }
        .contextMenu {
            Button("managementDownloadAction") {
                downloadPhoto(item)
            }
            Divider()
            Button("commonDelete") {
                confirmDelete(item)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text(photoAccessibilitySummary(item)))
        .accessibilityAction { selectedPhotoID = item.id }
        .accessibilityAction(named: Text("managementDownloadAction")) {
            downloadPhoto(item)
        }
        .accessibilityAction(named: Text("commonDelete")) {
            confirmDelete(item)
        }
    }

    private func photoAccessibilitySummary(_ item: RemotePhotoItem) -> String {
        let mediaType = String.localizedKey(
            item.isVideo ? "photosMediaTypeVideo" : "photosMediaTypeImage"
        )
        return String(
            format: String.localizedKey("photosMediaAccessibilitySummary"),
            mediaType,
            item.sizeText,
            item.dateText
        )
    }

    private func loadPhotos() {
        guard let target = managementTarget(from: appState) else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let directory = ManagementADB.quote(selectedCategory.directoryPath)
                let extensionFilters = supportedExtensions
                    .map { "-iname \(ManagementADB.quote("*.\($0)"))" }
                    .joined(separator: " -o ")
                let command = "[ -d \(directory) ] || exit 0; "
                    + "find \(directory) -maxdepth \(selectedCategory.searchDepth) -type f "
                    + "\\( \(extensionFilters) \\) -exec stat -c '%s|%Y|%n' {} \\; 2>/dev/null"
                let output = try await ManagementADB.shell(target: target, command: command)
                let parsed = parsePhotoList(output)

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

    private var supportedExtensions: [String] {
        imageExtensions + videoExtensions
    }

    private var imageExtensions: [String] {
        ["jpg", "jpeg", "png", "webp", "gif", "heic", "dng"]
    }

    private var videoExtensions: [String] {
        ["mp4", "mkv", "mov", "webm", "3gp"]
    }

    private func parsePhotoList(_ raw: String) -> [RemotePhotoItem] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        return raw.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let byteCount = Int64(fields[0]),
                  let timestamp = TimeInterval(fields[1]) else {
                return nil
            }

            let fullPath = String(fields[2])
            let name = URL(fileURLWithPath: fullPath).lastPathComponent
            guard !name.hasPrefix(".") else { return nil }

            let fileExtension = URL(fileURLWithPath: fullPath).pathExtension.lowercased()
            let isVideo = videoExtensions.contains(fileExtension)
            guard isVideo || imageExtensions.contains(fileExtension) else { return nil }

            let modifiedAt = Date(timeIntervalSince1970: timestamp)
            return RemotePhotoItem(
                name: name,
                fullPath: fullPath,
                isVideo: isVideo,
                sizeText: formatFileSize(byteCount),
                dateText: dateFormatter.string(from: modifiedAt),
                modifiedAt: modifiedAt
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
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
                let output = try await ManagementADB.run(
                    target: target,
                    arguments: ["pull", item.fullPath, url.path]
                )
                guard output.succeeded else {
                    throw ManagementError.message(output.failureDetail)
                }
                appState.appendSDLLog("Photo downloaded: \(target.device.name), file=\(item.name)")
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func confirmDelete(_ item: RemotePhotoItem) {
        let alert = NSAlert()
        alert.messageText = String(
            format: String.localizedKey("photosDeleteConfirmationTitle"),
            item.name
        )
        alert.informativeText = String.localizedKey("photosDeleteConfirmationDetail")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String.localizedKey("commonDelete"))
        alert.addButton(withTitle: String.localizedKey("commonCancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        deletePhoto(item)
    }

    private func deletePhoto(_ item: RemotePhotoItem) {
        guard let target = managementTarget(from: appState) else { return }

        Task {
            do {
                _ = try await ManagementADB.shell(
                    target: target,
                    command: "rm -f \(ManagementADB.quote(item.fullPath))"
                )
                appState.appendSDLLog("Photo deleted: \(target.device.name), file=\(item.name)")
                loadPhotos()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
