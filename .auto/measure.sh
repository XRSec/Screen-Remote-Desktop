#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Photos/PhotosView.swift").read_text(encoding="utf-8")

# Product gap: Photos loading visually shows a spinner plus Loading text, but
# unlike the already-fixed Apps state, its container is not a single coherent
# VoiceOver status. Keep visual feedback while eliminating fragmented semantics.
checks = {
    "spinner_hidden": r'if isLoading.*?ProgressView\(\).*?\.accessibilityHidden\(true\)',
    "loading_group_combined": r'if isLoading.*?VStack.*?\.accessibilityElement\(children: \.combine\).*?\.accessibilityLabel\(Text\("commonLoading"\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve actual load state, visible feedback, async scan, and error handling.
required = [
    "if isLoading",
    "ProgressView()",
    'Text("commonLoading")',
    "isLoading = true",
    "isLoading = false",
    "ManagementADB.shell",
    "errorMessage = error.localizedDescription",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Photos loading behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC photos_loading_accessibility_gaps={len(gaps)}")
print(f"METRIC photos_loading_coherent_states={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
