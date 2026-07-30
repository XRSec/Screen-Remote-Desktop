# Screen Remote macOS Development Guidelines

This file applies only to the `Screen-Remote-macOS/` subtree. If a subdirectory contains a more specific `AGENTS.md`, follow the more specific file as well.

## ADB and Session Logic Reference

- Use `../Screen-Remote/app/` as the Android reference only for ADB-related logic and remote-session semantics, including protocol behavior, connection state transitions, and data meanings. Before changing those areas, inspect the corresponding Android implementation and keep user-visible behavior consistent.
- Use native macOS implementations for application lifecycle, windows, UI, settings, and system integration. These areas do not require corresponding Android inspection unless they directly affect ADB or session semantics.
- Treat the Android reference project only as the source of ADB and session behavior. Do not modify files under `../Screen-Remote/` unless the task explicitly requires it.

## Backward Compatibility

- Do not preserve compatibility with older data schemas or application behavior unless the task explicitly requires it. Prefer the current product model and remove obsolete migration paths. This rule does not override the platform API availability strategy below.

## ADB Logic Reference

- Refer to `../external/dadb/` for parts of the ADB protocol, connection, authentication, transport, remote helper, and device interaction logic.
- When referencing `dadb`, reuse its protocol semantics, boundary conditions, and error-handling approach. Do not translate the Kotlin/JVM implementation line by line; keep the macOS implementation consistent with Swift concurrency, lifecycle, and error models.
- Before referencing or porting a third-party implementation, confirm its license requirements and retain all required copyright and license notices.
- Use English only for all application, debug, event, and error-detail logs by default. Logs must not change with the UI language.

## Localization and Language Switching

- The application must support English and Simplified Chinese, with three language choices: Follow System, English, and Simplified Chinese.
- Use English as the development default for source-code identifiers, logs, comments, and user-visible text. English is also the fallback language for missing translations.
- Do not scatter hard-coded English/Chinese conditionals throughout user-visible text, and do not copy `TextPair` to the macOS implementation. Use Apple's standard localization system consistently: String Catalog (`Localizable.xcstrings`), `String(localized:)`, or SwiftUI localization keys.
- Store the in-app language selection in the existing `settings.json` and make the selected language apply consistently to all application-owned, user-visible content. Enforce this through shared localization and presentation infrastructure rather than page-by-page exceptions.
- SwiftUI views should respond through the root `Locale` environment. Runtime string keys used by independently hosted or transient UI, such as prompts, help content, and system-backed presentations, must resolve through the app-aware localization path so they do not silently fall back to the macOS system language.
- Prefer complete live switching without discarding in-progress user state. If the framework cannot reliably refresh every affected surface, persist the selection and clearly tell the user that restarting the app is required to apply the language everywhere.
- When adding UI, prompts, error summaries, or accessibility text, provide both English and Simplified Chinese translations and verify format arguments, plurals, and interpolation in both languages.
- When referencing Android copy, preserve meaning and terminology rather than adopting its custom bilingual text-pair implementation.

## macOS Compatibility Strategy

- The application must support macOS 11 as its minimum version. Do not raise the deployment target without explicit approval.
- Prefer the best available system API on each macOS version. Do not globally downgrade an implementation to an older API merely because macOS 11 is supported; use the newer API on macOS 12 and later when it provides a better implementation, and provide a scoped fallback only for versions where that API is unavailable.
- Centralize compatibility handling and fallbacks for newer system APIs in dedicated compatibility files, currently `Screen-Remote/MacOSCompatibility.swift`; if the compatibility layer is later split by capability, keep those files together rather than scattering availability checks through feature views.
- Feature views and business logic must use unified compatibility wrappers. Keep `if #available`, legacy API alternatives, and visual fallback details in the compatibility layer whenever possible. Do not degrade implementations on every platform merely to support macOS 11.
- Continue using appropriate newer APIs on macOS 12 and later. On macOS 11, use only the minimal fallback for the affected capability. Fallbacks must preserve core functionality, data, and interaction semantics, although reasonable visual differences are acceptable.
- When introducing a new SDK API, check its availability and add a dedicated macOS 11 fallback before integrating it into feature code.

## Verification

- For ADB and session changes, verify key states and error paths against `../Screen-Remote/app/`.
- For ADB changes, verify connection failures, authentication, disconnection, timeouts, and data boundaries. Refer to `../external/dadb/` when necessary.
- For UI copy, check English, Simplified Chinese, and Follow System modes across normal content and transient user-visible content. Verify that the selected app language, rather than the macOS system language, is used.
- For system APIs, confirm that both the macOS 11 fallback and the current SDK path compile. Do not eliminate availability errors by raising the minimum system version.

