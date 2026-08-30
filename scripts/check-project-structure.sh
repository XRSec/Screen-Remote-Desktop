#!/bin/bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$repo/Screen-Remote"

for directory in App Core Platform Services Features Resources; do
    if [[ ! -d "$source_root/$directory" ]]; then
        echo "error: missing source directory Screen-Remote/$directory" >&2
        exit 1
    fi
done

flat_swift=$(find "$source_root" -maxdepth 1 -type f -name '*.swift' -print)
if [[ -n "$flat_swift" ]]; then
    echo "error: Swift files must not be flat in Screen-Remote/:" >&2
    while IFS= read -r file; do echo "  ${file#"$repo/"}" >&2; done <<< "$flat_swift"
    exit 1
fi

python3 "$repo/scripts/sync-xcode-project.py" --check

if rg -n '\bProcess\(' "$source_root/Features" --glob '*View.swift' >/dev/null; then
    echo "error: feature View files must not create Process directly" >&2
    rg -n '\bProcess\(' "$source_root/Features" --glob '*View.swift' >&2
    exit 1
fi

echo "Project structure is valid"
