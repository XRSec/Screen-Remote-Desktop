#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Management/Utilities/DeviceUtilitiesView.swift").read_text(encoding="utf-8")
catalog = Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8")
combined = source + "\n" + catalog

# Product gap: eight unrelated device utilities currently appear as one flat
# grid. Grouping them into system, display, and quick-action sections improves
# scanning and makes high-impact reboot/display controls easier to distinguish.
checks = {
    "system_optimization_section": r'managementSystemOptimizationSection.*?\.fixedPort.*?\.activation.*?\.animation',
    "display_controls_section": r'managementDisplayControlsSection.*?\.density.*?\.resolution',
    "quick_actions_section": r'managementQuickActionsSection.*?\.screenshot.*?\.reboot.*?\.standby',
    "localized_section_headers": r'"managementSystemOptimizationSection".*?"managementDisplayControlsSection".*?"managementQuickActionsSection"',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, combined, flags=re.S) is None]

# Guard all eight real utility destinations and their existing presentation
# path. Passing cannot drop an action or bypass present(_:).
required_cases = ["fixedPort", "screenshot", "reboot", "activation", "density", "resolution", "animation", "standby"]
missing_cases = [case for case in required_cases if f"sheet: .{case}" not in source]
required_behavior = ["Button { present(action.sheet) }", "LazyVGrid", "ForEach"]
missing_behavior = [item for item in required_behavior if item not in source]
if missing_cases or missing_behavior:
    print("Measurement invalid: utility behavior is incomplete:", file=sys.stderr)
    for item in missing_cases + missing_behavior:
        print(f"- {item}", file=sys.stderr)
    sys.exit(2)

print(f"METRIC utility_information_architecture_gaps={len(gaps)}")
print(f"METRIC utility_named_sections={3 - sum(name != 'localized_section_headers' for name in gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
