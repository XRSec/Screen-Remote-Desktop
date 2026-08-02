import AppKit
import SwiftUI

private let managementCardColumns = [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 14)]
private let managementCardGridMaxWidth: CGFloat = 914

private enum DeviceUtilitySheet: String, Identifiable {
    case fixedPort
    case screenshot
    case reboot
    case activation
    case density
    case resolution
    case animation
    case standby

    var id: String { rawValue }
}

private struct DeviceUtilityItem: Identifiable {
    let sheet: DeviceUtilitySheet
    let title: LocalizedStringKey
    let icon: String
    let detail: String

    var id: DeviceUtilitySheet { sheet }
}

private struct DeviceUtilitySnapshot {
    var wirelessPort = ""
    var density = ""
    var resolutionWidth = ""
    var resolutionHeight = ""
    var windowAnimationScale = "1.0"
    var transitionAnimationScale = "1.0"
    var animatorDurationScale = "1.0"
    var installedActivationPackages: Set<String> = []
}

private struct DeviceActivationTarget: Identifiable {
    let id: String
    let title: String
    let command: String
}

struct DeviceUtilitiesView: View {
    @EnvironmentObject private var appState: AppState
    let isCompact: Bool
    @State private var isBusy = false
    @State private var isRefreshing = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var activeSheet: DeviceUtilitySheet?
    @State private var snapshot = DeviceUtilitySnapshot()
    @State private var fixedPort = "5555"
    @State private var density = ""
    @State private var resolutionWidth = ""
    @State private var resolutionHeight = ""
    @State private var windowAnimationScale = "1.0"
    @State private var transitionAnimationScale = "1.0"
    @State private var animatorDurationScale = "1.0"
    @State private var screenshotURL: URL?

    private var actions: [DeviceUtilityItem] {
        [
            DeviceUtilityItem(
                sheet: .fixedPort,
                title: "managementFixedPort",
                icon: "wifi",
                detail: snapshot.wirelessPort.isEmpty
                    ? String.localizedKey("managementFixedPortDetail")
                    : String(format: String.localizedKey("managementCurrentPort"), snapshot.wirelessPort)
            ),
            DeviceUtilityItem(
                sheet: .screenshot,
                title: "managementScreenshot",
                icon: "camera",
                detail: String.localizedKey("managementScreenshotPreviewDetail")
            ),
            DeviceUtilityItem(
                sheet: .reboot,
                title: "managementAdvancedReboot",
                icon: "restart",
                detail: String.localizedKey("managementAdvancedRebootDetail")
            ),
            DeviceUtilityItem(
                sheet: .activation,
                title: "managementActivateApp",
                icon: "checkmark.shield",
                detail: String.localizedKey("managementActivateAppDetail")
            ),
            DeviceUtilityItem(
                sheet: .density,
                title: "managementChangeDensity",
                icon: "textformat.size",
                detail: snapshot.density.isEmpty
                    ? String.localizedKey("managementChangeDensityDetail")
                    : String(format: String.localizedKey("managementCurrentDensity"), snapshot.density)
            ),
            DeviceUtilityItem(
                sheet: .resolution,
                title: "managementChangeResolution",
                icon: "rectangle.arrowtriangle.2.outward",
                detail: snapshot.resolutionWidth.isEmpty
                    ? String.localizedKey("managementChangeResolutionDetail")
                    : String(format: String.localizedKey("managementCurrentResolution"), snapshot.resolutionWidth, snapshot.resolutionHeight)
            ),
            DeviceUtilityItem(
                sheet: .animation,
                title: "managementAnimationScale",
                icon: "slider.horizontal.3",
                detail: String.localizedKey("managementAnimationScaleDetail")
            ),
            DeviceUtilityItem(
                sheet: .standby,
                title: "managementStandby",
                icon: "moon.zzz",
                detail: String.localizedKey("managementStandbyActionsDetail")
            )
        ]
    }