## Subagent Model Allocation

- When a task contains a clearly bounded, low-risk coding subtask that can be completed independently, prefer delegating that part to `gpt-5.3-codex-spark` to take advantage of its speed and coding focus. Do not split work merely to use a subagent.
- Suitable delegated work includes locating code and files, investigating a local implementation, making mechanical changes limited to one or a few files, adding focused tests, organizing compiler or log errors, and independently reviewing a clearly scoped change.
- Every delegation must specify the concrete objective, permitted modification scope, relevant constraints, and expected deliverable. Subtasks may run in parallel when they are genuinely independent and will not modify the same files.
- The primary agent remains responsible for the overall approach, cross-module design, task decomposition, result integration, and final verification. Do not let `gpt-5.3-codex-spark` independently decide architectural changes, ambiguous requirements, high-risk modifications, complex concurrency or lifecycle behavior, cross-module refactors, or other problems requiring broad judgment.
- Subagents working on SwiftUI, Xcode execution, device operations, release workflows, or any other constrained area must follow every rule in this file. The primary agent must review their conclusions and changes before adopting them.

## UI Design and macOS Documentation

- Before changing SwiftUI themes, colors, corner radii, dimensions, windows, layouts, or shared components, read `../external/wiki/开发文档-专题-UI-设计.md`. Reuse its semantic hierarchy, tokens, and dual-theme acceptance criteria, but implement them with native macOS SwiftUI and `Screen-Remote/DesignSystem.swift`; do not copy Compose APIs or Android interaction structure.
- Check light and dark appearances plus compact and wide window layouts for every affected page family.
- macOS-specific implementation notes, handoff documents, and development plans may be maintained inside `Screen-Remote-macOS/`. Do not add macOS-only documentation to the repository-root `docs/` directory.

## Xcode, Computer Use, and Screenshots

- Do not build or run after every ordinary code edit. When compilation, execution, or visual verification is genuinely needed, use the Xcode `Screen-Remote` scheme with the `My Mac` destination.
- First check whether the current session provides a dedicated Xcode integration. If it does not, Computer Use may operate the already-open Xcode window for Run, status inspection, app navigation, non-sensitive in-app appearance switching, and exact application-window screenshots. Continue to use local tools for code search, file reads, edits, and refactoring.
- Multiple iOS, old DerivedData, or current macOS products may share the `Screen Remote` display name or bundle identifier. Before any UI action or screenshot, resolve the target's actual `.app` path. If the user supplies a path, use that exact path and do not target the app by display name alone.
- Prefer application-window capture so screenshots do not include unrelated windows or desktop content. Shortcut- or script-based capture must also identify the exact `Screen Remote` window.
- The app UI may connect an existing device session for verification. Without explicit authorization, do not click actions that reboot or power off the device, change the wireless-debugging port, change DPI or resolution, clear data, uninstall apps, or otherwise mutate device state. Read-only screenshots, field reads, hierarchy inspection, and dialog inspection are allowed.

## ADB and dadb Helper Boundaries

- Direct terminal ADB use follows the repository-level limits: read-only diagnostics, Logcat, screenshots, UI hierarchy inspection, and UI automation are allowed; installing, uninstalling, clearing data, directly replacing an app, or using ADB to install or launch an Android build for verification is forbidden.
- Device-information diagnostics may call an already-deployed dadb helper. Helper deployment or updates should normally be performed by the application's existing helper runtime. Only a task explicitly about helper deployment may directly operate `/data/local/tmp/dadb-helper.jar`, and it still must not install or replace the application.
- Reusable remote collection for device information, app metadata and icons, files, processes, and related management data belongs in `../external/dadb/dadb-helper/` behind dadb's stable protocol. Do not grow separate long shell-query and parser implementations in both Android and macOS.
- The macOS Xcode project already builds and bundles `dadb-helper.jar`. `Screen-Remote/DeviceAppsManager.swift` already checks its version, deploys it to `/data/local/tmp/dadb-helper.jar`, and invokes it with `app_process`. Extract and reuse that runtime for new helper consumers instead of bundling a second JAR or introducing another remote path.
- Device information should invoke `dadb.helper.ManagementSnapshotMain device` and parse the `DADB_MANAGEMENT\tDEVICE` header followed by `D\t<wireName>\t<base64 value>\t<base64 error>` records. A missing vendor field must not fail the page: preserve its English diagnostic error, omit the empty UI row, and continue rendering other fields.
- Helper diagnostics, protocol errors, app logs, event logs, and written error details must always be English. User-visible UI remains localized through the String Catalog and must not leak helper diagnostics directly.
