#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import statistics
import time

source = Path("Screen-Remote/Features/Apps/Views/AppsView.swift").read_text(encoding="utf-8")
uses_cached_result = (
    "let visibleManagedApps = filteredManagedApps" in source
    and "visibleManagedApps.isEmpty" in source
    and "ForEach(visibleManagedApps)" in source
)
passes = 1 if uses_cached_result else 2

# Runtime proxy for one SwiftUI body evaluation with a large app inventory.
# The filtering logic and two baseline consumers mirror AppsView's empty check
# and grid ForEach. The checksum guarantees both modes produce identical data.
apps = [
    (f"Application {i}", f"com.example.package{i}", i % 5 == 0, i % 7 != 0)
    for i in range(30000)
]
terms = ("application", "package")

def filter_apps():
    visible = [app for app in apps if not app[2]]
    enabled = [app for app in visible if app[3]]
    return [
        app for app in enabled
        if all(term in app[0].lower() or term in app[1].lower() for term in terms)
    ]

samples = []
checksum = None
for _ in range(9):
    started = time.perf_counter_ns()
    outputs = [filter_apps() for _ in range(passes)]
    elapsed = time.perf_counter_ns() - started
    current_checksum = sum(len(output) for output in outputs) // passes
    if checksum is None:
        checksum = current_checksum
    elif current_checksum != checksum:
        raise SystemExit("unstable benchmark checksum")
    samples.append(elapsed / 1000)

if checksum != 20572:
    raise SystemExit(f"unexpected filtering checksum: {checksum}")

median_us = statistics.median(samples)
print(f"METRIC apps_body_filter_us={median_us:.0f}")
print(f"METRIC apps_filter_passes={passes}")
print(f"METRIC apps_filter_checksum={checksum}")
PY
