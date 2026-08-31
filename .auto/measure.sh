#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

sidebar = Path("Screen-Remote/App/Root/SidebarView.swift").read_text(encoding="utf-8")
components = Path("Screen-Remote/App/Root/SidebarComponents.swift").read_text(encoding="utf-8")
combined = sidebar + "\n" + components

# Product gap: collapsing the sidebar removes the visible and VoiceOver session
# status that expanded rows provide. The compact device control should retain
# connection/working/failure/battery context and the start/stop named action.
checks = {
    "snapshot_forwarded_to_collapsed_glyph": r'collapsedDeviceGlyph\(.*?let session = appState\.screenSessions\.session\(for: device\.id\)',
    "collapsed_status_value": r'collapsedDeviceGlyph.*?accessibilityValue\(Text\(collapsedSessionStatusText\(session\)\)\)',
    "collapsed_named_session_action": r'collapsedDeviceGlyph.*?accessibilityAction\(named: Text\(collapsedSessionActionKey\(session\)\)\)',
    "status_semantics_cover_real_states": r'collapsedSessionStatusText.*?phase\.isWorking.*?phase == \.failed.*?supportsBatteryInformation.*?batteryLevel',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, combined, flags=re.S) is None]

# Guard the existing compact selection/double-click behavior and expanded-row
# state source. A passing result cannot replace or remove session controls.
required = [
    "appState.selectDevice(at: index)",
    "appState.startScreenSession(deviceID: device.id)",
    "sessionManager.session(for: device.id)",
    "onToggleSession",
]
missing = [item for item in required if item not in combined]
if missing:
    print("Measurement invalid: sidebar session behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC collapsed_sidebar_session_gaps={len(gaps)}")
print(f"METRIC collapsed_sidebar_session_semantics={4 - len(gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
