#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Apps/Views/AppViewComponents.swift").read_text(encoding="utf-8")

# Product gap: app-card management commands exist only in a pointer context
# menu. VoiceOver users get only the default Open action, so details, launch on
# device, enable/disable, force stop, clear data, export, and uninstall are not
# discoverable as named actions.
actions = {
    "details": ("appsManageDetails", "showDetails"),
    "launch_on_device": ("appsManageLaunchOnDevice", "launchOnDevice"),
    "toggle_enabled": ("app.isEnabled ? \"appsManageDisable\" : \"appsManageEnable\"", "toggleEnabled"),
    "force_stop": ("appsManageForceStop", "forceStop"),
    "clear_data": ("appsManageClearData", "clearData"),
    "export_apk": ("appsManageExportAPK", "exportAPK"),
    "uninstall": ("appsManageUninstall", "uninstall"),
}

gaps = []
for name, (label, handler) in actions.items():
    pattern = rf'accessibilityAction\(named: Text\([^\n]*{re.escape(label)}[^\n]*\)\).*?{handler}\(\)'
    if re.search(pattern, source, flags=re.S) is None:
        gaps.append(name)

# Guard the existing context menu, default open action, and all real handlers.
required = [
    ".contextMenu",
    ".accessibilityAction { openApp() }",
    "Button(action: showDetails)",
    "Button(action: launchOnDevice)",
    "Button(action: toggleEnabled)",
    "Button(action: forceStop)",
    "Button(action: clearData)",
    "Button(action: exportAPK)",
    "Button(action: uninstall)",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: app-card management behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC app_card_named_action_gaps={len(gaps)}")
print(f"METRIC app_card_named_actions={len(actions) - len(gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
