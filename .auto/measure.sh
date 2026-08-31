#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Management/Shared/ManagementSupport.swift").read_text(encoding="utf-8")

# Product gap: the shared management error banner is used across seven page
# families, but VoiceOver currently relies on automatic Label child merging.
# It should expose one explicit dynamic error message without a duplicate icon.
checks = {
    "error_children_ignored": r'ManagementErrorBanner.*?Label\(message, systemImage: "exclamationmark\.triangle\.fill"\).*?\.accessibilityElement\(children: \.ignore\)',
    "dynamic_error_label": r'ManagementErrorBanner.*?\.accessibilityLabel\(Text\(message\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve dynamic message, visual warning styling, semantic tokens, and the
# shared component itself. Passing cannot replace the banner with a marker.
required = [
    "struct ManagementErrorBanner: View",
    "let message: String",
    'Label(message, systemImage: "exclamationmark.triangle.fill")',
    ".foregroundColor(.red)",
    "Color.red.opacity(0.08)",
    "AppRadius.small",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: shared management error banner is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC management_error_feedback_gaps={len(gaps)}")
print(f"METRIC management_error_coherent_states={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
