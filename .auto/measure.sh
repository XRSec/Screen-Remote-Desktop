#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Apps/Views/AppViewComponents.swift").read_text(encoding="utf-8")

# Product gap: PageSearchField visually uses its prompt as the field placeholder,
# but does not set an explicit accessibility label. This shared component is used
# across Apps, Diagnostics, Files, Processes, Messages, Notifications, and Photos.
checks = {
    "search_field_label": r'TextField\(searchPrompt, text: \$searchText\).*?\.accessibilityLabel\(Text\(searchPrompt\)\)',
    "clear_button_label_preserved": r'Button \{.*?searchText = "".*?\.accessibilityLabel\(Text\("commonClear"\)\)',
    "search_icon_hidden": r'Image\(systemName: "magnifyingglass"\).*?\.accessibilityHidden\(true\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve binding, placeholder, clear action, compact/wide sizing, visual icon,
# and shared styling. Passing cannot replace the search component.
required = [
    "struct PageSearchField: View",
    "@Binding var searchText: String",
    "let searchPrompt: LocalizedStringKey",
    "TextField(searchPrompt, text: $searchText)",
    'searchText = ""',
    "maxWidth: expands ? .infinity : 230",
    "AppRadius.small",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: shared search behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC shared_search_field_semantic_gaps={len(gaps)}")
print(f"METRIC shared_search_accessible_surfaces={7 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
