#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Apps/Views/AppsView.swift").read_text(encoding="utf-8")

# Product gap: the Apps loading state exposes both an unlabeled progress
# indicator and a separate Loading text node. VoiceOver may announce duplicate,
# fragmented feedback instead of one coherent live state.
checks = {
    "decorative_spinner_hidden": r'if appManager\.isLoading.*?ProgressView\(\).*?\.accessibilityHidden\(true\).*?Text\("appsManageLoading"\)',
    "loading_group_has_single_label": r'if appManager\.isLoading.*?VStack.*?\.accessibilityElement\(children: \.combine\).*?\.accessibilityLabel\(Text\("appsManageLoading"\)\)',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve the actual manager-backed loading branch and visible localized text.
# Passing cannot remove progress feedback or replace it with a benchmark marker.
required = [
    "if appManager.isLoading",
    "ProgressView()",
    'Text("appsManageLoading")',
    "appManager.loadApps(for: device, appState: appState, force: true)",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: real Apps loading behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC apps_loading_accessibility_gaps={len(gaps)}")
print(f"METRIC apps_loading_coherent_states={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
