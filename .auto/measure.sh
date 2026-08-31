#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

components = Path("Screen-Remote/App/Root/SidebarComponents.swift").read_text(encoding="utf-8")
view = Path("Screen-Remote/App/Root/SidebarView.swift").read_text(encoding="utf-8")
combined = components + "\n" + view

# Product gap: section headers announce only expanded/collapsed. VoiceOver users
# should also hear how many sessions or virtual devices belong to each section,
# even while its rows are collapsed.
checks = {
    "header_accepts_count": r'SidebarSectionHeader.*?let itemCount: Int',
    "header_exposes_count_value": r'SidebarSectionHeader.*?accessibilityValue\(Text\(sectionSummary\)\)',
    "session_count_forwarded": r'title: "sidebarSessions".*?itemCount: appState\.visibleDeviceOffsets\(\)\.count',
    "virtual_count_forwarded": r'title: "sidebarVirtualDevices".*?itemCount: virtualDeviceViewModel\.devices\.count',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, combined, flags=re.S) is None]

# Guard both section toggles, add actions, and the actual row collections.
required = [
    "sessionsExpanded.toggle()",
    "virtualDevicesExpanded.toggle()",
    "appState.showingAddDevice = true",
    "appState.openVirtualDeviceCreator()",
    "appState.visibleDeviceOffsets()",
    "virtualDeviceViewModel.devices",
]
missing = [item for item in required if item not in combined]
if missing:
    print("Measurement invalid: sidebar section behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC sidebar_section_summary_gaps={len(gaps)}")
print(f"METRIC sidebar_counted_sections={2 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
