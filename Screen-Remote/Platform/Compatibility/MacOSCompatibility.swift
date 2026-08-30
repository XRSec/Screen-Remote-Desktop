import AppKit
import Foundation
import SwiftUI

private struct AppMaterialEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .contentBackground
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct TextFieldFocusDismissalView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        private var monitor: Any?

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                self?.dismissTextFieldFocus(for: event)
                return event
            }
        }

        private func dismissTextFieldFocus(for event: NSEvent) {
            guard let window = event.window,
                  let firstResponder = window.firstResponder,
                  firstResponder is NSTextView || firstResponder is NSTextField else {
                return
            }

            let hitView = window.contentView?.hitTest(event.locationInWindow)
            var currentView = hitView
            while let view = currentView {
                if view === firstResponder || view is NSTextField || view is NSTextView {
                    return
                }
                currentView = view.superview
            }
            window.makeFirstResponder(nil)
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

private struct AppMainWindowSizingView: NSViewRepresentable {
    let defaultWidth: CGFloat
    let defaultHeight: CGFloat
    let minimumWidth: CGFloat
    let minimumHeight: CGFloat

    func makeNSView(context: Context) -> WindowSizingNSView {
        WindowSizingNSView(
            defaultWidth: defaultWidth,
            defaultHeight: defaultHeight,
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        )
    }

    func updateNSView(_ nsView: WindowSizingNSView, context: Context) {
        nsView.defaultWidth = defaultWidth
        nsView.defaultHeight = defaultHeight
        nsView.minimumWidth = minimumWidth
        nsView.minimumHeight = minimumHeight
        nsView.configureWindowIfNeeded()
    }
}

private final class WindowSizingNSView: NSView {
    var defaultWidth: CGFloat
    var defaultHeight: CGFloat
    var minimumWidth: CGFloat
    var minimumHeight: CGFloat
    private weak var configuredWindow: NSWindow?
    private var titlebarDoubleClickMonitor: Any?

    init(
        defaultWidth: CGFloat,
        defaultHeight: CGFloat,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) {
        self.defaultWidth = defaultWidth
        self.defaultHeight = defaultHeight
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeTitlebarDoubleClickMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installTitlebarDoubleClickMonitorIfNeeded()
        configureWindowIfNeeded()
    }

    func configureWindowIfNeeded() {
        guard let window, configuredWindow !== window else { return }
        configuredWindow = window

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.contentMinSize = NSSize(width: self.minimumWidth, height: self.minimumHeight)
            window.setContentSize(NSSize(
                width: self.defaultWidth,
                height: max(self.defaultHeight, self.minimumHeight)
            ))
        }
    }

    private func installTitlebarDoubleClickMonitorIfNeeded() {
        removeTitlebarDoubleClickMonitor()
        guard let window else { return }
        titlebarDoubleClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self, weak window] event in
            guard let self,
                  let window,
                  self.window === window,
                  event.window === window,
                  event.clickCount == 2,
                  NativeWindowInteraction.isInTitlebar(event, of: window),
                  !NativeWindowInteraction.isOverStandardWindowButton(event, in: window) else {
                return event
            }
            NativeWindowInteraction.performZoom(on: window)
            return nil
        }
    }

    private func removeTitlebarDoubleClickMonitor() {
        if let titlebarDoubleClickMonitor {
            NSEvent.removeMonitor(titlebarDoubleClickMonitor)
            self.titlebarDoubleClickMonitor = nil
        }
    }
}

enum NativeWindowInteraction {
    static func performZoom(on window: NSWindow) {
        window.performZoom(nil)
    }

    static func isInTitlebar(_ event: NSEvent, of window: NSWindow) -> Bool {
        var titlebarStyle = window.styleMask
        titlebarStyle.remove(.fullSizeContentView)
        let titlebarHeight = NSWindow.frameRect(
            forContentRect: .zero,
            styleMask: titlebarStyle
        ).height
        guard titlebarHeight > 0 else { return false }
        return event.locationInWindow.y >= window.frame.height - titlebarHeight
    }

    static func isOverStandardWindowButton(_ event: NSEvent, in window: NSWindow) -> Bool {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].contains { type in
            guard let button = window.standardWindowButton(type), !button.isHidden else {
                return false
            }
            return button.bounds.contains(button.convert(event.locationInWindow, from: nil))
        }
    }
}

