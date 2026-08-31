#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Management/Utilities/DeviceUtilitiesView.swift").read_text(encoding="utf-8")

# Product gap: utility success feedback is a green label visually, but it has no
# explicit status semantics. VoiceOver users should encounter one coherent
# confirmation whose label is the localized result message.
checks = {
    "success_icon_hidden": r'if let resultMessage.*?Label\(resultMessage, systemImage: "checkmark\.circle\.fill"\).*?\.accessibilityElement\(children: \.ignore\)',
    "success_message_label": r'if let resultMessage.*?\.accessibilityLabel\(Text\(resultMessage\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve real localized result writes, visual success treatment, errors,
# progress, action execution, and result reset behavior.
required = [
    "@State private var resultMessage: String?",
    'Label(resultMessage, systemImage: "checkmark.circle.fill")',
    "resultMessage = nil",
    "resultMessage = String.localizedKey",
    "ManagementErrorBanner",
    "runShellAction",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: utility feedback behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC utility_success_feedback_gaps={len(gaps)}")
print(f"METRIC utility_success_coherent_states={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
