#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Photos/PhotosView.swift").read_text(encoding="utf-8")

# Product gap: the segmented photo-category picker has a localized visible
# label in its initializer, but segmented controls often suppress that label.
# Set an explicit accessibility label and expose the selected category value.
checks = {
    "category_label": r'Picker\("photosCategory", selection: \$selectedCategory\).*?\.accessibilityLabel\(Text\("photosCategory"\)\)',
    "category_value": r'Picker\("photosCategory", selection: \$selectedCategory\).*?\.accessibilityValue\(Text\(selectedCategory\.titleKey\)\)',
    "segmented_style_preserved": r'Picker\("photosCategory".*?\.pickerStyle\(\.segmented\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve all categories, localized option titles, selection binding, reload on
# category change, directory/depth semantics, and width.
required = [
    "PhotoCategory.allCases",
    "Text(category.titleKey).tag(category)",
    "selection: $selectedCategory",
    ".onChange(of: selectedCategory) { _ in loadPhotos() }",
    "selectedCategory.directoryPath",
    "selectedCategory.searchDepth",
    ".frame(maxWidth: 240)",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: photo-category behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC photos_category_picker_semantic_gaps={len(gaps)}")
print(f"METRIC photos_category_picker_states={1 if not gaps else 0}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
