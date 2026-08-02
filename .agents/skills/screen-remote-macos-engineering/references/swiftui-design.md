# SwiftUI and design system

Read `../external/wiki-macos/UI-Design-System.md` before visual changes.

- Use semantic tokens and shared components from `Core/DesignSystem/`.
- Preserve restrained utility hierarchy: page surface, 12-point cards, 38-point compact controls, 18-point control radius, low/no card shadow, semantic badges, and clear dividers.
- Use one-column compact layouts and wider adaptive grids where macOS space improves scanning.
- Keep terminal surfaces intentionally dark; do not spread terminal colors into normal cards.
- Give destructive or device-mutating actions an explicit localized confirmation that names the target and effect.
- Check light/dark appearance, compact/wide windows, keyboard focus, VoiceOver labels, empty/loading/error states, sheets, and long bilingual strings.

Do not add hard-coded colors, radii, or spacing when an existing token expresses the same role.
