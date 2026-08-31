#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import json
import re
import sys

source = Path("Screen-Remote/Features/Notifications/NotificationsView.swift").read_text(encoding="utf-8")
catalog = json.loads(Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]

# Product gap: after searching notifications, the header still announces the
# total count as though every item were visible. It should distinguish total
# content from matching results, using the same normalized query as filtering.
checks = {
    "normalized_query_source": r'normalizedSearchQuery.*?searchText\.trimmingCharacters\(in: \.whitespacesAndNewlines\)',
    "filter_uses_normalized_query": r'filteredNotifications.*?guard !normalizedSearchQuery\.isEmpty.*?localizedCaseInsensitiveContains\(normalizedSearchQuery\)',
    "count_uses_filtered_and_total": r'notificationsCountText(?=[\s\S]*?normalizedSearchQuery\.isEmpty)(?=[\s\S]*?filteredNotifications\.count)(?=[\s\S]*?appState\.notifications\.count)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

for key in ("notificationsFilteredCountOne", "notificationsFilteredCount"):
    loc = catalog.get(key, {}).get("localizations", {})
    if not all(loc.get(lang, {}).get("stringUnit", {}).get("value") for lang in ("en", "zh-Hans")):
        gaps.append(f"{key}_localized")

# Preserve actual three-field search, cards, total collection, and clear action.
required = [
    "notification.app.localizedCaseInsensitiveContains",
    "notification.title.localizedCaseInsensitiveContains",
    "notification.body.localizedCaseInsensitiveContains",
    "ForEach(filteredNotifications)",
    "appState.notifications.removeAll()",
    'action: { searchText = "" }',
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: notification search behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC notification_filter_count_gaps={len(gaps)}")
print(f"METRIC notification_filter_count_contexts={2 if not gaps else 1}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
