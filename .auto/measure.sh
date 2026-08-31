#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Screens/Views/ScreenComponents.swift").read_text(encoding="utf-8")

# Product gap: when battery is available, screenStatusText becomes "80%" and is
# used as both accessibility label and value, duplicating battery while losing
# the Connected state. Keep visual battery text, but separate semantic status.
checks = {
    "separate_accessibility_status": r'screenAccessibilityStatusText.*?session\.phase\.isWorking.*?sidebarDeviceConnected',
    "status_label_uses_semantic_text": r'\.accessibilityLabel\(Text\(screenAccessibilityStatusText\)\)',
    "battery_only_in_value": r'\.accessibilityValue\(\s*session\.batteryLevel\.map \{ Text\("\\\(\$0\)%"\) \} \?\? Text\(""\)\s*\)',
    "visual_battery_preserved": r'screenStatusText.*?session\.batteryLevel\.map \{ "\\\(\$0\)%" \}',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve working phase semantics, visible battery, connected fallback, and
# connected-only rendering. Passing cannot remove useful status information.
required = [
    "if session.isConnected",
    "Text(screenStatusText)",
    "session.phase.isWorking",
    "session.phase.localizationKey",
    "session.batteryLevel",
    'String.localizedKey("sidebarDeviceConnected")',
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: ScreenTile status information is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC screen_status_battery_semantic_gaps={len(gaps)}")
print(f"METRIC screen_status_distinct_fields={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
