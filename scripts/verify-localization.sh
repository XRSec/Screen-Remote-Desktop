#!/bin/bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
catalog="$repo/Screen-Remote/Resources/Localizable.xcstrings"
output=$(mktemp -d "${TMPDIR:-/tmp}/screen-remote-xcstrings.XXXXXX")
trap 'rm -rf "$output"' EXIT

plutil -lint "$catalog" >/dev/null
xcrun xcstringstool compile "$catalog" --output-directory "$output" --language en --language zh-Hans >/dev/null

python3 - "$repo" "$catalog" <<'PY'
import json
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
catalog_path = Path(sys.argv[2])
catalog = json.loads(catalog_path.read_text())
errors = []

for key, entry in catalog.get("strings", {}).items():
    localizations = entry.get("localizations")
    if not localizations:
        continue
    for language in ("en", "zh-Hans"):
        unit = localizations.get(language, {}).get("stringUnit", {})
        if unit.get("state") != "translated" or not unit.get("value"):
            errors.append(f"{key}: missing translated {language} value")

referenced = set()
pattern = re.compile(r'(?:localizedKey|localizedString)\(\s*"([^"]+)"')
for source in (repo / "Screen-Remote").rglob("*.swift"):
    referenced.update(pattern.findall(source.read_text()))

missing = sorted(referenced - set(catalog.get("strings", {})))
errors.extend(f"missing catalog key referenced by Swift: {key}" for key in missing)

if errors:
    print("\n".join(f"error: {error}" for error in errors), file=sys.stderr)
    raise SystemExit(1)
print(f"Localization catalog verified: {len(catalog.get('strings', {}))} keys")
PY
