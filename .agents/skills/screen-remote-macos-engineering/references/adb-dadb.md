# ADB and dadb boundary

Prefer one reusable ADB process runner and typed result. SwiftUI views must not launch or parse `Process` directly.

- Put cross-platform remote collection and stable record formats in `../external/dadb/dadb-helper/`.
- Reuse `DADBHelperRuntime`; do not create another JAR, version constant, or remote path.
- Follow `../docs/contracts/adb-helper-protocol.md` for version markers and management records.
- Preserve English low-level diagnostics and map them to localized UI summaries.
- Treat a missing vendor device field as partial data, not a page failure.
- Bound command output, timeouts, cancellation, and temporary files. Clean process/file resources on every exit.
- Keep platform presentation, cache policy, panels, and progress in the macOS app.

Direct terminal ADB remains read-only diagnostics unless explicitly authorized. Never use ADB to install or replace the app under test.
