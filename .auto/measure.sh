#!/bin/bash
set -euo pipefail

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

cat > "$work_dir/ManagedAndroidApp.swift" <<'SWIFT'
import Foundation

struct ManagedAndroidApp: Identifiable, Codable, Equatable {
    let packageName: String
    let name: String
    let isEnabled: Bool
    let isSystem: Bool
    let versionCode: Int64
    let lastUpdateTime: Int64
    let iconFileName: String?
    var id: String { packageName }
}
SWIFT

# Candidate pure function used as the product file when present; otherwise fall
# back to an identical inline copy so baseline/candidate measurement is never
# blocked by an autoresearch rollback.
if [[ -f "Screen-Remote/Features/Apps/Models/ManagedAppFiltering.swift" ]]; then
  cp "Screen-Remote/Features/Apps/Models/ManagedAppFiltering.swift" "$work_dir/ManagedAppFiltering.swift"
else
  cat > "$work_dir/ManagedAppFiltering.swift" <<'SWIFT'
import Foundation

enum ManagedAppFiltering {
    static func filter(
        _ apps: [ManagedAndroidApp],
        systemState: Bool?,
        enabledState: Bool?,
        searchTerms: [String]
    ) -> [ManagedAndroidApp] {
        apps.filter { app in
            if let systemState, app.isSystem != systemState { return false }
            if let enabledState, app.isEnabled != enabledState { return false }
            return searchTerms.allSatisfy { term in
                app.name.localizedCaseInsensitiveContains(term)
                    || app.packageName.localizedCaseInsensitiveContains(term)
            }
        }
    }
}
SWIFT
fi

cat > "$work_dir/main.swift" <<'SWIFT'
import Foundation

#if BASELINE
@inline(never)
func measuredFilter(
    _ apps: [ManagedAndroidApp],
    systemState: Bool?,
    enabledState: Bool?,
    searchTerms: [String]
) -> [ManagedAndroidApp] {
    let visibleApps = systemState.map { state in apps.filter { $0.isSystem == state } } ?? apps
    let enabledApps = enabledState.map { state in visibleApps.filter { $0.isEnabled == state } } ?? visibleApps
    guard !searchTerms.isEmpty else { return enabledApps }
    return enabledApps.filter { app in
        searchTerms.allSatisfy { term in
            app.name.localizedCaseInsensitiveContains(term)
                || app.packageName.localizedCaseInsensitiveContains(term)
        }
    }
}
#else
@inline(never)
func measuredFilter(
    _ apps: [ManagedAndroidApp],
    systemState: Bool?,
    enabledState: Bool?,
    searchTerms: [String]
) -> [ManagedAndroidApp] {
    ManagedAppFiltering.filter(
        apps,
        systemState: systemState,
        enabledState: enabledState,
        searchTerms: searchTerms
    )
}
#endif

let sizes = [200, 500, 2_000]
let iterations = 80
var totalNanoseconds: UInt64 = 0
var combinedCount = 0
var combinedIndexSum: Int64 = 0
var detail: [String] = []

for size in sizes {
    var apps: [ManagedAndroidApp] = []
    apps.reserveCapacity(size)
    for index in 0..<size {
        let name = index % 11 == 0 ? "Camera Tool \(index)" : "Application \(index)"
        apps.append(ManagedAndroidApp(
            packageName: "com.example.package\(index)",
            name: name,
            isEnabled: index % 7 != 0,
            isSystem: index % 5 == 0,
            versionCode: Int64(index),
            lastUpdateTime: Int64(index),
            iconFileName: nil
        ))
    }
    var samples: [UInt64] = []
    var resultCount = 0
    var indexSum: Int64 = 0
    for _ in 0..<iterations {
        let started = DispatchTime.now().uptimeNanoseconds
        let result = measuredFilter(
            apps,
            systemState: false,
            enabledState: true,
            searchTerms: ["application", "package"]
        )
        samples.append(DispatchTime.now().uptimeNanoseconds - started)
        resultCount = result.count
        indexSum = result.reduce(0) { $0 + $1.versionCode }
    }
    samples.sort()
    let median = samples[samples.count / 2]
    totalNanoseconds += median
    combinedCount += resultCount
    combinedIndexSum += indexSum
    detail.append("\(size):\(median / 1_000)us")
}

if combinedCount != 1683 || combinedIndexSum != 1_337_737 {
    fatalError("unexpected result: count=\(combinedCount), sum=\(combinedIndexSum)")
}
print("METRIC app_filter_total_us=\(totalNanoseconds / 1_000)")
print("METRIC app_filter_result_count=\(combinedCount)")
print("METRIC app_filter_index_sum=\(combinedIndexSum)")
print("DETAIL " + detail.joined(separator: ","))
SWIFT

swift_flags=()
if [[ "${MODE:-candidate}" == "baseline" ]]; then
  swift_flags+=("-D" "BASELINE")
fi
if [[ ${#swift_flags[@]} -gt 0 ]]; then
  xcrun swiftc -O "${swift_flags[@]}" \
    "$work_dir/ManagedAndroidApp.swift" \
    "$work_dir/ManagedAppFiltering.swift" \
    "$work_dir/main.swift" \
    -o "$work_dir/app-filter-benchmark"
else
  xcrun swiftc -O \
    "$work_dir/ManagedAndroidApp.swift" \
    "$work_dir/ManagedAppFiltering.swift" \
    "$work_dir/main.swift" \
    -o "$work_dir/app-filter-benchmark"
fi
"$work_dir/app-filter-benchmark"
