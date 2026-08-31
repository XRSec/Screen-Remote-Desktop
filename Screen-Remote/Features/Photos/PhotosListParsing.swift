import Foundation

/// 一条远程媒体文件在列表中的展示信息。
/// 字段与旧 `PhotosView.RemotePhotoItem` 完全一致,id 仍为 fullPath。
struct PhotosParsedItem: Identifiable, Hashable {
    let name: String
    let fullPath: String
    let isVideo: Bool
    let sizeText: String
    let dateText: String
    let modifiedAt: Date

    var id: String { fullPath }
}

/// 解析 `find | stat` 的原始输出为媒体列表项。
/// 提取为纯函数以便在后台线程执行,避免阻塞主线程。
/// 输出语义与旧 `PhotosView.parsePhotoList` 完全一致。
enum PhotosListParsing {
    static let imageExtensions: [String] = ["jpg", "jpeg", "png", "webp", "gif", "heic", "dng"]
    static let videoExtensions: [String] = ["mp4", "mkv", "mov", "webm", "3gp"]

    static let supportedExtensions: [String] = imageExtensions + videoExtensions

    static func parse(_ raw: String) -> [PhotosParsedItem] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        // 复用格式化器:每行新建 ByteCountFormatter 是解析热点的主要成本之一。
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteFormatter.countStyle = .file

        return raw.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let byteCount = Int64(fields[0]),
                  let timestamp = TimeInterval(fields[1]) else {
                return nil
            }

            let fullPath = String(fields[2])
            // 用 NSString 直接取路径成分,避免每行构造 URL。
            let nsPath = fullPath as NSString
            let name = nsPath.lastPathComponent
            guard !name.hasPrefix(".") else { return nil }

            let fileExtension = nsPath.pathExtension.lowercased()
            let isVideo = videoExtensions.contains(fileExtension)
            guard isVideo || imageExtensions.contains(fileExtension) else { return nil }

            let modifiedAt = Date(timeIntervalSince1970: timestamp)
            return PhotosParsedItem(
                name: name,
                fullPath: fullPath,
                isVideo: isVideo,
                sizeText: byteFormatter.string(fromByteCount: byteCount),
                dateText: dateFormatter.string(from: modifiedAt),
                modifiedAt: modifiedAt
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}