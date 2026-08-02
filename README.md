# Screen Remote for macOS

Screen Remote is a native SwiftUI app for controlling and managing Android devices from macOS. It
combines persistent multi-device sessions, ADB-powered management tools, scrcpy screen control, and
Android Virtual Device management in one desktop experience.

The app supports macOS 11 and later, follows native macOS window and lifecycle conventions, and
provides English and Simplified Chinese interfaces with live language and appearance switching.

## Current Capabilities

- Save devices in nested groups, with prioritized TCP/IP, USB, and mDNS connection addresses for
  each device.
- Discover ADB devices, race available connection candidates, perform a device preflight, retain the
  winning connection, and refresh battery information while the session remains connected.
- Configure per-device scrcpy video, audio, clipboard, power, game-mode, and virtual-display
  options, including remote video encoder selection and automatic encoder detection.
- Browse installed apps, cache app metadata and icons, launch apps on the device or a new virtual
  display, inspect package details, force-stop, enable or disable, clear data, export APKs, and
  uninstall apps.
- Inspect device information, browse and transfer files, manage processes, configure port
  forwarding, and run common device actions through ADB.
- Locate or download ADB, scrcpy, Android command-line tools, and emulator components.
- Install and remove Android system images and create, edit, start, stop, and delete Android Virtual
  Devices.
- Persist settings and device sessions, provide light and dark appearances, expose a menu-bar entry,
  and include runtime logs and local codec diagnostics.

Notifications, messages, and photos currently provide the product UI and empty states only. They
still require a companion-side or protocol-backed data channel before they can become functional.

## Product Terminology

- **Small Window (`小窗`)**: a screen session displayed inside the **Screens** workspace.
- **Large Window (`大窗`)**: the same screen session after it is expanded from **Screens**.
- **Auxiliary Menu (`辅助菜单`)**: the transient controls and session actions shown around a Small
  Window or Large Window.

Product and user-facing documentation should use these terms consistently. Internal names such as
embedded, detached, window chrome, toolbar, or control bar may still be used when describing a
specific implementation detail.

## Architecture Today

Primary screen sessions now use the app-owned scrcpy 4.1 pipeline. The macOS project bundles its own
verified `scrcpy-server.jar`, deploys it through ADB, establishes the video, optional audio, and
control sockets in protocol order, parses official scrcpy stream metadata, and decodes H.264 through
VideoToolbox into app-owned SwiftUI surfaces. This path does not use scrcpy-mask server extensions
and does not modify scrcpy protocol behavior.

Audio sockets are currently consumed without playback, and control-message routing is the next
native-session step. App-specific virtual-display launches still use the configured scrcpy
executable temporarily. The **Screens** workspace can render native primary-session frames in Small
Windows, expand the same sessions into Large Windows, and expose transient actions through the
Auxiliary Menu.

The macOS server asset is prepared by `scripts/prepare-scrcpy-server.sh`. Existing assets are checked
against the pinned SHA-256; a missing asset is downloaded from the official scrcpy GitHub v4.1
release and verified before it is bundled. A checksum mismatch stops the build.

## Future Direction

The goal is to unify the most relevant capabilities demonstrated by **scrcpy-mask** and
**AndroLaunch** into Screen Remote, while using **KonnectMac** as a product and architecture
reference for native macOS interaction, onboarding, background device coordination, and
companion-backed features.

Reusable ADB transport, stream, forwarding, remote-helper, and device-operation capabilities should
be implemented in or shared through **dadb**. Screen Remote will continue to own the native macOS
application lifecycle, UI, windows, media rendering, input mapping, persisted product state, and
scrcpy-specific orchestration. In particular, the scrcpy video, optional audio, and control sockets
must remain ordered and lifecycle-managed by the application rather than being hidden inside the
generic ADB layer.

Reference projects will be used according to their license terms. Features and interaction models
may be reimplemented natively where direct source reuse is inappropriate.

### Near-Term Plan

1. **Refine the UI and update its content**

   - Establish a consistent visual hierarchy and component language across the sidebar, top bar,
     management pages, dialogs, and empty/error states.
   - Improve responsive layouts for compact windows and verify every affected screen in light and
     dark appearances.
   - Complete English and Simplified Chinese copy, accessibility labels, onboarding guidance, and
     explanations for tools, connections, and session options.
   - Replace remaining prototype-oriented content with state derived from real devices and clearly
     identify features that require a companion channel.

