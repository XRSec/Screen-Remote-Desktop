#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("Screen-Remote/Features/Apps/Views/AppsView.swift")
source = path.read_text(encoding="utf-8")

# Product gap: both app-filter dimensions should expose their current choices
# directly as native segmented controls. Menu pickers hide state alternatives
# and add an avoidable click for a frequently repeated filtering task.
checks = {
    "visibility_filter_segmented": r'Picker\("appsTypeFilterTitle",\s*selection:\s*\$appFilter\).*?\.pickerStyle\(\.segmented\)',
    "enabled_filter_segmented": r'Picker\("appsStateFilterTitle",\s*selection:\s*\$enabledFilter\).*?\.pickerStyle\(\.segmented\)',
}

gaps = []
for name, pattern in checks.items():
    if re.search(pattern, source, flags=re.S) is None:
        gaps.append(name)

# Guard the real interaction surface: all choices and accessible group labels
# must remain present; changing the measurement cannot erase product behavior.
required = [
    "ForEach(AppVisibilityFilter.allCases)",
    "ForEach(AppEnabledFilter.allCases)",
    '.accessibilityLabel(Text("appsTypeFilterTitle"))',
    '.accessibilityLabel(Text("appsStateFilterTitle"))',
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: required filter behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC apps_filter_discoverability_gaps={len(gaps)}")
print(f"METRIC apps_filter_segmented_controls={2 - len(gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
