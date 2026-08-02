# Project map

Use this reference for ownership and source placement. Confirm facts against current source and `Screen-Remote.xcodeproj/project.pbxproj`.

## Repository boundary

- This repository is the open-source native macOS client: `XRSec/Screen-Remote-macOS`.
- `../Screen-Remote/` is the private Android behavior reference.
- `../external/dadb/` owns reusable ADB transport, helper, forwarding, and remote collection.
- `../external/scrcpy/` is the official protocol/server reference; `../external/scrcpy-mask/` is a client-behavior reference only.
- Detailed macOS documentation lives in `../external/wiki-macos/`.

## Source ownership

Use one App target with physical folders matching Xcode groups:

```text
Screen-Remote/
├── App/                 app entry, root navigation, commands
├── Core/                stable models, design system, localization, logging
├── Platform/            macOS compatibility, windows, menu bar, panels
├── Services/            persistence, ADB, scrcpy, Android tooling
├── Features/            user-facing feature slices
│   ├── Devices/
│   ├── Screens/
│   ├── Apps/
│   ├── Management/
│   ├── VirtualDevices/
│   ├── Settings/
│   ├── Diagnostics/
│   ├── Tooling/
│   ├── Notifications/
│   ├── Messages/
│   └── Photos/
└── Resources/           Assets.xcassets and Localizable.xcstrings
```

Feature views own presentation and view state. Services own process, protocol, parsing, transport, and long-lived lifecycle. Core types must not depend on a feature. Platform fallbacks must not be scattered through feature views.

## High-risk runtime path

Trace screen sessions through device configuration, connection candidate resolution, ADB preflight, official scrcpy server launch, ordered sockets, metadata, decoder, frame presenter, surface/window, and cleanup. Load `scrcpy-session.md` before changing any stage.
