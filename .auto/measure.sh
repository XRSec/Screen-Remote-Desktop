#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Screens/Views/ScreenComponents.swift").read_text(encoding="utf-8")

# Product gap: the visible status text reports working phases, battery, or
# Connected, but its VoiceOver label always uses session.phase.localizationKey.
# Connected sessions can therefore announce a stale phase name instead of the
# same honest status shown on screen.
checks = {
    "shared_status_text_used_as_label": r'Text\(screenStatusText\).*?\.accessibilityLabel\(Text\(screenStatusText\)\)',
    "battery_remains_value": r'\.accessibilityValue\(\s*session\.batteryLevel\.map \{ Text\("\\\(\$0\)%"\) \} \?\? Text\(""\)\s*\)',
    "status_text_covers_working_and_connected": r'screenStatusText.*?session\.phase\.isWorking.*?session\.batteryLevel.*?sidebarDeviceConnected',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve connected-only visibility, green indicator, visible text, battery,
# phase localization for working states, and stream metric semantics.
required = [
    "if session.isConnected",
    ".fill(Color.green)",
    "Text(screenStatusText)",
    "session.phase.localizationKey",
    "session.batteryLevel",
    'String.localizedKey("sidebarDeviceConnected")',
    'Text("screensStreamMetrics")',
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: ScreenTile status behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC screen_status_semantic_gaps={len(gaps)}")
print(f"METRIC screen_status_consistent_states={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
