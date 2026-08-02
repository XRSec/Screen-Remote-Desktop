#!/bin/bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$repo/Screen-Remote"
allowlist="$repo/scripts/swift-file-size-allowlist.txt"
status=0

allowed_reason() {
    awk -F '\t' -v target="$1" '$1 == target && length($2) > 0 { print $2; exit }' "$allowlist"
}

while IFS= read -r -d '' file; do
    relative=${file#"$repo/"}
    lines=$(wc -l < "$file" | tr -d ' ')
    if (( lines > 700 )); then
        reason=$(allowed_reason "$relative")
        if [[ -n "$reason" ]]; then
            echo "warning: $relative has $lines lines (allowlisted: $reason)"
        else
            echo "error: $relative has $lines lines; split it or add a reasoned allowlist entry" >&2
            status=1
        fi
    elif (( lines > 500 )); then
        echo "warning: $relative has $lines lines; review its responsibilities"
    fi
done < <(find "$source_root" -type f -name '*.swift' -print0)

exit "$status"
