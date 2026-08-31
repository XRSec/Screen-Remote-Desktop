#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Photos/PhotosView.swift").read_text(encoding="utf-8")

# Product gap: filtering trims whitespace to decide whether an empty state is a
# search, but filteredPhotos uses the raw string. A query such as " photo " can
# incorrectly return no results even when "photo" matches. One normalized query
# should drive filtering, count context, and empty-state classification.
checks = {
    "normalized_query_source": r'private var normalizedSearchQuery: String.*?searchText\.trimmingCharacters\(in: \.whitespacesAndNewlines\)',
    "filter_uses_normalized_query": r'filteredPhotos.*?guard !normalizedSearchQuery\.isEmpty.*?localizedCaseInsensitiveContains\(normalizedSearchQuery\)',
    "count_uses_normalized_query": r'photosCountSummary.*?normalizedSearchQuery\.isEmpty',
    "empty_state_uses_normalized_query": r'let hasSearchQuery = !normalizedSearchQuery\.isEmpty',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve filename filtering, clear action, count summary, and source data.
required = [
    "photos.filter",
    "$0.name.localizedCaseInsensitiveContains",
    'action: { searchText = "" }',
    "photosCountSummary",
    "@State private var photos: [RemotePhotoItem]",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Photos search behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC photos_search_normalization_gaps={len(gaps)}")
print(f"METRIC photos_search_consistent_consumers={4 - len(gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
