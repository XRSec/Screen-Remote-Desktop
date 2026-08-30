import AppKit
import SwiftUI

struct ScrcpySessionParametersMenu: View {
    @EnvironmentObject private var appState: AppState
    let deviceID: UUID
    let options: ScrcpyDeviceOptions
    let remoteSerial: String
    let controlSize: CGFloat
    let isDisabled: Bool

    var body: some View {
        ScrcpySessionParametersMenuButton(
            appState: appState,
            deviceID: deviceID,
            options: options,
            remoteSerial: remoteSerial,
            isDisabled: isDisabled
        )
        .frame(width: controlSize, height: controlSize)
        .help("screensSessionParameters")
    }
}

private struct ScrcpySessionParametersMenuButton: NSViewRepresentable {
    let appState: AppState
    let deviceID: UUID
    let options: ScrcpyDeviceOptions
    let remoteSerial: String
    let isDisabled: Bool

    func makeCoordinator() -> ScrcpySessionParametersMenuCoordinator {
        ScrcpySessionParametersMenuCoordinator(
            appState: appState,
            deviceID: deviceID,
            options: options,
            remoteSerial: remoteSerial
        )
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(ScrcpySessionParametersMenuCoordinator.showMenu(_:))
        context.coordinator.update(button, options: options, isDisabled: isDisabled)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.deviceID = deviceID
        context.coordinator.remoteSerial = remoteSerial
        context.coordinator.update(button, options: options, isDisabled: isDisabled)
    }
}

private final class ScrcpySessionParametersMenuCoordinator: NSObject {
    let appState: AppState
    var deviceID: UUID
    var remoteSerial: String
    private var options: ScrcpyDeviceOptions
    private var deviceInfoWindow: NSWindow?

    init(
        appState: AppState,
        deviceID: UUID,
        options: ScrcpyDeviceOptions,
        remoteSerial: String
    ) {
        self.appState = appState
        self.deviceID = deviceID
        self.options = options
        self.remoteSerial = remoteSerial
    }

    func update(_ button: NSButton, options: ScrcpyDeviceOptions, isDisabled: Bool) {
        self.options = options
        button.image = NSImage(
            systemSymbolName: "ellipsis.circle",
            accessibilityDescription: String.localizedKey("screensSessionParameters")
        )
        button.contentTintColor = .labelColor
        button.toolTip = String.localizedKey("screensSessionParameters")
        button.isEnabled = !isDisabled
    }

