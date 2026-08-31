#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Screens/Views/ScreenComponents.swift").read_text(encoding="utf-8")

# Product gap: compact ScreenTile headers hide the entire stream summary. The
# full text cannot fit, but VoiceOver should still expose configured stream
# metrics so compact layouts do not lose quality/FPS/bitrate information.
checks = {
    "metrics_semantics_outside_visual_condition": r'if isCompact, let metrics = screenMetricsText.*?Color\.clear.*?\.accessibilityLabel\(Text\("screensStreamMetrics"\)\).*?\.accessibilityValue\(Text\(metrics\)\)',
    "compact_visual_text_still_guarded": r'if !isCompact, let metrics = screenMetricsText',
    "metrics_group_label": r'HStack\(spacing: 6\).*?\.accessibilityLabel\(Text\("screensStreamMetrics"\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve actual pixel-size/config summary and the compact visual constraint.
required = [
    "guard surface.pixelSize.width > 0, surface.pixelSize.height > 0",
    "device.scrcpyOptions.maxFPS",
    "device.scrcpyOptions.videoBitrate",
    "if !isCompact, let metrics = screenMetricsText",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: ScreenTile metric behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC compact_screen_metric_semantic_gaps={len(gaps)}")
print(f"METRIC compact_screen_metric_semantics={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
