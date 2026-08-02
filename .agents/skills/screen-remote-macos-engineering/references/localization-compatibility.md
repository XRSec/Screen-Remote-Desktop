# Localization and compatibility

Support Follow System, English, and Simplified Chinese through `Localizable.xcstrings` and the root `Locale` environment.

- Use English identifiers, comments, logs, and fallback values.
- Add English and Simplified Chinese values for every user-visible key, including accessibility, prompts, menus, transient sheets, and errors.
- Resolve runtime/transient strings through the app-aware localization path; do not silently fall back to the system locale.
- Never build bilingual conditionals or copy Android `TextPair`.

Keep macOS 11 as the deployment target. Put `if #available`, legacy alternatives, window API fallbacks, and visual fallbacks in `Platform/Compatibility/`. Feature code calls a unified wrapper. Use newer APIs on newer systems instead of globally downgrading behavior.
