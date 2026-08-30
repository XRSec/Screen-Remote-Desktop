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

### macOS Remote-Control and Device-Management Roadmap (admin-verified)

Last reviewed: 2026-08-09

1. **Add audio and video encoder/decoder parameter selection**
   - Status: 🟡 Partially complete
   - Verification result: explicit remote encoder and local decoder selectors, bundled-server
     capability discovery, cache validation, native H.264/H.265 selection, and automatic runtime
     fallback are implemented. H.264 and H.265 first frames were verified on an SM-F731B running
     Android 14. Audio playback and the full user-facing compatibility matrix remain incomplete.
   - Next action: complete audio playback and verify the encoder/decoder matrix on macOS 11 and
     current macOS releases against representative Android devices.

2. **Support seamless parameter switching during active sessions and determine whether changes should
   be persisted**
   - Status: ⚠️ In progress
   - Verification result: option changes are persisted with the device configuration; audio volume is
     applied live, while server and decoder changes use a replacement session that keeps the current
     session active until video and optional audio are ready. H.264 to H.265 replacement reached
     `VideoReady`, `Switching`, and `Completed` on an SM-F731B with both cleanup modes. Every current
     option is classified as live, restart-required, or unsupported by `SessionParameterController`.
   - Next action: validate replacement timeout, cancellation, failed codec fallback, and rapid
     consecutive updates on additional devices.

3. **Debug scroll-wheel and trackpad event handling**
   - Status: ⚠️ In progress
   - Verification result: precise and non-precise scroll normalization plus began/changed/ended and
     momentum phase preservation are implemented. Precise `-0.25` and mouse-scale `-8` control paths
     both changed the captured device screen on an SM-F731B. The device was locked during automation,
     so direction, distance, and phase behavior still need content-level verification.
   - Next action: run the event parity matrix with a physical mouse and trackpad on an unlocked,
     scrollable page and retain focused regression coverage for scrcpy fixed-point encoding.

4. **Support secondary-click actions and back navigation**
   - Status: ⚠️ In progress
   - Verification result: plain right-click now sends Android `BACK`; Shift-right-click forwards the
     secondary mouse button so contextual actions such as the SMS selection “More” menu remain
     available. The control protocol does not report whether an app consumed a secondary click, so
     an automatic “context action or Back if unhandled” fallback cannot be determined reliably.
   - Next action: verify both bindings on an unlocked SMS conversation and other apps with contextual
     secondary-click actions.

5. **Evaluate additional parameters for large-window mode**
   - Status: ⚪ Not started
   - Verification result: large-window rendering behavior exists, but dedicated parameter tuning scope is
     not yet tracked in plan text.
   - Next action: define an explicit large-window parameter audit and completion checklist.

6. **Launch directly into Screens without relying on the scrcpy binary**
   - Status: ⚠️ In progress
   - Verification result: primary session is on native scrcpy, while app-specific virtual display flow
     still references the legacy executable path.
   - Next action: finish unifying virtual-display launch to the native session model.

7. **Use a true streaming canvas for device information rendering**
   - Status: ⚪ Not started
   - Verification result: current documentation focuses on feature availability, not continuous canvas
     architecture for live management data.
   - Next action: define streaming surface contract for device info and diagnostics updates.

8. **Continue expanding the toolset**
   - Status: ⚠️ In progress
   - Verification result: core app, file, process, port-forwarding, and virtual-device tools are present.
   - Next action: keep extending tools guided by usage frequency and error telemetry.

9. **Optimize file management**
   - Status: ⚪ Not started
   - Verification result: feature coverage exists; optimization and throughput-focused UX improvements are
     not yet explicit.
   - Next action: add queue control, resume-capable transfer, and richer error taxonomy.

10. **Improve process management with dadb-based app icons and Android-compatible app names**
    - Status: 🟡 Partially complete
    - Verification result: app metadata collection through helper-backed workflows exists; normalization
      and process lifecycle binding still need completion.
    - Next action: finalize name/icon normalization and unify process representation.

11. **Complete port forwarding support**
    - Status: ✅ Done
    - Verification result: README capability list already includes port-forwarding and ADB-based workflow,
      while handoff text still includes it under hardening priorities.

12. **Improve notifications and add a session list to the notification panel**
    - Status: ⚪ Not started
    - Verification result: notifications/messages/photos are currently product UI with empty states and no
      companion protocol data channel.
    - Next action: finish protocol contract and bind notification sessions to UI list state.

13. **Reconsider the scope and naming of the Messages feature**
    - Status: ⚪ Not started
    - Verification result: Messages is documented as shell-only; no scoped product naming work is
      tracked as complete.
    - Next action: confirm naming and scope once companion protocol is ready.

14. **Defer further photo-library improvements**
    - Status: ✅ Deferred
    - Verification result: photos remain shell-only and should stay deferred until protocol/data model is
      ready.
    - Next action: keep deferred in next plan iteration and prevent scope creep.

15. **Improve Settings based on the Android implementation and remove the scrcpy file-path setting**
    - Status: ⚪ Not started
    - Verification result: no explicit completion of this migration is documented yet.
    - Next action: align settings schema with Android reference and remove direct binary path fields.

16. **Complete virtual-device startup parameters**
    - Status: ⚪ Not started
    - Verification result: virtual-device create/start/stop flows exist, but startup parameters are not
      yet fully finalized in roadmap form.
    - Next action: define and enforce full startup parameter matrix.

## Run from Xcode

Open `Screen-Remote.xcodeproj` in Xcode, select the **Screen-Remote** scheme, and run the app. The
deployment target is macOS 11 or later.

For local command-line development, you can also run:

```sh
make run
```

The session option classifier can be checked without an Android device:

```sh
make check-session-parameters
```

## Release Packaging

The release target archives an Apple Silicon arm64 build and creates a versioned DMG in `dist/`.
Intel x86_64 Macs are not supported:

```sh
make release
```

The DMG includes English and Simplified Chinese installation instructions and recovery tools for
Gatekeeper launch failures. If `create-dmg` is installed, the package uses the background and icon
layout in `assets/dmg/`; otherwise it falls back to a basic `hdiutil` image.

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
