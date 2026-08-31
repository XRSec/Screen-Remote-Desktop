#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

root = Path("Screen-Remote/App/Root/RootView.swift").read_text(encoding="utf-8")
catalog = Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8")
combined = root + "\n" + catalog

# Product gap: the global refresh button is currently enabled in Screens,
# Notifications, and Messages even though none of those workspaces subscribes
# to its refresh event. A visible enabled no-op is misleading; refresh should
# be available only where a real reload path exists.
checks = {
    "explicit_refreshable_workspaces": r'refreshableSections.*?\.deviceInfo.*?\.utilities.*?\.files.*?\.apps.*?\.processes.*?\.portForward.*?\.photos',
    "unsupported_workspaces_disabled": r'isWorkspaceRefreshable.*?refreshableSections\.contains\(appState\.selection\).*?isRefreshEnabled\s*=\s*isWorkspaceRefreshable',
    "dispatch_matches_capability": r'switch appState\.selection.*?case \.apps:.*?refreshSelectedDeviceApps.*?case \.deviceInfo, \.utilities, \.files, \.processes, \.portForward, \.photos:.*?screenRemoteRefreshManagement.*?default:',
    "localized_unavailable_hint": r'topBarRefreshUnavailable.*?Refresh isn.*?available.*?当前工作区.*?刷新',
}

gaps = [name for name, pattern in checks.items() if re.search(pattern, combined, flags=re.S) is None]

# Preserve each real receiver and the apps-specific reload. Passing cannot
# disable refresh globally or remove working reload paths.
required = [
    "appState.refreshSelectedDeviceApps()",
    "NotificationCenter.default.post(name: .screenRemoteRefreshManagement, object: nil)",
]
receivers = [
    "DeviceInformationView.swift",
    "DeviceUtilitiesView.swift",
    "DeviceFilesView.swift",
    "DeviceProcessesView.swift",
    "PortForwardView.swift",
    "PhotosView.swift",
]
missing = [item for item in required if item not in root]
for filename in receivers:
    matches = list(Path("Screen-Remote").rglob(filename))
    if not matches or ".screenRemoteRefreshManagement" not in matches[0].read_text(encoding="utf-8"):
        missing.append(filename)
if missing:
    print("Measurement invalid: real refresh behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC topbar_refresh_honesty_gaps={len(gaps)}")
print(f"METRIC topbar_refresh_supported_workspaces={7 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
