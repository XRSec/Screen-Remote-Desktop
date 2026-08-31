#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

apps_view = Path("Screen-Remote/Features/Apps/Views/AppsView.swift").read_text(encoding="utf-8")
components = Path("Screen-Remote/Features/Apps/Views/AppViewComponents.swift").read_text(encoding="utf-8")

# Product gap: when users enter multiple search terms, every visible app card
# should reveal why it matched in both searchable fields. Filtering alone makes
# package-name matches especially hard to locate in a dense adaptive grid.
checks = {
    "terms_forwarded_to_cards": r'ManagedAppGridItem\(.*?searchTerms:\s*searchTerms',
    "app_name_highlighted": r'highlightedText\(app\.name,\s*terms:\s*searchTerms\)',
    "package_name_highlighted": r'highlightedText\(app\.packageName,\s*terms:\s*searchTerms\)',
}

gaps = []
combined = apps_view + "\n" + components
for name, pattern in checks.items():
    if re.search(pattern, combined, flags=re.S) is None:
        gaps.append(name)

# Preserve actual search semantics and guard against a benchmark-only marker.
required = [
    "searchText.split(whereSeparator: \\.isWhitespace)",
    "allSatisfy { term in",
    "localizedCaseInsensitiveContains",
]
missing = [item for item in required if item not in combined]
if missing:
    print("Measurement invalid: searchable/highlight behavior is incomplete:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC apps_search_highlight_gaps={len(gaps)}")
highlighted_fields = sum(name not in gaps for name in ("app_name_highlighted", "package_name_highlighted"))
print(f"METRIC apps_search_highlighted_fields={highlighted_fields}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
