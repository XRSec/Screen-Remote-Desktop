#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import json
import re
import sys

notifications = Path("Screen-Remote/Features/Notifications/NotificationsView.swift").read_text(encoding="utf-8")
messages = Path("Screen-Remote/Features/Messages/MessagesView.swift").read_text(encoding="utf-8")
catalog = json.loads(Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]

# Product gap: these pages intentionally have no sync channel, yet their titles
# say merely "No notifications/messages", which reads like a temporary empty
# inbox. Titles should state the unavailable capability immediately; details
# retain the explicit no-collection privacy promise.
checks = {
    "notifications_unavailable_title_used": r'title: "notificationsSyncUnavailableTitle"',
    "messages_unavailable_title_used": r'title: "messagesSyncUnavailableTitle"',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, notifications + "\n" + messages) is None]

for key in ("notificationsSyncUnavailableTitle", "messagesSyncUnavailableTitle"):
    entry = catalog.get(key, {})
    localizations = entry.get("localizations", {})
    if not all(localizations.get(lang, {}).get("stringUnit", {}).get("value") for lang in ("en", "zh-Hans")):
        gaps.append(f"{key}_localized")

# Preserve honest privacy details and the fact that there is no fabricated sync
# action. Passing cannot replace the unavailable state with fake controls.
required = [
    (notifications, 'detail: "notificationsSyncUnavailableDetail"'),
    (messages, 'detail: "messagesSyncUnavailableDetail"'),
]
missing = [item for source, item in required if item not in source]
if missing:
    print("Measurement invalid: privacy/unavailable details are missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC unavailable_sync_title_gaps={len(gaps)}")
print(f"METRIC unavailable_sync_honest_pages={2 - sum(name.endswith('_used') for name in gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
