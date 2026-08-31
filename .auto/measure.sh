#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Apps/Views/AppsView.swift").read_text(encoding="utf-8")

# Product gap: the two segmented app filters have explicit labels, but unlike
# Photos category they do not expose their current selection as a value. VoiceOver
# should hear both the filter dimension and the selected option.
checks = {
    "type_filter_value": r'Picker\("appsTypeFilterTitle", selection: \$appFilter\).*?\.accessibilityValue\(Text\(appFilter\.title\)\)',
    "state_filter_value": r'Picker\("appsStateFilterTitle", selection: \$enabledFilter\).*?\.accessibilityValue\(Text\(enabledFilter\.title\)\)',
    "labels_preserved": r'accessibilityLabel\(Text\("appsTypeFilterTitle"\)\).*?accessibilityLabel\(Text\("appsStateFilterTitle"\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve all options, selection bindings, segmented presentation, filtering,
# and fixed sizing. Passing cannot replace filters with static labels.
required = [
    "AppVisibilityFilter.allCases",
    "AppEnabledFilter.allCases",
    "selection: $appFilter",
    "selection: $enabledFilter",
    ".pickerStyle(.segmented)",
    "switch appFilter",
    "switch enabledFilter",
    ".fixedSize()",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Apps filter behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC apps_filter_value_semantic_gaps={len(gaps)}")
print(f"METRIC apps_filter_explicit_values={2 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
