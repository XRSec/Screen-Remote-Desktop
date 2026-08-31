#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Messages/MessagesView.swift").read_text(encoding="utf-8")

# Product gap: ConversationRow is already a native Button, but its combined
# children do not provide an explicit label/value split for sender, preview,
# time, and read state. A coherent card summary improves VoiceOver scanning.
checks = {
    "row_label_is_name": r'ConversationRow.*?\.accessibilityLabel\(Text\(conversation\.name\)\)',
    "row_metadata_summary": r'conversationAccessibilitySummary.*?conversation\.preview.*?conversation\.time',
    "row_value_combines_metadata_and_state": r'ConversationRow.*?\.accessibilityValue\(Text\(conversationAccessibilitySummary\)\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve native button activation, selection, read state, visible metadata,
# compact navigation callback, and existing hint.
required = [
    "Button(action: action)",
    "Text(conversation.name)",
    "Text(conversation.preview)",
    "Text(conversation.time)",
    "conversation.unread",
    ".accessibilityHint(Text(\"messagesOpenConversationHint\"))",
    ".accessibilityAddTraits(isSelected ? .isSelected : [])",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: conversation row behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC conversation_row_semantic_gaps={len(gaps)}")
print(f"METRIC conversation_row_metadata_fields={4 if not gaps else 2}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
