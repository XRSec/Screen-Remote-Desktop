# Verification

Choose the narrowest meaningful check, then broaden by risk.

## Static checks

```bash
scripts/check-swift-file-size.sh
scripts/check-project-structure.sh
scripts/verify-localization.sh
python3 scripts/sync-xcode-project.py --check
xcodebuild -project Screen-Remote.xcodeproj -scheme Screen-Remote -showBuildSettings >/dev/null
```

Use `plutil -lint Screen-Remote/Resources/Localizable.xcstrings` for catalog syntax. Run parser or state tests when present.

## Compile and run

- For production Swift, resources, project, ADB, or scrcpy changes, run one Debug build with the `Screen-Remote` scheme and `My Mac` destination when needed.
- Do not raise the deployment target to resolve availability errors.
- Use Xcode Run for application execution and visual verification. Do not use ADB as an app build/install/launch substitute.
- Reserve `make release` for an explicit release task; it archives, signs, packages, and may notarize.

## Manual/device checks

Require a real device for ordered socket startup, first frame, rotation/dynamic size, audio, control, disconnect/reconnect, Wi-Fi/USB latency, helper deployment, and device-mutating management actions. State exactly what was not observed.
