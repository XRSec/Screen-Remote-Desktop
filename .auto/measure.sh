#!/bin/bash
set -euo pipefail

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# 产品过滤逻辑提取(与 PhotosView.filteredPhotos 相同)
cat > "$work_dir/PhotosFilter.swift" <<'SWIFT'
import Foundation

struct FilterItem: Identifiable, Equatable {
    let name: String
    var id: String { name }
}

enum PhotosFiltering {
    static func filtered(_ photos: [FilterItem], query: String) -> [FilterItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return photos }
        return photos.filter { $0.name.localizedCaseInsensitiveContains(normalized) }
    }
}
SWIFT

cat > "$work_dir/main.swift" <<'SWIFT'
import Foundation

#if BASELINE
// 当前产品行为:单次 body 中 filteredPhotos 被访问 5 次(toolbar count、
// photosCountSummary×2、contentArea isEmpty、ForEach),每次完整过滤
@inline(never)
func bodyEvaluation(_ photos: [FilterItem], query: String) -> Int {
    let c1 = PhotosFiltering.filtered(photos, query: query).count   // toolbar Text
    let c2 = PhotosFiltering.filtered(photos, query: query).count   // photosCountSummary(搜索分支)
    let c3 = PhotosFiltering.filtered(photos, query: query).count   // photosCountSummary(空分支)
    let empty = PhotosFiltering.filtered(photos, query: query).isEmpty  // contentArea
    let items = PhotosFiltering.filtered(photos, query: query)      // ForEach
    return c1 + c2 + c3 + (empty ? 0 : 1) + items.count
}
#else
// 候选:同一次 body 求值用 let visiblePhotos = filteredPhotos 复用
@inline(never)
func bodyEvaluation(_ photos: [FilterItem], query: String) -> Int {
    let visible = PhotosFiltering.filtered(photos, query: query)
    let c1 = visible.count
    let c2 = visible.count
    let c3 = visible.count
    let empty = visible.isEmpty
    let items = visible
    return c1 + c2 + c3 + (empty ? 0 : 1) + items.count
}
#endif

let sizes = [500, 2_000, 5_000]
let iterations = 50
var baselineTotal: UInt64 = 0
var candidateTotal: UInt64 = 0
var detail: [String] = []

for size in sizes {
    let photos = (0..<size).map { FilterItem(name: "IMG_\($0).jpg") }
    let query = "IMG_12"

    // 正确性守卫:两模式结果必须一致
    let baseResult = bodyEvaluation(photos, query: query)
    // 用未编译的候选逻辑验证:候选结果由 #else 分支计算,这里强制两种
    // 通过内部守卫:基线模式也验证候选等价值
    #if BASELINE
    let visible = PhotosFiltering.filtered(photos, query: query)
    let candCheck = visible.count + visible.count + visible.count + (visible.isEmpty ? 0 : 1) + visible.count
    guard baseResult == candCheck else {
        fatalError("baseline/candidate result mismatch: \(baseResult) vs \(candCheck)")
    }
    #else
    // 候选模式:验证单次过滤输出与多次等价
    let a = PhotosFiltering.filtered(photos, query: query)
    let b = PhotosFiltering.filtered(photos, query: query)
    let c = PhotosFiltering.filtered(photos, query: query)
    guard a == b, b == c, baseResult == a.count * 4 + (a.isEmpty ? 0 : 1) else {
        fatalError("candidate consistency mismatch")
    }
    #endif

    var samples: [UInt64] = []
    for _ in 0..<iterations {
        let s = DispatchTime.now().uptimeNanoseconds
        _ = bodyEvaluation(photos, query: query)
        samples.append(DispatchTime.now().uptimeNanoseconds - s)
    }
    samples.sort()
    let median = samples[samples.count / 2]
    #if BASELINE
    baselineTotal += median
    #else
    candidateTotal += median
    #endif
    detail.append("\(size):\(median / 1_000)us")
}

#if BASELINE
let total = baselineTotal
#else
let total = candidateTotal
#endif
print("METRIC photos_search_filter_us=\(total / 1_000)")
print("DETAIL " + detail.joined(separator: ","))
SWIFT

swift_flags=()
if [[ "${MODE:-candidate}" == "baseline" ]]; then
  swift_flags+=("-D" "BASELINE")
fi
if [[ ${#swift_flags[@]} -gt 0 ]]; then
  xcrun swiftc -O "${swift_flags[@]}" \
    "$work_dir/PhotosFilter.swift" \
    "$work_dir/main.swift" \
    -o "$work_dir/photos-filter-benchmark"
else
  xcrun swiftc -O \
    "$work_dir/PhotosFilter.swift" \
    "$work_dir/main.swift" \
    -o "$work_dir/photos-filter-benchmark"
fi
"$work_dir/photos-filter-benchmark"