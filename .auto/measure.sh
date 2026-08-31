#!/bin/bash
set -euo pipefail

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Baseline: 旧 PhotosView.parsePhotoList 同一逻辑的副本(纯函数提取,行为一致)
cat > "$work_dir/BaselineParsing.swift" <<'SWIFT'
import Foundation

struct BaselineItem: Hashable {
    let name: String
    let fullPath: String
    let isVideo: Bool
    let sizeText: String
    let dateText: String
    let modifiedAt: Date
    var id: String { fullPath }
}

enum BaselineParsing {
    static let imageExtensions: [String] = ["jpg", "jpeg", "png", "webp", "gif", "heic", "dng"]
    static let videoExtensions: [String] = ["mp4", "mkv", "mov", "webm", "3gp"]

    static func parse(_ raw: String) -> [BaselineItem] {
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
            let byteFormatter = ByteCountFormatter()
            byteFormatter.allowedUnits = [.useKB, .useMB, .useGB]
            byteFormatter.countStyle = .file
            return BaselineItem(
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
SWIFT

# Candidate: 产品纯函数文件(存在则直接使用,否则用一致内联副本兜底)
if [[ -f "Screen-Remote/Features/Photos/PhotosListParsing.swift" ]]; then
  cp "Screen-Remote/Features/Photos/PhotosListParsing.swift" "$work_dir/PhotosListParsing.swift"
else
  echo "!! PhotosListParsing.swift missing (rollback?) — using inline copy" >&2
  cat > "$work_dir/PhotosListParsing.swift" <<'SWIFT'
import Foundation

struct PhotosParsedItem: Identifiable, Hashable {
    let name: String
    let fullPath: String
    let isVideo: Bool
    let sizeText: String
    let dateText: String
    let modifiedAt: Date
    var id: String { fullPath }
}

enum PhotosListParsing {
    static let imageExtensions: [String] = ["jpg", "jpeg", "png", "webp", "gif", "heic", "dng"]
    static let videoExtensions: [String] = ["mp4", "mkv", "mov", "webm", "3gp"]
    static let supportedExtensions: [String] = imageExtensions + videoExtensions

    static func parse(_ raw: String) -> [PhotosParsedItem] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteFormatter.countStyle = .file

        return raw.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let byteCount = Int64(fields[0]),
                  let timestamp = TimeInterval(fields[1]) else { return nil }

            let fullPath = String(fields[2])
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
SWIFT
fi

cat > "$work_dir/main.swift" <<'SWIFT'
import Foundation

let sizes = [500, 2_000, 10_000]
let iterations = 30
var baselineTotal: UInt64 = 0
var candidateTotal: UInt64 = 0
var detail: [String] = []

for size in sizes {
    var lines: [String] = []
    lines.reserveCapacity(size)
    for i in 0..<size {
        let bytes = 200_000 + i * 137
        let ts = 1_700_000_000 + i * 30
        let ext = i % 7 == 0 ? "mp4" : "jpg"
        lines.append("\(bytes)|\(ts)|/sdcard/DCIM/Camera/IMG_\(i).\(ext)")
    }
    let raw = lines.joined(separator: "\n")

    // 正确性守卫:逐项比较两实现输出(同一次输入)
    let expected = BaselineParsing.parse(raw)
    let candidate = PhotosListParsing.parse(raw)
    guard expected.count == candidate.count else {
        fatalError("count mismatch: \(expected.count) vs \(candidate.count)")
    }
    for (b, c) in zip(expected, candidate) {
        guard b.id == c.id, b.name == c.name, b.isVideo == c.isVideo,
              b.sizeText == c.sizeText, b.dateText == c.dateText, b.modifiedAt == c.modifiedAt else {
            fatalError("item mismatch: \(b) vs \(c)")
        }
    }

    var baseSamples: [UInt64] = []
    var candSamples: [UInt64] = []
    for _ in 0..<iterations {
        let s1 = DispatchTime.now().uptimeNanoseconds
        _ = BaselineParsing.parse(raw)
        baseSamples.append(DispatchTime.now().uptimeNanoseconds - s1)

        let s2 = DispatchTime.now().uptimeNanoseconds
        _ = PhotosListParsing.parse(raw)
        candSamples.append(DispatchTime.now().uptimeNanoseconds - s2)
    }
    baseSamples.sort()
    candSamples.sort()
    let bMedian = baseSamples[baseSamples.count / 2]
    let cMedian = candSamples[candSamples.count / 2]
    baselineTotal += bMedian
    candidateTotal += cMedian
    detail.append("\(size):base=\(bMedian / 1_000)us,cand=\(cMedian / 1_000)us")
}

#if BASELINE
let total = baselineTotal
#else
let total = candidateTotal
#endif
print("METRIC photos_parse_main_busy_us=\(total / 1_000)")
print("DETAIL " + detail.joined(separator: ","))
SWIFT

swift_flags=()
if [[ "${MODE:-candidate}" == "baseline" ]]; then
  swift_flags+=("-D" "BASELINE")
fi
if [[ ${#swift_flags[@]} -gt 0 ]]; then
  xcrun swiftc -O "${swift_flags[@]}" \
    "$work_dir/BaselineParsing.swift" \
    "$work_dir/PhotosListParsing.swift" \
    "$work_dir/main.swift" \
    -o "$work_dir/photos-parse-benchmark"
else
  xcrun swiftc -O \
    "$work_dir/BaselineParsing.swift" \
    "$work_dir/PhotosListParsing.swift" \
    "$work_dir/main.swift" \
    -o "$work_dir/photos-parse-benchmark"
fi
"$work_dir/photos-parse-benchmark"