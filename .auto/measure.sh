#!/bin/bash
set -euo pipefail

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# 基线:SDLLogView.highlightKeywords 当前逻辑(每次调用新建 3 个 NSRegularExpression)
cat > "$work_dir/LogHighlight.swift" <<'SWIFT'
import AppKit
import Foundation

enum LogHighlight {
    static let patterns: [(String, NSColor)] = [
        ("\\b(ERROR|FATAL|FAILED|EXCEPTION)\\b", .systemRed),
        ("\\b(WARN|WARNING)\\b", .systemOrange),
        ("\\b(READY|CONNECTED|STARTED|COMPLETED|SUCCESS)\\b", .systemGreen),
    ]

    static func apply(to text: NSMutableAttributedString, range: NSRange) {
        let message = text.attributedSubstring(from: range).string
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            regex.enumerateMatches(in: message, range: NSRange(location: 0, length: (message as NSString).length)) { match, _, _ in
                guard let match else { return }
                let absoluteRange = NSRange(
                    location: range.location + match.range.location,
                    length: match.range.length
                )
                text.addAttribute(.foregroundColor, value: color, range: absoluteRange)
                text.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), range: absoluteRange)
            }
        }
    }

    static func build(_ entries: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        for (idx, line) in entries.enumerated() {
            let lineStart = result.length
            result.append(NSAttributedString(string: line + "\n", attributes: base))
            // 模拟产品的时间戳/tag 着色后,对整行做关键字高亮
            let range = NSRange(location: lineStart, length: (line as NSString).length)
            apply(to: result, range: range)
            _ = idx
        }
        return result
    }
}
SWIFT

cat > "$work_dir/main.swift" <<'SWIFT'
import AppKit
import Foundation

#if BASELINE
// 基线:LogHighlight 每次新建正则(与产品一致)
@inline(never)
func renderLogs(_ entries: [String]) -> NSAttributedString {
    LogHighlight.build(entries)
}
#else
// 候选:静态缓存正则
private let cachedRegex: [(NSRegularExpression, NSColor)] = LogHighlight.patterns.compactMap { pattern, color in
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    return (regex, color)
}

@inline(never)
func renderLogs(_ entries: [String]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.textColor,
    ]
    for line in entries {
        let lineStart = result.length
        result.append(NSAttributedString(string: line + "\n", attributes: base))
        let message = line
        for (regex, color) in cachedRegex {
            regex.enumerateMatches(in: message, range: NSRange(location: 0, length: (message as NSString).length)) { match, _, _ in
                guard let match else { return }
                let absoluteRange = NSRange(location: lineStart + match.range.location, length: match.range.length)
                result.addAttribute(.foregroundColor, value: color, range: absoluteRange)
                result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), range: absoluteRange)
            }
        }
    }
    return result
}
#endif

// 现实:200 条日志(logPageSize),部分含 ERROR/WARN/READY 关键字
let entries: [String] = (0..<200).map { i in
    let tag = ["connection", "adb", "scrcpy_server", "video", "audio", "control", "socks", "render", "apps", "files", "device", "other"][i % 12]
    if i % 5 == 0 {
        return "01:23:4\(i % 10)  [\(tag)]  ERROR connection failed with status \(i)"
    } else if i % 7 == 0 {
        return "01:23:4\(i % 10)  [\(tag)]  READY connected device \(i)"
    }
    return "01:23:4\(i % 10)  [\(tag)]  Message payload \(i) connecting to device"
}

// 行为守卫:两模式输出 attributed string 的文本与着色范围一致
let baseAttr = LogHighlight.build(entries)
let candAttr = renderLogs(entries)
guard baseAttr.length == candAttr.length else {
    fatalError("length mismatch: \(baseAttr.length) vs \(candAttr.length)")
}
guard baseAttr.string == candAttr.string else {
    fatalError("text mismatch")
}
// 比较每个字符的 foregroundColor(着色一致性)
let baseColors = (0..<baseAttr.length).map { baseAttr.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor }
let candColors = (0..<candAttr.length).map { candAttr.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor }
for i in 0..<baseAttr.length {
    let b = baseColors[i] ?? .textColor
    let c = candColors[i] ?? .textColor
    if b != c {
        fatalError("color mismatch at \(i): \(b) vs \(c)")
    }
}

// 计时:候选模式测候选,基线模式测基线(renderLogs 已按 MODE 分支)
let sizes = [200]
let iterations = 30
var samples: [UInt64] = []
for _ in 0..<iterations {
    let s = DispatchTime.now().uptimeNanoseconds
    _ = renderLogs(entries)
    samples.append(DispatchTime.now().uptimeNanoseconds - s)
}
samples.sort()
let median = samples[samples.count / 2]
print("METRIC log_highlight_rebuild_us=\(median / 1_000)")
print("DETAIL 200entries:\(median / 1_000)us")
SWIFT

swift_flags=()
if [[ "${MODE:-candidate}" == "baseline" ]]; then
  swift_flags+=("-D" "BASELINE")
fi
if [[ ${#swift_flags[@]} -gt 0 ]]; then
  xcrun swiftc -O "${swift_flags[@]}" \
    "$work_dir/LogHighlight.swift" \
    "$work_dir/main.swift" \
    -o "$work_dir/log-highlight-benchmark"
else
  xcrun swiftc -O \
    "$work_dir/LogHighlight.swift" \
    "$work_dir/main.swift" \
    -o "$work_dir/log-highlight-benchmark"
fi
"$work_dir/log-highlight-benchmark"