enum AppLocalization {
    private static let lock = NSLock()
    private static var languageIdentifier: String?

    static func useLanguage(_ identifier: String?) {
        lock.lock()
        languageIdentifier = identifier
        lock.unlock()
    }

    static func localizedString(
        forKey key: String,
        table: String? = nil,
        bundle: Bundle = .main
    ) -> String {
        lock.lock()
        let requestedLanguage = languageIdentifier
        lock.unlock()

        guard let requestedLanguage else {
            return bundle.localizedString(forKey: key, value: nil, table: table)
        }

        let localization = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: [requestedLanguage]
        ).first ?? requestedLanguage

        guard let localizationPath = bundle.path(forResource: localization, ofType: "lproj"),
              let localizedBundle = Bundle(path: localizationPath) else {
            return bundle.localizedString(forKey: key, value: nil, table: table)
        }

        return localizedBundle.localizedString(forKey: key, value: nil, table: table)
    }
}

extension String {
    init(localizedKey key: String, table: String? = nil, bundle: Bundle = .main) {
        self = AppLocalization.localizedString(forKey: key, table: table, bundle: bundle)
    }

    static func localizedKey(_ key: String, table: String? = nil, bundle: Bundle = .main) -> String {
        AppLocalization.localizedString(forKey: key, table: table, bundle: bundle)
    }
}

extension View {
    /// Releases a text field's first responder when the user clicks elsewhere in the app.
    func appDismissTextFieldFocusOnTap() -> some View {
        background(TextFieldFocusDismissalView())
    }

    func appMainWindowSizing(
        defaultWidth: CGFloat,
        defaultHeight: CGFloat,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) -> some View {
        background(AppMainWindowSizingView(
            defaultWidth: defaultWidth,
            defaultHeight: defaultHeight,
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        ))
    }

    /// macOS 11-compatible form of `background(_:in:)`.
    func appBackground<S: Shape, F: ShapeStyle>(_ style: F, in shape: S) -> some View {
        background(shape.fill(style))
    }

    func appBackground<Background: View>(_ backgroundView: Background, alignment: Alignment = .center) -> some View {
        background(backgroundView, alignment: alignment)
    }

    @ViewBuilder
    func appMaterialBackground<S: Shape>(in shape: S, isActive: Bool = true) -> some View {
        if isActive {
            if #available(macOS 12, *) {
                background(shape.fill(.ultraThinMaterial))
            } else {
                background(AppMaterialEffectView().clipShape(shape))
            }
        } else {
            self
        }
    }

    func appOverlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View {
        self.overlay(overlay, alignment: alignment)
    }

    @ViewBuilder
    func appTextSelectionEnabled() -> some View {
        if #available(macOS 12, *) {
            textSelection(.enabled)
        } else {
            self
        }
    }

    @ViewBuilder
    func appMonospacedDigit() -> some View {
        if #available(macOS 12, *) {
            monospacedDigit()
        } else {
            self
        }
    }
}

/// Uses SF Symbols' native rotation on macOS 15 and a matching fallback on older systems.
struct AppRefreshSymbol: View {
    let isAnimating: Bool

    var body: some View {
        if #available(macOS 15, *) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .symbolEffect(
                    .rotate,
                    options: .repeat(.continuous),
                    isActive: isAnimating
                )
        } else {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    isAnimating
                        ? .linear(duration: 0.72).repeatForever(autoreverses: false)
                        : .default,
                    value: isAnimating
                )
        }
    }
}

extension Font {
    static var appCaptionMonospaced: Font {
        if #available(macOS 12, *) {
            return .caption.monospaced()
        }
        return .system(.caption, design: .monospaced)
    }
}

extension URLSession {
    func appDownload(for request: URLRequest) async throws -> (URL, URLResponse) {
        if #available(macOS 12, *) {
            return try await download(for: request)
        }
        return try await withCheckedThrowingContinuation { continuation in
            downloadTask(with: request) { temporaryURL, response, error in
                do {
                    if let error { throw error }
                    guard let temporaryURL, let response else {
                        throw URLError(.badServerResponse)
                    }
                    let retainedURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ScreenRemote-\(UUID().uuidString)")
                    try FileManager.default.copyItem(at: temporaryURL, to: retainedURL)
                    continuation.resume(returning: (retainedURL, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }.resume()
        }
    }
}