    @objc func showMenu(_ sender: NSButton) {
        let menu = makeMenu()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.height),
            in: sender
        )
    }

    private enum MenuAction {
        case maxSize(Int)
        case videoBitrate(String)
        case maxFPS(Int)
        case videoEncoder(String)
        case videoDecoder(String)
        case enableAudio(Bool)
        case audioBitrate(String)
        case audioEncoder(String)
        case audioDecoder(String)
        case audioVolume(Double)
        case compatibilityMode(Bool)
        case gameMode(Bool)
        case enableHardwareDecoding(Bool)
        case clipboardSync(Bool)
        case turnScreenOff(Bool)
        case cleanupOnDisconnect(Bool)
        case powerOffOnClose(Bool)
        case keepControllerAwake(Bool)
        case keepDeviceAwake(Bool)
        case ignoreVideoEncoderConstraints(Bool)
        case newDisplayEnabled(Bool)
        case virtualDisplaySystemDecorations(Bool)
        case preserveVirtualDisplayContent(Bool)
        case screenshot
        case deviceInfo
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
            menu.autoenablesItems = false

            addSubmenu(
            to: menu,
            titleKey: "screensImageQuality",
            menu: makeImageQualityMenu()
        )
        addSubmenu(
            to: menu,
            titleKey: "addDeviceMaxFrameRate",
            menu: makeFrameRateMenu()
        )
        addSubmenu(
            to: menu,
            titleKey: "addDeviceVideoBitrate",
            menu: makeVideoBitrateMenu()
        )
        addSubmenu(
            to: menu,
            titleKey: "addDeviceVideoSection",
            menu: makeVideoCodecMenu()
        )
        menu.addItem(.separator())
        addSubmenu(
            to: menu,
            titleKey: "sessionAudioSection",
            menu: makeAudioMenu()
        )
        addSubmenu(
            to: menu,
            titleKey: "sessionConnectionOptionsSection",
            menu: makeConnectionOptionsMenu()
        )
        addSubmenu(
            to: menu,
            titleKey: "sessionOtherOptionsSection",
            menu: makeOtherOptionsMenu()
        )
        addSubmenu(
            to: menu,
            titleKey: "sessionVirtualDisplaySection",
            menu: makeVirtualDisplayMenu()
        )
        menu.addItem(.separator())
        addChoice(
            to: menu,
            title: String.localizedKey("managementScreenshot"),
            selected: false,
            action: .screenshot
        )
        addChoice(
            to: menu,
            title: String.localizedKey("screensConnectionDebugInfo"),
            selected: false,
            action: .deviceInfo
        )
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeImageQualityMenu() -> NSMenu {
        let menu = NSMenu()
        for preset in ScreenQualityPreset.allCases {
            addChoice(
                to: menu,
                title: String.localizedKey(preset.localizationKey),
                selected: options.maxSize == preset.maxSize,
                action: .maxSize(preset.maxSize)
            )
        }
        if options.maxSize > 0 && !ScreenQualityPreset.allCases.contains(where: { $0.maxSize == options.maxSize }) {
            addChoice(
                to: menu,
                title: "\(options.maxSize)P",
                selected: true,
                action: .maxSize(options.maxSize),
                enabled: false
            )
        }
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeFrameRateMenu() -> NSMenu {
        let menu = NSMenu()
        let values = [15, 30, 60, 90, 120]
        for value in values {
            addChoice(
                to: menu,
                title: "\(value) FPS",
                selected: options.maxFPS == value,
                action: .maxFPS(value)
            )
        }
        if options.maxFPS == 0 {
            addChoice(
                to: menu,
                title: String.localizedKey("sessionDefault"),
                selected: true,
                action: .maxFPS(0)
            )
        } else if !values.contains(options.maxFPS) {
            addChoice(
                to: menu,
                title: "\(options.maxFPS) FPS",
                selected: true,
                action: .maxFPS(options.maxFPS),
                enabled: false
            )
        }
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeVideoBitrateMenu() -> NSMenu {
        let menu = NSMenu()
        let values = ["700K", "1M", "2M", "4M", "8M", "12M", "20M", "40M", "80M", "120M"]
        for value in values {
            addChoice(
                to: menu,
                title: value,
                selected: options.videoBitrate.caseInsensitiveCompare(value) == .orderedSame,
                action: .videoBitrate(value)
            )
        }
        if !options.videoBitrate.isEmpty && !values.contains(where: {
            $0.caseInsensitiveCompare(options.videoBitrate) == .orderedSame
        }) {
            addChoice(
                to: menu,
                title: options.videoBitrate,
                selected: true,
                action: .videoBitrate(options.videoBitrate),
                enabled: false
            )
        }
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeVideoCodecMenu() -> NSMenu {
        let menu = NSMenu()
        addSubmenu(
            to: menu,
            titleKey: "sessionVideoEncoder",
            menu: makeRemoteEncoderMenu(
                kind: .video,
                current: options.videoEncoder,
                action: { .videoEncoder($0) }
            )
        )
        addSubmenu(
            to: menu,
            titleKey: "sessionVideoDecoder",
            menu: makeVideoDecoderMenu()
        )
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeAudioMenu() -> NSMenu {
        let menu = NSMenu()
        addToggle(
            to: menu,
            titleKey: "addDeviceForwardAudio",
            selected: options.enableAudio,
            action: .enableAudio(!options.enableAudio),
            enabled: !options.compatibilityMode
        )
        addSubmenu(
            to: menu,
            titleKey: "sessionAudioBitrate",
            menu: makeAudioBitrateMenu(),
            enabled: options.enableAudio && !options.compatibilityMode
        )
        addSubmenu(
            to: menu,
            titleKey: "sessionAudioEncoder",
            menu: makeRemoteEncoderMenu(
                kind: .audio,
                current: options.audioEncoder,
                action: { .audioEncoder($0) }
            ),
            enabled: options.enableAudio && !options.compatibilityMode
        )
        addSubmenu(
            to: menu,
            titleKey: "sessionAudioDecoder",
            menu: makeAudioDecoderMenu(),
            enabled: options.enableAudio && !options.compatibilityMode
        )
        addSubmenu(
            to: menu,
            titleKey: "sessionAudioVolume",
            menu: makeAudioVolumeMenu(),
            enabled: options.enableAudio && !options.compatibilityMode
        )
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeAudioBitrateMenu() -> NSMenu {
        let menu = NSMenu()
        let values = ["64K", "128K", "192K", "256K"]
        for value in values {
            addChoice(
                to: menu,
                title: value,
                selected: options.audioBitrate.caseInsensitiveCompare(value) == .orderedSame,
                action: .audioBitrate(value)
            )
        }
        if !options.audioBitrate.isEmpty && !values.contains(where: {
            $0.caseInsensitiveCompare(options.audioBitrate) == .orderedSame
        }) {
            addChoice(
                to: menu,
                title: options.audioBitrate,
                selected: true,
                action: .audioBitrate(options.audioBitrate),
                enabled: false
            )
        }
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeAudioVolumeMenu() -> NSMenu {
        let menu = NSMenu()
        let values = [1.0, 1.5, 2.0, 2.5, 3.0]
        let current = min(max(options.audioVolume, 1), 3)
        for value in values {
            addChoice(
                to: menu,
                title: "\(Int(value * 100))%",
                selected: abs(current - value) < 0.001,
                action: .audioVolume(value)
            )
        }
        if !values.contains(where: { abs(current - $0) < 0.001 }) {
            addChoice(
                to: menu,
                title: "\(Int((current * 100).rounded()))%",
                selected: true,
                action: .audioVolume(current),
                enabled: false
            )
        }
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeConnectionOptionsMenu() -> NSMenu {
        let menu = NSMenu()
        addToggle(
            to: menu,
            titleKey: "sessionCompatibilityMode",
            selected: options.compatibilityMode,
            action: .compatibilityMode(!options.compatibilityMode)
        )
        addToggle(
            to: menu,
            titleKey: "sessionGameMode",
            selected: options.gameMode,
            action: .gameMode(!options.gameMode),
            enabled: !options.compatibilityMode
        )
        addToggle(
            to: menu,
            titleKey: "sessionHardwareDecoding",
            selected: options.enableHardwareDecoding,
            action: .enableHardwareDecoding(!options.enableHardwareDecoding),
            enabled: !options.compatibilityMode
        )
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeOtherOptionsMenu() -> NSMenu {
        let menu = NSMenu()
        addToggle(
            to: menu,
            titleKey: "addDeviceSyncClipboard",
            selected: options.clipboardSync,
            action: .clipboardSync(!options.clipboardSync),
            enabled: !options.compatibilityMode
        )
        addToggle(
            to: menu,
            titleKey: "addDeviceTurnScreenOff",
            selected: options.turnScreenOff,
            action: .turnScreenOff(!options.turnScreenOff),
            enabled: !options.compatibilityMode
        )
        addToggle(
            to: menu,
            titleKey: "sessionCleanupOnDisconnect",
            selected: options.cleanupOnDisconnect,
            action: .cleanupOnDisconnect(!options.cleanupOnDisconnect)
        )
        addToggle(
            to: menu,
            titleKey: "sessionPowerOffOnClose",
            selected: options.powerOffOnClose,
            action: .powerOffOnClose(!options.powerOffOnClose),
            enabled: options.cleanupOnDisconnect && !options.compatibilityMode
        )
        addToggle(
            to: menu,
            titleKey: "sessionKeepControllerAwake",
            selected: options.keepControllerAwake,
            action: .keepControllerAwake(!options.keepControllerAwake)
        )
        addToggle(
            to: menu,
            titleKey: "addDeviceKeepAwake",
            selected: options.keepDeviceAwake,
            action: .keepDeviceAwake(!options.keepDeviceAwake),
            enabled: options.cleanupOnDisconnect && !options.compatibilityMode
        )
        addToggle(
            to: menu,
            titleKey: "sessionIgnoreEncoderConstraints",
            selected: options.ignoreVideoEncoderConstraints,
            action: .ignoreVideoEncoderConstraints(!options.ignoreVideoEncoderConstraints),
            enabled: !options.compatibilityMode
        )
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeVirtualDisplayMenu() -> NSMenu {
        let menu = NSMenu()
        addToggle(
            to: menu,
            titleKey: "sessionNewDisplay",
            selected: options.newDisplayEnabled,
            action: .newDisplayEnabled(!options.newDisplayEnabled),
            enabled: !options.compatibilityMode
        )
        addToggle(
            to: menu,
            titleKey: "sessionDisplaySystemUI",
            selected: options.virtualDisplaySystemDecorations,
            action: .virtualDisplaySystemDecorations(!options.virtualDisplaySystemDecorations),
            enabled: options.newDisplayEnabled && !options.compatibilityMode
        )
        addToggle(
            to: menu,
            titleKey: "sessionPreserveDisplay",
            selected: options.preserveVirtualDisplayContent,
            action: .preserveVirtualDisplayContent(!options.preserveVirtualDisplayContent),
            enabled: options.newDisplayEnabled && !options.compatibilityMode
        )
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeRemoteEncoderMenu(
        kind: ScrcpyMediaKind,
        current: String,
        action: (String) -> MenuAction
    ) -> NSMenu {
        let menu = NSMenu()
        addChoice(
            to: menu,
            title: String.localizedKey("sessionDefault"),
            selected: current.isEmpty,
            action: action("")
        )
        let supportedCodecs: Set<String> = kind == .video
            ? ["h264", "h265"]
            : ["opus", "aac", "flac"]
        let encoders = ScrcpyCodecCapabilityCache
            .remoteEncoders(for: remoteSerial, kind: kind)
            .filter { supportedCodecs.contains($0.codec) }
            .sorted {
                if $0.codec != $1.codec { return $0.codec < $1.codec }
                if $0.acceleration.rank != $1.acceleration.rank {
                    return $0.acceleration.rank < $1.acceleration.rank
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        var displayedNames = Set<String>()
        for encoder in encoders where displayedNames.insert(encoder.name).inserted {
            addChoice(
                to: menu,
                title: "\(displayCodecName(encoder.codec)) · \(encoder.name)",
                selected: current == encoder.name,
                action: action(encoder.name)
            )
        }
        if !current.isEmpty && !displayedNames.contains(current) {
            addChoice(
                to: menu,
                title: current,
                selected: true,
                action: action(current),
                enabled: false
            )
        }
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeVideoDecoderMenu() -> NSMenu {
        let menu = NSMenu()
        addChoice(
            to: menu,
            title: String.localizedKey("sessionDefault"),
            selected: options.videoDecoder.isEmpty,
            action: .videoDecoder("")
        )
        let decoders = [
            (id: "videotoolbox.h264", title: "VideoToolbox · H264"),
            (id: "videotoolbox.hevc", title: "VideoToolbox · H265")
        ]
        var displayedIDs = Set<String>()
        for decoder in decoders {
            displayedIDs.insert(decoder.id)
            addChoice(
                to: menu,
                title: decoder.title,
                selected: options.videoDecoder == decoder.id,
                action: .videoDecoder(decoder.id)
            )
        }
        if !options.videoDecoder.isEmpty && !displayedIDs.contains(options.videoDecoder) {
            addChoice(
                to: menu,
                title: options.videoDecoder,
                selected: true,
                action: .videoDecoder(options.videoDecoder),
                enabled: false
            )
        }
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func makeAudioDecoderMenu() -> NSMenu {
        let menu = NSMenu()
        addChoice(
            to: menu,
            title: String.localizedKey("sessionDefault"),
            selected: options.audioDecoder.isEmpty,
            action: .audioDecoder("")
        )
        let decoders = coreAudioDecoderCapabilities()
        var displayedIDs = Set<String>()
        for decoder in decoders {
            displayedIDs.insert(decoder.id)
            let title = decoder.codec == "raw"
                ? "Core Audio · PCM"
                : "Core Audio · \(decoder.codec.uppercased())"
            addChoice(
                to: menu,
                title: title,
                selected: options.audioDecoder == decoder.id,
                action: .audioDecoder(decoder.id)
            )
        }
        if !options.audioDecoder.isEmpty && !displayedIDs.contains(options.audioDecoder) {
            addChoice(
                to: menu,
                title: options.audioDecoder,
                selected: true,
                action: .audioDecoder(options.audioDecoder),
                enabled: false
            )
        }
        return menu
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func displayCodecName(_ codec: String) -> String {
        switch codec.lowercased() {
        case "h264": return "H264"
        case "h265", "hevc": return "H265"
        case "opus": return "OPUS"
        case "aac": return "AAC"
        case "flac": return "FLAC"
        default: return codec.uppercased()
        }
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func addSubmenu(
        to menu: NSMenu,
        titleKey: String,
        menu submenu: NSMenu,
        enabled: Bool = true
    ) {
        let item = NSMenuItem(title: String.localizedKey(titleKey), action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.isEnabled = enabled
        menu.addItem(item)
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func addChoice(
        to menu: NSMenu,
        title: String,
        selected: Bool,
        action: MenuAction,
        enabled: Bool = true
    ) {
        let item = NSMenuItem(title: title, action: #selector(selectItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        item.state = selected ? .on : .off
        item.isEnabled = enabled
        menu.addItem(item)
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    private func addToggle(
        to menu: NSMenu,
        titleKey: String,
        selected: Bool,
        action: MenuAction,
        enabled: Bool = true
    ) {
        addChoice(
            to: menu,
            title: String.localizedKey(titleKey),
            selected: selected,
            action: action,
            enabled: enabled
        )
    }
}

private extension ScrcpySessionParametersMenuCoordinator {
    @MainActor
    @objc private func selectItem(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        if case .screenshot = action {
            if let url = appState.screenSessions.captureScreenshot(deviceID: deviceID) {
                NSWorkspace.shared.open(url)
                appState.appendSDLLog("Scrcpy screenshot saved: \(url.path)")
            } else {
                appState.appendSDLLog("Scrcpy screenshot failed: no decoded frame available")
            }
            return
        }
        if case .deviceInfo = action {
            showDeviceInformationWindow()
            return
        }
        appState.updateScreenOptions(deviceID: deviceID) { options in
            _ = applyMediaAction(action, to: &options)
                || applySessionAction(action, to: &options)
                || applyDisplayAction(action, to: &options)
        }
    }

    @MainActor
    private func showDeviceInformationWindow() {
        if let window = deviceInfoWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = ScrcpyConnectionDebugWindow(deviceID: deviceID)
            .environmentObject(appState)
            .environment(\.locale, appState.resolvedLocale)
        let width = min(max(440, appState.appWindowWidth * 0.68), 760)
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String.localizedKey("screensConnectionDebugInfo")
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(NSSize(width: width, height: 550))
        window.contentMinSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        deviceInfoWindow = window
    }

    @discardableResult
    private func applyMediaAction(
        _ action: MenuAction,
        to options: inout ScrcpyDeviceOptions
    ) -> Bool {
        switch action {
        case .maxSize(let value): options.maxSize = value
        case .videoBitrate(let value): options.videoBitrate = value
        case .maxFPS(let value): options.maxFPS = value
        case .videoEncoder(let value): options.videoEncoder = value
        case .videoDecoder(let value): options.videoDecoder = value
        case .enableAudio(let value): options.enableAudio = value
        case .audioBitrate(let value): options.audioBitrate = value
        case .audioEncoder(let value): options.audioEncoder = value
        case .audioDecoder(let value): options.audioDecoder = value
        case .audioVolume(let value): options.audioVolume = value
        default: return false
        }
        return true
    }

    @discardableResult
    private func applySessionAction(
        _ action: MenuAction,
        to options: inout ScrcpyDeviceOptions
    ) -> Bool {
        switch action {
        case .compatibilityMode(let value): options.compatibilityMode = value
        case .gameMode(let value): options.gameMode = value
        case .enableHardwareDecoding(let value): options.enableHardwareDecoding = value
        case .clipboardSync(let value): options.clipboardSync = value
        case .turnScreenOff(let value): options.turnScreenOff = value
        case .cleanupOnDisconnect(let value): options.cleanupOnDisconnect = value
        case .powerOffOnClose(let value): options.powerOffOnClose = value
        case .keepControllerAwake(let value): options.keepControllerAwake = value
        case .keepDeviceAwake(let value): options.keepDeviceAwake = value
        case .ignoreVideoEncoderConstraints(let value): options.ignoreVideoEncoderConstraints = value
        default: return false
        }
        return true
    }

    @discardableResult
    private func applyDisplayAction(
        _ action: MenuAction,
        to options: inout ScrcpyDeviceOptions
    ) -> Bool {
        switch action {
        case .newDisplayEnabled(let value): options.newDisplayEnabled = value
        case .virtualDisplaySystemDecorations(let value): options.virtualDisplaySystemDecorations = value
        case .preserveVirtualDisplayContent(let value): options.preserveVirtualDisplayContent = value
        default: return false
        }
        return true
    }
}
