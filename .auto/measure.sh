#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import json
import re
import sys

source = Path("Screen-Remote/App/Root/SidebarComponents.swift").read_text(encoding="utf-8")
catalog = json.loads(Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]

# Product gap: Sidebar section summaries always say "items", including a count
# of one. Use a dedicated singular summary so VoiceOver receives natural,
# grammatically correct expanded/collapsed counts.
checks = {
    "singular_branch": r'sectionSummary.*?itemCount == 1.*?sidebarSectionSummaryOne.*?sidebarSectionSummary',
    "state_preserved_in_singular": r'let expansionState = String\.localizedKey\(.*?isExpanded \? "commonExpanded" : "commonCollapsed".*?sidebarSectionSummaryOne.*?expansionState',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

for key in ("sidebarSectionSummaryOne", "sidebarSectionSummary"):
    loc = catalog.get(key, {}).get("localizations", {})
    if not all(loc.get(lang, {}).get("stringUnit", {}).get("value") for lang in ("en", "zh-Hans")):
        gaps.append(f"{key}_localized")

# Preserve the dynamic expansion state, real item count, header button, add
# action, and both existing section call sites.
required = [
    "let isExpanded: Bool",
    "let itemCount: Int",
    "Button(action: onToggle)",
    "Button(action: onAdd)",
    ".accessibilityValue(Text(sectionSummary))",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: sidebar section semantics are missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC sidebar_section_plural_gaps={len(gaps)}")
print(f"METRIC sidebar_section_count_forms={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
