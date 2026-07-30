import AppKit
import Foundation
import SwiftUI

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
