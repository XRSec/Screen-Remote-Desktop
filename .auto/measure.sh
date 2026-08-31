#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import json
import re
import sys

source = Path("Screen-Remote/Features/Photos/PhotosView.swift").read_text(encoding="utf-8")
catalog = json.loads(Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]

# Product gap: while searching, the toolbar badge exposes only the filtered
# count. Users cannot tell whether that is all media or a subset of a larger
# collection. The accessibility label should state matching and total counts.
checks = {
    "count_summary_uses_search_state": r'photosCountSummary.*?searchText.*?filteredPhotos\.count.*?photos\.count',
    "badge_uses_count_summary": r'Text\("\\\(filteredPhotos\.count\)"\).*?\.accessibilityLabel\(Text\(photosCountSummary\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

for key in ("photosMediaCount", "photosFilteredMediaCount"):
    loc = catalog.get(key, {}).get("localizations", {})
    if not all(loc.get(lang, {}).get("stringUnit", {}).get("value") for lang in ("en", "zh-Hans")):
        gaps.append(f"{key}_localized")

# Preserve visible filtered count, actual filtering, total collection, and search.
required = [
    'Text("\\(filteredPhotos.count)")',
    "photos.filter",
    "filteredPhotos.count",
    "@State private var photos: [RemotePhotoItem]",
    "PageSearchField",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Photos count/search behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC photos_filter_count_honesty_gaps={len(gaps)}")
print(f"METRIC photos_filter_count_contexts={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