2. **Complete and harden existing features**

   - Stabilize discovery, connection racing, reconnect and disconnect behavior, process cleanup,
     timeout handling, and multi-device session state.
   - Finish the ADB-backed device information, file, app, process, port-forwarding, utility, and
     diagnostics workflows, with consistent progress, cancellation, and error reporting.
   - Improve dependency detection, guided setup, downloads, and recovery when ADB, scrcpy, Android
     SDK tools, or emulator components are unavailable.
   - Define the companion/protocol boundary required for notifications, messages, photos, clipboard,
     battery events, and background device coordination, taking lessons from KonnectMac without
     coupling these features to the UI layer.
   - Move reusable remote operations and helper protocols into dadb so the macOS app does not keep
     duplicating shell parsing and device-operation logic.

### Mid-Term Plan

1. **Complete the scrcpy presentation layer inside Screen Remote**

   - Extend the app-managed primary-session pipeline to app-specific virtual displays.
   - Harden server supervision, socket timeouts, explicit session state, and cancellation.
   - Complete dynamic-resolution presentation, synchronized audio playback, clipboard routing, and
     control messages around the existing native H.264 decode path.
   - Preserve dadb as the generic ADB transport and stream foundation while keeping scrcpy protocol
     roles and media lifecycle in the Screen Remote layer.

2. **Add configurable key mapping**

   - Introduce per-device and per-app mapping profiles with a visual editor over the live screen.
   - Support keyboard, mouse, tap, repeated tap, swipe, directional pad, and multi-touch actions,
     using scrcpy-mask as a behavioral reference.
   - Correctly transform coordinates across scaling, rotation, window resizing, and virtual
     displays, and reliably release active touches when focus or a session is lost.

3. **Unify screen management and scheduling**

   - Promote the existing multi-screen prototype into the main product after native rendering is
     available.
   - Manage physical displays, scrcpy virtual displays, app-specific displays, and emulator screens
     through one session model.
   - Coordinate connection reuse, decoding load, audio focus, active input, recovery, and cleanup
     across simultaneous sessions.
   - Allow Small Windows in **Screens** to become Large Windows and return to the shared workspace
     without restarting the underlying session.

4. **Add an About page and reorganize Settings**

   - Add an About page for version information, project links, licenses, acknowledgements, update
     status, and diagnostic entry points.
   - Restructure Settings around appearance and language, device connectivity, screen and input,
     Android SDK and emulator tooling, downloads, storage, privacy, and advanced diagnostics.
   - Surface dependency health and feature prerequisites where users make related choices instead
     of relying on raw path fields alone.

## Run from Xcode

Open `Screen-Remote.xcodeproj` in Xcode, select the **Screen-Remote** scheme, and run the app. The
deployment target is macOS 11 or later.

For local command-line development, you can also run:

```sh
make run
```

## Release Packaging

The release target archives a universal arm64 and x86_64 build and creates a versioned DMG in
`dist/`:

```sh
make release
```

The DMG includes English and Simplified Chinese installation instructions and recovery tools for
Gatekeeper launch failures. If `create-dmg` is installed, the package uses the background and icon
layout in `dmg-assets/`; otherwise it falls back to a basic `hdiutil` image.

Development builds use an `Apple Development` identity by default. For external distribution,
provide a Developer ID Application identity and a configured notarization keychain profile:

```sh
make release \
  RELEASE_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
  NOTARY_PROFILE="screen-remote-notary"
```

An unsigned test package can be produced with `RELEASE_CODE_SIGNING_ALLOWED=NO`. Unsigned packages
are not intended for public distribution.

## Third-Party Foundations

- [scrcpy](https://github.com/Genymobile/scrcpy) provides the current screen-mirroring process and
  protocol foundation.
- [dadb](https://github.com/mobile-dev-inc/dadb) provides the reusable ADB protocol and stream model
  being extended for Screen Remote's cross-device operations.
- [scrcpy-mask](https://github.com/AkiChase/scrcpy-mask) is a reference for native scrcpy media,
  control, and key-mapping behavior.
- [AndroLaunch](https://github.com/aman-senpai/AndroLaunch) is a reference for macOS device tooling,
  dependency onboarding, quick actions, and menu-bar workflows.
- [KonnectMac](https://github.com/aryarajsingh/KonnectMac) is a reference for native background
  coordination and companion-backed Android integration.
