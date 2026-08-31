#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Apps/Views/AppViewComponents.swift").read_text(encoding="utf-8")

# Product gap: app cards are disabled while busy/launching, but their seven
# named management actions remain attached by a modifier that knows only
# enabled state. Disabled cards should not advertise actions they cannot run.
checks = {
    "modifier_accepts_availability": r'ManagedAppAccessibilityActions.*?let actionsAvailable: Bool',
    "card_passes_availability": r'ManagedAppAccessibilityActions\(.*?actionsAvailable: !isBusy && !isLaunchingApp',
    "actions_conditionally_exposed": r'func body\(content: Content\).*?if actionsAvailable.*?accessibilityAction\(named:',
    "disabled_state_preserved": r'\.disabled\(isBusy \|\| isLaunchingApp\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve all seven real actions, default open action, state values, and the
# busy/launching overlay. Passing cannot remove functionality to hide the gap.
required = [
    'Text("appsManageDetails")',
    'Text("appsManageLaunchOnDevice")',
    "toggleEnabled()",
    "forceStop()",
    "clearData()",
    "exportAPK()",
    "uninstall()",
    ".accessibilityAction { openApp() }",
    "isBusy || isLaunchingApp",
    'Text("appsManageLaunching")',
    'Text("commonLoading")',
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: app-card state/actions are missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC app_card_action_availability_gaps={len(gaps)}")
print(f"METRIC app_card_action_availability_states={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
