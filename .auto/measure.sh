#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import json
import re
import sys

source = Path("Screen-Remote/Features/Notifications/NotificationsView.swift").read_text(encoding="utf-8")
catalog = json.loads(Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]

# Product gap: the notifications summary says only "New notifications" even
# when records exist, so neither visual nor VoiceOver users know the actual
# count. The header should expose the current list count as a localized value.
checks = {
    "count_text_visible": r'notificationsCountText.*?appState\.notifications\.count.*?Text\(notificationsCountText\)',
    "count_header_semantics": r'Text\(notificationsCountText\).*?accessibilityAddTraits\(\.isHeader\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

for key in ("notificationsCountOne", "notificationsCount"):
    entry = catalog.get(key, {})
    loc = entry.get("localizations", {})
    if not all(loc.get(lang, {}).get("stringUnit", {}).get("value") for lang in ("en", "zh-Hans")):
        gaps.append(f"{key}_localized")

# Preserve the real notification collection, search, card rendering, and clear
# behavior. Passing cannot fabricate a count or remove notification content.
required = [
    "appState.notifications",
    "filteredNotifications",
    "ForEach(filteredNotifications)",
    "appState.notifications.removeAll()",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: notification behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC notification_count_summary_gaps={len(gaps)}")
print(f"METRIC notification_count_honest_headers={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
