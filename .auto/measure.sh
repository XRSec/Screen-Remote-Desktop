#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/App/Root/SidebarView.swift").read_text(encoding="utf-8")

# Product gap: expanded device rows show working/failed/connected/disconnected
# state visually, but collapsed sidebar glyphs use only the device accent color.
# A compact status overlay should preserve the same glanceable state hierarchy.
checks = {
    "status_overlay_attached": r'PhoneGlyph\(color: device\.accent, compact: true\).*?\.overlay\(.*?CollapsedSessionStatusIndicator\(session: session\).*?alignment: \.bottomTrailing',
    "working_progress_visible": r'struct CollapsedSessionStatusIndicator.*?session\.phase\.isWorking.*?ProgressView\(',
    "failed_state_visible": r'struct CollapsedSessionStatusIndicator.*?session\.phase == \.failed.*?Color\.red',
    "connected_and_idle_states_visible": r'struct CollapsedSessionStatusIndicator.*?supportsBatteryInformation.*?Color\.green.*?Color\.secondary',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve the compact glyph's existing selection, double-click launch, status
# accessibility value, and named session action. Passing cannot trade semantics
# for decoration.
required = [
    "appState.selectDevice(at: index)",
    "appState.startScreenSession(deviceID: device.id)",
    ".accessibilityValue(Text(collapsedSessionStatusText(session)))",
    ".accessibilityAction(named: Text(collapsedSessionActionKey(session)))",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: collapsed-sidebar behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC collapsed_sidebar_visual_status_gaps={len(gaps)}")
print(f"METRIC collapsed_sidebar_visual_states={4 - len(gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
