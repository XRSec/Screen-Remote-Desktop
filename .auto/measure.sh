#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Notifications/NotificationsView.swift").read_text(encoding="utf-8")

# Product gap: dismiss is available only through the small trailing x button.
# Exposing the same existing operation as a named card action gives VoiceOver
# users a reliable action without navigating into card internals.
checks = {
    "shared_dismiss_function": r'private func dismissNotification\(\).*?firstIndex.*?notification\.id.*?remove\(at: index\)',
    "button_uses_shared_dismiss": r'Button\(action: dismissNotification\)',
    "card_named_dismiss_action": r'\.accessibilityAction\(named: Text\("notificationsDismiss"\), dismissNotification\)',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve the real identity-based single-card removal, visible button, and list.
required = [
    "appState.notifications.firstIndex",
    "appState.notifications.remove(at: index)",
    'Image(systemName: "xmark")',
    "ForEach(filteredNotifications)",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: notification dismiss behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC notification_card_action_gaps={len(gaps)}")
print(f"METRIC notification_card_named_actions={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
