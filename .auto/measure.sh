#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/App/Root/SidebarComponents.swift").read_text(encoding="utf-8")

# Product gap: SidebarSectionHeader's toggle button has a value but no explicit
# label or header trait. VoiceOver should identify the section name as a heading
# and expose its expanded/count summary on the same control.
checks = {
    "toggle_has_title_label": r'Button\(action: onToggle\).*?\.accessibilityLabel\(Text\(title\)\)',
    "toggle_has_header_trait": r'Button\(action: onToggle\).*?\.accessibilityAddTraits\(\.isHeader\)',
    "toggle_keeps_summary_value": r'Button\(action: onToggle\).*?\.accessibilityValue\(Text\(sectionSummary\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve visual title/chevron, expansion state/count, toggle and add actions,
# plus the independent add-button label.
required = [
    "Text(title)",
    "isExpanded ? \"chevron.down\" : \"chevron.right\"",
    "sectionSummary",
    "Button(action: onToggle)",
    "Button(action: onAdd)",
    ".accessibilityLabel(addHelp)",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: sidebar section header behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC sidebar_header_navigation_gaps={len(gaps)}")
print(f"METRIC sidebar_navigable_headers={2 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
