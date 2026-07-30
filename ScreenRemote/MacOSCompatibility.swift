import Foundation
import SwiftUI

extension String {
    init(localizedKey key: String, table: String? = nil, bundle: Bundle = .main) {
        self = bundle.localizedString(forKey: key, value: "", table: table)
    }

    static func localizedKey(_ key: String, table: String? = nil, bundle: Bundle = .main) -> String {
        String.localizedKey(key, table: table, bundle: bundle)
    }
}

extension View {
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
