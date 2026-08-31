#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/App/Root/SidebarView.swift").read_text(encoding="utf-8")

# Product gap: while discovering virtual devices, the sidebar exposes a small
# progress indicator and a separate text node. The compact row should remain
# visually unchanged but present one coherent localized loading state.
checks = {
    "spinner_semantics_hidden": r'virtualDeviceViewModel\.isWorking.*?ProgressView\(\).*?\.accessibilityHidden\(true\).*?Text\("virtualDeviceStatusReadingSDK"\)',
    "loading_row_combined": r'virtualDeviceViewModel\.isWorking.*?HStack.*?\.accessibilityElement\(children: \.combine\).*?\.accessibilityLabel\(Text\("virtualDeviceStatusReadingSDK"\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve the real discovery state, visible progress/text, refresh trigger, and
# empty-device distinction. Passing cannot remove loading feedback.
required = [
    "virtualDeviceViewModel.isWorking && virtualDeviceViewModel.devices.isEmpty",
    "ProgressView()",
    'Text("virtualDeviceStatusReadingSDK")',
    "virtualDeviceViewModel.refreshDevices(virtualDeviceConfiguration)",
    'Text("virtualDeviceNoDevicesSidebar")',
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: virtual-device loading behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC virtual_device_loading_accessibility_gaps={len(gaps)}")
print(f"METRIC virtual_device_loading_coherent_states={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
