#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Apps/Views/AppsView.swift").read_text(encoding="utf-8")
match = re.search(r'else if filteredManagedApps\.isEmpty \{(.*?)\n            \} else \{\n                LazyVGrid', source, flags=re.S)
if match is None:
    print("Measurement invalid: Apps empty-state branch is missing", file=sys.stderr)
    sys.exit(2)
empty_branch = match.group(1)

# Product gap: Apps reimplements an empty/search-empty layout instead of using
# the shared ContentUnavailableViewCompat. This drifts from the app-wide header
# navigation semantics and duplicates icon/title/detail/action structure.
checks = {
    "empty_state_uses_shared_component": r'ContentUnavailableViewCompat\(',
    "empty_state_title_switch_preserved": r'ContentUnavailableViewCompat\(.*?title: appManager\.apps\.isEmpty\s*\? "appsManageEmpty"\s*:\s*"appsManageNoSearchResults"',
    "empty_state_action_switch_preserved": r'actionTitle: appManager\.apps\.isEmpty\s*\? "commonRefresh"\s*:\s*"commonClear".*?action: \{.*?loadApps.*?searchText = "".*?appFilter = \.all.*?enabledFilter = \.all',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, empty_branch, flags=re.S) is None]

# Guard both real recovery paths and honest empty/search-empty distinctions.
required = [
    '"appsManageEmpty"',
    '"appsManageNoSearchResults"',
    "appManager.loadApps(for: device, appState: appState, force: true)",
    'searchText = ""',
    "appFilter = .all",
    "enabledFilter = .all",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Apps empty-state behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC apps_empty_state_consistency_gaps={len(gaps)}")
print(f"METRIC apps_shared_empty_states={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
