#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

source = Path("Screen-Remote/Features/Messages/MessagesView.swift").read_text(encoding="utf-8")

# Product gap: message filtering trims whitespace in a local variable, while
# selection synchronization and list summaries repeatedly recompute the filter.
# A single normalized query should define filtering and search-state semantics.
checks = {
    "normalized_query_source": r'private var normalizedSearchQuery: String.*?searchText\.trimmingCharacters\(in: \.whitespacesAndNewlines\)',
    "filter_uses_normalized_query": r'filteredConversations.*?guard !normalizedSearchQuery\.isEmpty.*?localizedCaseInsensitiveContains\(normalizedSearchQuery\)',
    "list_summary_knows_search_state": r'conversationList.*?normalizedSearchQuery\.isEmpty.*?filteredConversations\.count.*?appState\.conversations\.count',
    "selection_change_uses_normalized_query": r'\.onChange\(of: normalizedSearchQuery\)',
}
gaps = [name for name, pattern in checks.items() if re.search(pattern, source, flags=re.S) is None]

# Preserve name/preview matching, selection sync, unread summary, clear action,
# compact navigation, and the underlying conversation collection.
required = [
    "conversation.name.localizedCaseInsensitiveContains",
    "conversation.preview.localizedCaseInsensitiveContains",
    "synchronizeSelectionWithFilteredConversations()",
    "messagesUnreadConversationCount",
    'action: { searchText = "" }',
    "isShowingConversation = true",
    "appState.conversations",
]
missing = [item for item in required if item not in source]
if missing:
    print("Measurement invalid: Messages search behavior is missing:", *missing, sep="\n- ", file=sys.stderr)
    sys.exit(2)

print(f"METRIC messages_search_consistency_gaps={len(gaps)}")
print(f"METRIC messages_search_consistent_consumers={4 - len(gaps)}")
if gaps:
    print("GAPS " + ",".join(gaps))
PY
