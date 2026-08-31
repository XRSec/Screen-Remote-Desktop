#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import json
import re
import sys

source = Path("Screen-Remote/Features/Management/Shared/ManagementSupport.swift").read_text(encoding="utf-8")
catalog = json.loads(Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]

# Product gap: when no device exists, ManagementUnavailableView now offers Add
# Session but still says "Device connection required" and tells users to connect
# the selected device. Title/detail should match the actual no-device state.
checks = {
    "dynamic_title": r'title: hasSelectedDevice \? "managementSessionRequiredTitle" : "managementNoDeviceTitle"',
    "dynamic_detail": r'detail: hasSelectedDevice \? "managementSessionRequiredDetail" : "managementNoDeviceDetail"',
    "dynamic_action_preserved": r'actionTitle: hasSelectedDevice \? "sessionStartAction" : "addDeviceTitle"',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

for key in ("managementNoDeviceTitle", "managementNoDeviceDetail"):
    loc = catalog.get(key, {}).get("localizations", {})
    if not all(loc.get(lang, {}).get("stringUnit", {}).get("value") for lang in ("en", "zh-Hans")):
        gaps.append(f"{key}_localized")

# Preserve both recovery paths, capability check, shared component, and existing
# connected-device copy.
required = [
    "hasSelectedDevice",
    '"managementSessionRequiredTitle"',
    '"managementSessionRequiredDetail"',
    '"sessionStartAction"',
    '"addDeviceTitle"',
    "connectScreenSession",
    "showingAddDevice = true",
    "ContentUnavailableViewCompat",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: management unavailable behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC management_no_device_copy_gaps={len(gaps)}")
print(f"METRIC management_unavailable_honest_states={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
