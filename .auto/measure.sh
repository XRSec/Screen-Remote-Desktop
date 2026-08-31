#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Management/Utilities/DeviceUtilitiesView.swift").read_text(encoding="utf-8")

# Product gap: the utility page may be busy or refreshing, but the progress
# indicator only says Loading and remains separate from the page content. It
# should expose one coherent state and hide the decorative spinner semantics.
checks = {
    "spinner_hidden": r'if isBusy \|\| isRefreshing.*?ProgressView\(\).*?\.accessibilityHidden\(true\)',
    "loading_state_element": r'if isBusy \|\| isRefreshing.*?\.accessibilityElement\(children: \.ignore\).*?\.accessibilityLabel\(Text\("commonLoading"\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve both busy sources, visible progress, action disabling, snapshot
# refresh, success/error feedback, and command execution.
required = [
    "if isBusy || isRefreshing",
    "ProgressView()",
    ".disabled(isBusy)",
    "refreshSnapshot",
    "ManagementErrorBanner",
    "resultMessage",
    "runShellAction",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: utility loading behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC utility_loading_accessibility_gaps={len(gaps)}")
print(f"METRIC utility_loading_coherent_states={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