    var body: some View {
        ScrollView {
            if managementTarget(from: appState) == nil { ManagementUnavailableView() }
            else {
                VStack(alignment: .leading, spacing: 16) {
                    if isBusy || isRefreshing { ProgressView().frame(maxWidth: .infinity) }
                    if let errorMessage { ManagementErrorBanner(message: errorMessage) }
                    if let resultMessage {
                        Label(resultMessage, systemImage: "checkmark.circle.fill").foregroundColor(.green).padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading).appCard()
                    }
                    LazyVGrid(columns: managementCardColumns, alignment: .center, spacing: 14) {
                        ForEach(actions) { action in
                            Button { present(action.sheet) } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: action.icon).font(.title3).foregroundColor(AppTheme.accent).frame(width: 38, height: 38)
                                        .appBackground(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(action.title).font(.headline)
                                        Text(action.detail).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                }.padding(14).appCard(radius: 12)
                            }.buttonStyle(.plain).disabled(isBusy)
                        }
                    }
                    .frame(maxWidth: managementCardGridMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                }.padding(isCompact ? 20 : 28)
            }
        }
        .onAppear(perform: refreshSnapshot)
        .onChange(of: appState.selectedDevice) { _ in refreshSnapshot() }
        .onChange(of: managementTarget(from: appState)?.serial ?? "") { serial in
            if !serial.isEmpty { refreshSnapshot() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenRemoteRefreshManagement)) { _ in
            refreshSnapshot()
        }
        .sheet(item: $activeSheet) { sheet in
            utilitySheet(sheet)
                .environment(\.locale, appState.resolvedLocale)
        }
    }

    private func present(_ sheet: DeviceUtilitySheet) {
        resultMessage = nil
        errorMessage = nil
        switch sheet {
        case .fixedPort:
            fixedPort = snapshot.wirelessPort.isEmpty ? "5555" : snapshot.wirelessPort
        case .density:
            density = snapshot.density
        case .resolution:
            resolutionWidth = snapshot.resolutionWidth
            resolutionHeight = snapshot.resolutionHeight
        case .animation:
            windowAnimationScale = snapshot.windowAnimationScale
            transitionAnimationScale = snapshot.transitionAnimationScale
            animatorDurationScale = snapshot.animatorDurationScale
        case .screenshot:
            captureScreenshot()
            return
        default:
            break
        }
        activeSheet = sheet
    }

    @ViewBuilder
    private func utilitySheet(_ sheet: DeviceUtilitySheet) -> some View {
        VStack(spacing: 0) {
            UtilitySheetHeader(title: sheetTitle(sheet)) { activeSheet = nil }
            Divider()
            Group {
                switch sheet {
                case .fixedPort: fixedPortSheet
                case .screenshot: screenshotSheet
                case .reboot: rebootSheet
                case .activation: activationSheet
                case .density: densitySheet
                case .resolution: resolutionSheet
                case .animation: animationSheet
                case .standby: standbySheet
                }
            }
            .padding(20)
        }
        .frame(width: min(500, max(420, appState.appWindowWidth * 0.62)))
        .background(AppTheme.background)
    }

    private func sheetTitle(_ sheet: DeviceUtilitySheet) -> LocalizedStringKey {
        switch sheet {
        case .fixedPort: "managementFixedPort"
        case .screenshot: "managementScreenshotReady"
        case .reboot: "managementAdvancedReboot"
        case .activation: "managementActivateApp"
        case .density: "managementChangeDensity"
        case .resolution: "managementChangeResolution"
        case .animation: "managementAnimationScale"
        case .standby: "managementStandby"
        }
    }

    private var fixedPortSheet: some View {
        UtilityForm(
            detail: "managementFixedPortWarning",
            primaryTitle: "managementApply",
            primaryEnabled: validPort != nil && fixedPort != snapshot.wirelessPort,
            primaryAction: { runFixedPort() }
        ) {
            UtilityTextField(title: "managementDevicePort", text: $fixedPort)
        }
    }

    private var densitySheet: some View {
        UtilityForm(
            detail: "managementChangeDensityDetail",
            primaryTitle: "managementApply",
            primaryEnabled: validDensity != nil && density != snapshot.density,
            primaryAction: { runShellAction("density", command: "wm density \(validDensity!)", refreshAfter: true) },
            secondaryTitle: "managementReset",
            secondaryAction: { runShellAction("densityReset", command: "wm density reset", refreshAfter: true) }
        ) {
            UtilityTextField(title: "managementDensityValue", text: $density)
        }
    }

    private var resolutionSheet: some View {
        UtilityForm(
            detail: "managementChangeResolutionDetail",
            primaryTitle: "managementApply",
            primaryEnabled: validResolution != nil && (
                resolutionWidth != snapshot.resolutionWidth ||
                resolutionHeight != snapshot.resolutionHeight
            ),
            primaryAction: {
                guard let size = validResolution else { return }
                runShellAction("resolution", command: "wm size \(size.0)x\(size.1)", refreshAfter: true)
            },
            secondaryTitle: "managementReset",
            secondaryAction: { runShellAction("resolutionReset", command: "wm size reset", refreshAfter: true) }
        ) {
            HStack(spacing: 12) {
                UtilityTextField(title: "managementWidth", text: $resolutionWidth)
                UtilityTextField(title: "managementHeight", text: $resolutionHeight)
            }
        }
    }

    private var animationSheet: some View {
        UtilityForm(
            detail: "managementAnimationScaleDetail",
            primaryTitle: "managementApply",
            primaryEnabled: validAnimationScales != nil && (
                windowAnimationScale != snapshot.windowAnimationScale ||
                transitionAnimationScale != snapshot.transitionAnimationScale ||
                animatorDurationScale != snapshot.animatorDurationScale
            ),
            primaryAction: {
                guard let scales = validAnimationScales else { return }
                let command = "settings put global window_animation_scale \(scales.0); settings put global transition_animation_scale \(scales.1); settings put global animator_duration_scale \(scales.2)"
                runShellAction("animationScale", command: command, refreshAfter: true)
            }
        ) {
            UtilityTextField(title: "managementWindowAnimationScale", text: $windowAnimationScale)
            UtilityTextField(title: "managementTransitionAnimationScale", text: $transitionAnimationScale)
            UtilityTextField(title: "managementAnimatorDurationScale", text: $animatorDurationScale)
        }
    }

    private var rebootSheet: some View {
        UtilityOptionList(detail: "managementAdvancedRebootWarning") {
            UtilityOptionButton(title: "managementRestart", icon: "restart") { runReboot(mode: "normal") }
            UtilityOptionButton(title: "managementPowerOff", icon: "power", isDestructive: true) { runReboot(mode: "powerOff") }
            UtilityOptionButton(title: "managementRecovery", icon: "cross.case", isDestructive: true) { runReboot(mode: "recovery") }
            UtilityOptionButton(title: "managementFastboot", icon: "terminal", isDestructive: true) { runReboot(mode: "fastboot") }
        }
    }

    private var standbySheet: some View {
        UtilityOptionList(detail: "managementStandbyActionsDetail") {
            UtilityOptionButton(title: "managementSleep", icon: "moon.zzz") {
                runShellAction("sleep", command: "input keyevent 223")
            }
            UtilityOptionButton(title: "managementWake", icon: "sun.max") {
                runShellAction("wake", command: "input keyevent 224")
            }
        }
    }

    private var activationSheet: some View {
        UtilityOptionList(detail: "managementActivateAppDetail") {
            ForEach(activationTargets) { target in
                UtilityOptionButton(
                    titleText: target.title,
                    icon: "checkmark.shield",
                    badge: snapshot.installedActivationPackages.contains(target.id)
                        ? String.localizedKey("managementInstalled")
                        : String.localizedKey("managementNotInstalled"),
                    enabled: snapshot.installedActivationPackages.contains(target.id)
                ) {
                    runShellAction("activate:\(target.id)", command: target.command)
                }
            }
        }
    }

    @ViewBuilder
    private var screenshotSheet: some View {
        if let screenshotURL, let image = NSImage(contentsOf: screenshotURL) {
            VStack(alignment: .leading, spacing: 16) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 420)
                    .appBackground(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button("managementOpen") { NSWorkspace.shared.open(screenshotURL) }
                    Spacer()
                    Button("commonSave") { saveScreenshot(screenshotURL) }.keyboardShortcut(.defaultAction)
                }
            }
        } else {
            ManagementErrorBanner(message: String.localizedKey("managementScreenshotFailed"))
        }
    }

    private var validPort: Int? {
        guard let port = Int(fixedPort), (1024...65535).contains(port) else { return nil }
        return port
    }

    private var validDensity: Int? {
        guard let value = Int(density), (72...1000).contains(value) else { return nil }
        return value
    }

    private var validResolution: (Int, Int)? {
        guard let width = Int(resolutionWidth), let height = Int(resolutionHeight),
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private var validAnimationScales: (String, String, String)? {
        let values = [windowAnimationScale, transitionAnimationScale, animatorDurationScale]
        guard values.allSatisfy({ Double($0).map { $0 >= 0 } == true }) else { return nil }
        return (values[0], values[1], values[2])
    }

    private var activationTargets: [DeviceActivationTarget] {
        [
            DeviceActivationTarget(
                id: "moe.shizuku.privileged.api",
                title: "Shizuku",
                command: "$(pm path moe.shizuku.privileged.api | sed \"s#package:##;s#/base.apk#/lib/$(getprop ro.product.cpu.abi | sed \\\"s/arm64-v8a/arm64/\\\")/libshizuku.so#\")"
            ),
            DeviceActivationTarget(
                id: "me.piebridge.brevent",
                title: "Brevent",
                command: "sh /data/data/me.piebridge.brevent/brevent.sh"
            ),
            DeviceActivationTarget(
                id: "com.catchingnow.icebox",
                title: "Ice Box",
                command: "sh /storage/emulated/0/Android/data/com.catchingnow.icebox/files/start.sh"
            )
        ]
    }

    private func refreshSnapshot() {
        guard let target = managementTarget(from: appState), !isRefreshing else { return }
        isRefreshing = true
        Task {
            do {
                let command = """
                echo PORT=$(getprop service.adb.tcp.port); \
                echo DENSITY=$(wm density | tail -n 1 | sed 's/.*: //'); \
                echo SIZE=$(wm size | tail -n 1 | sed 's/.*: //'); \
                echo WINDOW=$(settings get global window_animation_scale); \
                echo TRANSITION=$(settings get global transition_animation_scale); \
                echo ANIMATOR=$(settings get global animator_duration_scale); \
                pm list packages | grep -E '^package:(moe.shizuku.privileged.api|me.piebridge.brevent|com.catchingnow.icebox)$' || true
                """
                snapshot = parseUtilitySnapshot(try await ManagementADB.shell(target: target, command: command))
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Failed to load device utility state: \(target.device.name), \(error.localizedDescription)")
            }
            isRefreshing = false
        }
    }

    private func captureScreenshot() {
        guard let target = managementTarget(from: appState) else { return }
        isBusy = true
        resultMessage = nil
        errorMessage = nil
        Task {
            let identifier = UUID().uuidString.lowercased()
            let remotePath = "/data/local/tmp/screen_remote_screenshot_\(identifier).png"
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Screen-Remote-\(identifier).png")
            do {
                _ = try? await ManagementADB.run(
                    target: target,
                    arguments: ["shell", "rm", "-f", remotePath]
                )
                let capture = try await ManagementADB.run(
                    target: target,
                    arguments: ["shell", "screencap", "-p", remotePath],
                    timeout: 30
                )
                guard capture.succeeded else {
                    throw ManagementError.message(capture.failureDetail)
                }
                let pull = try await ManagementADB.run(
                    target: target,
                    arguments: ["pull", remotePath, localURL.path],
                    timeout: 30
                )
                guard pull.succeeded,
                      let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path),
                      (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0,
                      NSImage(contentsOf: localURL) != nil else {
                    throw ManagementError.message(
                        pull.succeeded ? String.localizedKey("managementScreenshotFailed") : pull.failureDetail
                    )
                }
                _ = try? await ManagementADB.run(
                    target: target,
                    arguments: ["shell", "rm", "-f", remotePath]
                )
                screenshotURL = localURL
                activeSheet = .screenshot
                appState.appendSDLLog("Device screenshot captured: \(target.device.name)")
            } catch {
                _ = try? await ManagementADB.run(
                    target: target,
                    arguments: ["shell", "rm", "-f", remotePath]
                )
                try? FileManager.default.removeItem(at: localURL)
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Device screenshot failed: \(target.device.name), \(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    private func saveScreenshot(_ sourceURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Screen Remote.png"
        panel.allowedFileTypes = ["png"]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            activeSheet = nil
            resultMessage = String.localizedKey("managementScreenshotSaved")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runFixedPort() {
        guard let target = managementTarget(from: appState), let port = validPort else { return }
        activeSheet = nil
        isBusy = true
        Task {
            do {
                let output = try await ManagementADB.run(target: target, arguments: ["tcpip", String(port)])
                guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
                resultMessage = String(format: String.localizedKey("managementFixedPortApplied"), port)
                appState.appendSDLLog("Wireless debugging port changed: \(target.device.name), port=\(port)")
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Failed to change wireless debugging port: \(target.device.name), \(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    private func runReboot(mode: String) {
        guard let target = managementTarget(from: appState) else { return }
        activeSheet = nil
        isBusy = true
        Task {
            do {
                let output: ManagementCommandOutput
                switch mode {
                case "powerOff":
                    output = try await ManagementADB.run(target: target, arguments: ["shell", "reboot", "-p"])
                case "recovery":
                    output = try await ManagementADB.run(target: target, arguments: ["reboot", "recovery"])
                case "fastboot":
                    output = try await ManagementADB.run(target: target, arguments: ["reboot", "bootloader"])
                default:
                    output = try await ManagementADB.run(target: target, arguments: ["reboot"])
                }
                guard output.succeeded else { throw ManagementError.message(output.failureDetail) }
                resultMessage = String.localizedKey("managementCommandSent")
                appState.appendSDLLog("Device reboot command sent: \(target.device.name), mode=\(mode)")
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Device reboot command failed: \(target.device.name), mode=\(mode), \(error.localizedDescription)")
            }
            isBusy = false
        }
    }

    private func runShellAction(_ action: String, command: String, refreshAfter: Bool = false) {
        guard let target = managementTarget(from: appState) else { return }
        activeSheet = nil
        isBusy = true
        resultMessage = nil
        errorMessage = nil
        Task {
            do {
                _ = try await ManagementADB.shell(target: target, command: command)
                resultMessage = String.localizedKey("managementActionCompleted")
                appState.appendSDLLog("Device utility completed: \(target.device.name), action=\(action)")
                if refreshAfter { refreshSnapshot() }
            } catch {
                errorMessage = error.localizedDescription
                appState.appendSDLLog("Device utility failed: \(target.device.name), action=\(action), \(error.localizedDescription)")
            }
            isBusy = false
        }
    }
}

private func parseUtilitySnapshot(_ output: String) -> DeviceUtilitySnapshot {
    var values: [String: String] = [:]
    var packages: Set<String> = []
    for rawLine in output.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("package:") {
            packages.insert(String(line.dropFirst("package:".count)))
        } else if let separator = line.firstIndex(of: "=") {
            values[String(line[..<separator])] = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    let size = (values["SIZE"] ?? "").split(separator: "x", maxSplits: 1).map(String.init)
    return DeviceUtilitySnapshot(
        wirelessPort: (values["PORT"] ?? "").replacingOccurrences(of: "-1", with: ""),
        density: values["DENSITY"] ?? "",
        resolutionWidth: size.first ?? "",
        resolutionHeight: size.count > 1 ? size[1] : "",
        windowAnimationScale: values["WINDOW"] ?? "1.0",
        transitionAnimationScale: values["TRANSITION"] ?? "1.0",
        animatorDurationScale: values["ANIMATOR"] ?? "1.0",
        installedActivationPackages: packages
    )
}

private struct UtilitySheetHeader: View {
    let title: LocalizedStringKey
    let close: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.title2.bold())
            Spacer()
            Button(action: close) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("commonCancel")
        }
        .padding(20)
    }
}

private struct UtilityForm<Content: View>: View {
    let detail: LocalizedStringKey
    let primaryTitle: LocalizedStringKey
    let primaryEnabled: Bool
    let primaryAction: () -> Void
    var secondaryTitle: LocalizedStringKey?
    var secondaryAction: (() -> Void)?
    let content: Content

    init(
        detail: LocalizedStringKey,
        primaryTitle: LocalizedStringKey,
        primaryEnabled: Bool,
        primaryAction: @escaping () -> Void,
        secondaryTitle: LocalizedStringKey? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.detail = detail
        self.primaryTitle = primaryTitle
        self.primaryEnabled = primaryEnabled
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(detail).font(.subheadline).foregroundColor(.secondary)
            content
            HStack {
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                }
                Spacer()
                Button(primaryTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!primaryEnabled)
            }
        }
    }
}

private struct UtilityTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField("", text: $text).textFieldStyle(.roundedBorder)
        }
    }
}

private struct UtilityOptionList<Content: View>: View {
    let detail: LocalizedStringKey
    let content: Content

    init(detail: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(detail).font(.subheadline).foregroundColor(.secondary)
            VStack(spacing: 8) { content }
        }
    }
}

private struct UtilityOptionButton: View {
    let title: LocalizedStringKey?
    let titleText: String?
    let icon: String
    var badge: String?
    var enabled = true
    var isDestructive = false
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        icon: String,
        badge: String? = nil,
        enabled: Bool = true,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.titleText = nil
        self.icon = icon
        self.badge = badge
        self.enabled = enabled
        self.isDestructive = isDestructive
        self.action = action
    }

    init(
        titleText: String,
        icon: String,
        badge: String? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = nil
        self.titleText = titleText
        self.icon = icon
        self.badge = badge
        self.enabled = enabled
        self.isDestructive = false
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22)
                if let title { Text(title) }
                else if let titleText { Text(titleText) }
                Spacer()
                if let badge {
                    Text(badge).font(.caption2).foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .appBackground(Color.primary.opacity(0.06), in: Capsule())
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .appCard(radius: 12)
        }
        .buttonStyle(.plain)
        .foregroundColor(isDestructive ? .red : .primary)
        .disabled(!enabled)
    }
}
