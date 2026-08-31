#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Apps/Views/AppsView.swift").read_text(encoding="utf-8")

# Product gap: each summary metric is exposed as separate icon/value/label
# fragments. VoiceOver should encounter one coherent metric whose label is the
# localized meaning and whose value is the count.
checks = {
    "metric_children_combined": r'private func summaryMetric.*?HStack.*?\.accessibilityElement\(children: \.combine\)',
    "metric_label_exposed": r'private func summaryMetric.*?\.accessibilityLabel\(Text\(label\)\)',
    "metric_value_exposed": r'private func summaryMetric.*?\.accessibilityValue\(Text\(value\)\)',
    "decorative_metric_icon_hidden": r'private func summaryMetric.*?Image\(systemName: icon\).*?\.accessibilityHidden\(true\)',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve both real metrics and their connected-device count semantics.
required = [
    'label: "appsUserInstalledCount"',
    'label: "appsInstalledCount"',
    "userInstalledAppCount",
    "appManager.apps.count",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Apps summary metrics are missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC apps_summary_accessibility_gaps={len(gaps)}")
print(f"METRIC apps_summary_coherent_metrics={2 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
