#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import json
import re
import sys

source = Path("Screen-Remote/Features/Apps/Views/AppsView.swift").read_text(encoding="utf-8")
catalog = json.loads(Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]
match = re.search(r'else if currentDevice == nil \{(.*?)\n        \} else \{', source, flags=re.S)
if match is None:
    print("Measurement invalid: Apps no-device branch is missing", file=sys.stderr)
    sys.exit(2)
no_device_branch = match.group(1)

# Product gap: Apps' no-device state is a custom icon/title with no recovery
# action. It should use the shared empty-state component and offer Add Session,
# just like management pages now do when no device exists.
checks = {
    "shared_no_device_state": r'ContentUnavailableViewCompat\(',
    "no_device_title_is_concise": r'title: "appsNoDeviceTitle".*?detail: "appsManageNoDevice"',
    "add_session_action": r'actionTitle: "addDeviceTitle".*?appState\.showingAddDevice = true',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, no_device_branch, flags=re.S) is None]
loc = catalog.get("appsNoDeviceTitle", {}).get("localizations", {})
if not all(loc.get(lang, {}).get("stringUnit", {}).get("value") for lang in ("en", "zh-Hans")):
    gaps.append("no_device_title_localized")

# Preserve distinction from disconnected selected device, connection recovery,
# app-manager lifecycle, and the existing no-device message.
required = [
    "currentDevice == nil",
    '"appsManageNoDevice"',
    'title: "appsSessionRequiredTitle"',
    "appState.connectScreenSession(deviceID: currentDevice.id)",
    "appManager.endManaging()",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Apps unavailable-state behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC apps_no_device_recovery_gaps={len(gaps)}")
print(f"METRIC apps_no_device_recovery_actions={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
