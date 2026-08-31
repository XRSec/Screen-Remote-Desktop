#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/App/Root/SidebarComponents.swift").read_text(encoding="utf-8")

# Product gap: expanded DeviceRow combines name and status implicitly, while
# collapsed rows now use explicit label/value semantics. Expanded and collapsed
# sidebar modes should expose the same stable device-name label and status value.
checks = {
    "expanded_row_name_label": r'DeviceRow.*?\.accessibilityLabel\(Text\(device\.name\)\)',
    "expanded_row_status_value": r'DeviceRow.*?\.accessibilityValue\(Text\(statusText\)\)',
    "primary_row_semantics_on_click_target": r'sessionClickGesture.*?\.accessibilityElement\(children: \.ignore\).*?\.accessibilityLabel\(Text\(device\.name\)\).*?\.accessibilityValue\(Text\(statusText\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve visible name/status, click gestures, selection, named session/edit
# actions, hidden hover controls, and all real status branches.
required = [
    "Text(device.name)",
    "Text(statusText)",
    "sessionClickGesture(onSingleClick: action, onDoubleClick: onDoubleClick)",
    ".accessibilityAction(named: Text(sessionActionLocalizationKey), onToggleSession)",
    ".accessibilityAction(named: Text(\"sessionEditTitle\"), onEdit)",
    "session.phase.isWorking",
    "session.phase == .failed",
    "session.batteryLevel",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: expanded device-row behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC expanded_device_row_semantic_gaps={len(gaps)}")
print(f"METRIC sidebar_device_modes_consistent={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
