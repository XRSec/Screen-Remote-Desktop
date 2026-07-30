# Screen Remote macOS Development Guidelines

This file applies to the entire repository. If a subdirectory contains a more specific `AGENTS.md`, follow the rules in that file instead.

## ADB and Session Logic Reference

- Use `../Screen-Remote/Screen-Remote/` as the reference only for ADB-related logic and remote-session semantics, including protocol behavior, connection state transitions, and data meanings. Before changing those areas, inspect the corresponding Android implementation and keep user-visible behavior consistent.
- Use native macOS implementations for application lifecycle, windows, UI, settings, and system integration. These areas do not require corresponding Android inspection unless they directly affect ADB or session semantics.
- Treat the reference project only as the source of ADB and session behavior. Do not modify files under `../Screen-Remote/` unless the task explicitly requires it.

## ADB Logic Reference

- Refer to `../Screen-Remote/external/dadb/` for parts of the ADB protocol, connection, authentication, transport, and device interaction logic.
- When referencing `dadb`, reuse its protocol semantics, boundary conditions, and error-handling approach. Do not translate the Kotlin/JVM implementation line by line; keep the macOS implementation consistent with Swift concurrency, lifecycle, and error models.
- Before referencing or porting a third-party implementation, confirm its license requirements and retain all required copyright and license notices.
- Use English only for all application, debug, event, and error-detail logs by default. Logs must not change with the UI language.

## Localization and Language Switching

- The application must support English and Simplified Chinese, with three language choices: Follow System, English, and Simplified Chinese.
- Use English as the development default for source-code identifiers, logs, comments, and user-visible text. English is also the fallback language for missing translations.
- Do not scatter hard-coded English/Chinese conditionals throughout user-visible text, and do not copy `TextPair` to the macOS implementation. Use Apple's standard localization system consistently: String Catalog (`Localizable.xcstrings`), `String(localized:)`, or SwiftUI localization keys.
- Store the in-app language selection in the existing `settings.json`. Make SwiftUI respond to changes through the root view's `Locale` environment. System-level menus or system UI that cannot refresh immediately may clearly state that a restart is required.
- When adding UI, prompts, error summaries, or accessibility text, provide both English and Simplified Chinese translations and verify format arguments, plurals, and interpolation in both languages.
- When referencing Android copy, preserve meaning and terminology rather than adopting its custom bilingual text-pair implementation.

## macOS Compatibility Strategy

- The application must support macOS 11 as its minimum version. Do not raise the deployment target without explicit approval.
- Centralize compatibility handling and fallbacks for newer system APIs in dedicated compatibility files, such as `ScreenRemote/Compatibility/MacOSCompatibility.swift`, or split them by capability into separate files in that directory.
- Feature views and business logic must use unified compatibility wrappers. Keep `if #available`, legacy API alternatives, and visual fallback details in the compatibility layer whenever possible. Do not degrade implementations on every platform merely to support macOS 11.
- Continue using appropriate newer APIs on macOS 12 and later. On macOS 11, use only the minimal fallback for the affected capability. Fallbacks must preserve core functionality, data, and interaction semantics, although reasonable visual differences are acceptable.
- When introducing a new SDK API, check its availability and add a dedicated macOS 11 fallback before integrating it into feature code.

## Verification

- For ADB and session changes, verify key states and error paths against `../Screen-Remote/Screen-Remote/`.
- For ADB changes, verify connection failures, authentication, disconnection, timeouts, and data boundaries. Refer to `../Screen-Remote/external/dadb/` when necessary.
- For UI copy, check English, Simplified Chinese, and Follow System modes.
- For system APIs, confirm that both the macOS 11 fallback and the current SDK path compile. Do not eliminate availability errors by raising the minimum system version.
