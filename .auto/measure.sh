#!/bin/bash
set -uo pipefail

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

if xcodebuild \
  -project Screen-Remote.xcodeproj \
  -scheme Screen-Remote \
  -destination 'platform=macOS' \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO >"$log_file" 2>&1; then
  printf 'METRIC app_card_compile_gaps=0\n'
  printf 'METRIC debug_build_success=1\n'
else
  printf 'METRIC app_card_compile_gaps=1\n'
  printf 'METRIC debug_build_success=0\n'
  grep -E 'AppViewComponents.swift:|error:|BUILD FAILED' "$log_file" | tail -n 20 >&2 || true
fi
