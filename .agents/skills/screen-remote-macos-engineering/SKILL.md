---
name: screen-remote-macos-engineering
description: Repository-scoped engineering workflow for the native Screen Remote macOS application. Use for understanding, planning, implementing, refactoring, reviewing, debugging, or verifying Swift, SwiftUI, Xcode, ADB/dadb, Android management parity, scrcpy session/media/control, VideoToolbox rendering, localization, macOS 11 compatibility, diagnostics, build, release, and large-file architecture work inside Screen-Remote-macOS.
---

# Screen Remote macOS Engineering

Work from the macOS repository's actual boundaries and load only the reference needed for the task.

## Start every task

1. Run from `Screen-Remote-macOS/`.
2. Read `AGENTS.md`, then use `../AGENTS.md` only for aggregate-repository and submodule boundaries.
3. Run:

   ```bash
   node .agents/skills/screen-remote-macos-engineering/scripts/project_probe.mjs
   ```

4. Preserve existing changes in the macOS repository, aggregate root, `../external/dadb/`, and both Wiki repositories.
5. State the owning feature/service and the narrowest acceptance checks before editing.

## Select context

- **Orient or place code:** Read `references/project-map.md`.
- **Match Android behavior:** Read `references/android-parity.md`, then inspect only the corresponding Android feature or runtime path.
- **Touch ADB, helper, files, processes, apps, forwarding, or device snapshots:** Read `references/adb-dadb.md`.
- **Touch scrcpy, sockets, server lifecycle, media, VideoToolbox, audio, control, or rendering:** Read `references/scrcpy-session.md`. Its ordering and retry rules are mandatory.
- **Change SwiftUI layout, tokens, colors, dimensions, windows, or shared components:** Read `references/swiftui-design.md` and the macOS Wiki design-system page before editing.
- **Change user-visible copy, locale switching, or platform API availability:** Read `references/localization-compatibility.md`.
- **Split or reorganize files:** Read `references/large-file-refactor.md` and `references/project-map.md`.
- **Verify code, diagnose a failure, build, or release:** Read `references/verification.md`.

## Non-negotiable rules

- Keep macOS platform behavior native. Use Android as the source of ADB/session meaning and management capability, not as a SwiftUI layout template.
- Keep views out of `Process`, socket, parser, and protocol ownership. Place reusable remote collection in dadb helper when both platforms need it.
- Establish scrcpy channels sequentially: `video`, optional `audio`, then `control`. Never parallelize channel creation.
- Use the official pinned scrcpy server without source modifications unless the task explicitly changes the upstream boundary.
- Keep application/protocol logs and diagnostics in English. Localize user-visible content through the String Catalog.
- Keep macOS 11 as the minimum target and centralize newer-API fallbacks in `Platform/Compatibility/`.
- Do not preserve obsolete data or behavior by default.
- Keep Swift files cohesive: target 400 lines, review at 500, fail at 700 unless an explicit allowlist records a concrete reason.
- Do not build or launch after every edit. Choose verification in proportion to risk.
- Do not stage, commit, push, release, mutate devices, or update unrelated submodule pointers unless the user requests that action.

## Implement incrementally

1. Identify the single source of truth and current callers.
2. Lock fragile parsing, ordering, or state behavior with a focused check when practical.
3. Change one coherent ownership slice.
4. Run the narrowest static or compile check.
5. Inspect the diff for duplicated facts, leaked localization, platform availability, stale paths, and scope growth.
6. Broaden verification only when the risk warrants it.

## Completion report

Report the behavior and architecture changed, files moved or split, checks run, device/manual verification still required, and pre-existing dirty files left untouched.
