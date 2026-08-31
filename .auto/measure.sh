#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("Screen-Remote/Features/Screens/Views/ScrcpySessionParametersMenu.swift")
source = path.read_text(encoding="utf-8")

# Product gap: the Auxiliary Menu button exposes only a generic label to
# VoiceOver. Users should hear the currently configured quality, FPS, and video
# bitrate before opening a menu whose purpose is to change those exact values.
checks = {
    "quality_in_accessibility_summary": r'accessibilitySummary\(options: options\).*?ScreenQualityPreset',
    "fps_in_accessibility_summary": r'accessibilitySummary\(options: options\).*?options\.maxFPS',
    "bitrate_in_accessibility_summary": r'accessibilitySummary\(options: options\).*?options\.videoBitrate',
    "summary_applied_to_button": r'button\.setAccessibilityValue\(accessibilitySummary\(options: options\)\)',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Guard the native menu and its real settings. A passing result must retain the
# interactive parameter menu rather than replacing it with benchmark markers.
required = [
    "ScrcpySessionParametersMenuButton: NSViewRepresentable",
    "button.action = #selector(ScrcpySessionParametersMenuCoordinator.showMenu(_:))",
    "makeImageQualityMenu()",
    "makeFrameRateMenu()",
    "makeVideoBitrateMenu()",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: native parameter-menu behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC screen_parameter_summary_gaps={len(gaps)}")
print(f"METRIC screen_parameter_summary_fields={3 - sum(name != 'summary_applied_to_button' for name in gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
