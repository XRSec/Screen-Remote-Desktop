#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/App/Root/SidebarComponents.swift").read_text(encoding="utf-8")

# Product gap: VirtualDeviceRow combines name and target automatically, then
# adds a state value. Use explicit label/value semantics so the device name is
# stable and the value contains target plus working/running/stopped state.
checks = {
    "virtual_name_label": r'VirtualDeviceRow.*?\.accessibilityLabel\(Text\(device\.name\)\)',
    "virtual_summary_function": r'virtualDeviceAccessibilitySummary.*?device\.target.*?isWorking.*?device\.isRunning',
    "virtual_summary_value": r'VirtualDeviceRow.*?\.accessibilityValue\(Text\(virtualDeviceAccessibilitySummary\)\)',
    "primary_children_ignored": r'VirtualDeviceRow.*?\.accessibilityElement\(children: \.ignore\).*?\.accessibilityLabel',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve visible name/target, start/stop and edit actions, working guards,
# visual status, hover behavior, and real state sources.
required = [
    "Text(device.name)",
    "Text(device.target)",
    "device.isRunning",
    "isWorking",
    ".accessibilityAction(named: Text(actionLocalizationKey))",
    '.accessibilityAction(named: Text("virtualDeviceEditTitle"))',
    "if !isWorking { action() }",
    "if !device.isRunning && !isWorking { onEdit() }",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: virtual-device row behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC virtual_device_row_semantic_gaps={len(gaps)}")
print(f"METRIC virtual_device_row_metadata_fields={3 if not gaps else 2}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
