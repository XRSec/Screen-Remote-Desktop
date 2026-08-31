#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import json
import re
import sys

source = Path("Screen-Remote/Features/Photos/PhotosView.swift").read_text(encoding="utf-8")
catalog = json.loads(Path("Screen-Remote/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]

# Product gap: media cards visually show filename, size, date, and video type,
# but their combined VoiceOver output has no explicit media type label/value.
# A named accessibility value should preserve all four facts coherently.
checks = {
    "card_summary_function": r'photoAccessibilitySummary\(_ item: RemotePhotoItem\).*?item\.isVideo.*?item\.sizeText.*?item\.dateText',
    "card_summary_applied": r'photoGridCard.*?\.accessibilityValue\(Text\(photoAccessibilitySummary\(item\)\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

for key in ("photosMediaTypeImage", "photosMediaTypeVideo", "photosMediaAccessibilitySummary"):
    loc = catalog.get(key, {}).get("localizations", {})
    if not all(loc.get(lang, {}).get("stringUnit", {}).get("value") for lang in ("en", "zh-Hans")):
        gaps.append(f"{key}_localized")

# Preserve real card content, selection, download, delete, and parsed metadata.
required = [
    "Text(item.name)",
    "Text(item.sizeText)",
    "Text(item.dateText)",
    "item.isVideo",
    "downloadPhoto(item)",
    "confirmDelete(item)",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Photos card behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC photo_card_metadata_semantic_gaps={len(gaps)}")
print(f"METRIC photo_card_metadata_fields={4 if not gaps else 3}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
