#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Screens/Views/ScreenComponents.swift").read_text(encoding="utf-8")

# Product gap: the ScreenTile header calls configured limits "stream metrics"
# but currently omits bitrate, a primary quality/bandwidth setting. The visible
# compact summary should expose resolution, FPS cap, and bitrate together.
checks = {
    "bitrate_read_from_options": r'screenMetricsText.*?let videoBitrate = device\.scrcpyOptions\.videoBitrate',
    "bitrate_in_visible_summary": r'screenMetricsText.*?metrics\.append\(videoBitrate\).*?joined\(separator: " · "\)',
    "resolution_preserved": r'screenMetricsText.*?let resolution = "\\\(width\) × \\\(height\)".*?metrics = \[resolution\]',
    "fps_cap_preserved": r'screenMetricsText.*?maxFPS > 0.*?metrics\.append\("≤\\\(maxFPS\) FPS"\)',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Guard the real rendered surface and accessible summary. Passing cannot remove
# pixel-size validation or hide the metrics from users/VoiceOver.
required = [
    "guard surface.pixelSize.width > 0, surface.pixelSize.height > 0",
    "Text(metrics)",
    '.accessibilityLabel(Text("screensStreamMetrics"))',
    ".accessibilityValue(Text(metrics))",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: rendered stream summary is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC screen_stream_summary_gaps={len(gaps)}")
print(f"METRIC screen_stream_summary_fields={3 if not gaps else 2}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
