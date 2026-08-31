#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Management/Shared/ManagementSupport.swift").read_text(encoding="utf-8")

# Product gap: ManagementUnavailableView always offers Start session. When no
# device exists that button is an enabled no-op. The recovery action should be
# Start session for a selected device, otherwise Add Session.
checks = {
    "selected_device_capability": r'ManagementUnavailableView.*?hasSelectedDevice.*?appState\.devices\.indices\.contains\(appState\.selectedDevice\)',
    "dynamic_recovery_title": r'actionTitle: hasSelectedDevice \? "sessionStartAction" : "addDeviceTitle"',
    "connect_recovery": r'if hasSelectedDevice.*?connectScreenSession\(deviceID: device\.id\)',
    "add_session_recovery": r'else.*?appState\.showingAddDevice = true',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve the shared unavailable state, connection recovery, selected-device
# bounds check, and existing localized explanation.
required = [
    "struct ManagementUnavailableView: View",
    'title: "managementSessionRequiredTitle"',
    'detail: "managementSessionRequiredDetail"',
    "appState.devices.indices.contains(appState.selectedDevice)",
    "appState.connectScreenSession(deviceID: device.id)",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: management recovery behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC management_recovery_action_gaps={len(gaps)}")
print(f"METRIC management_recovery_valid_states={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
