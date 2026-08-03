import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

final class ScrcpyVideoSurface: ObservableObject {
    /// Compatibility image output for existing SwiftUI views.
    /// New renderers should consume `frame` and keep the original pixel buffer.
    @Published private(set) var image: CGImage?
    @Published private(set) var frame: ScrcpyStreamingFrame?
    @Published private(set) var pixelSize = CGSize.zero

    private let context = CIContext(options: [.cacheIntermediates: false])
    private var generation: UInt64 = 0

    func publish(_ pixelBuffer: CVPixelBuffer) {
        generation &+= 1
        let streamingFrame = ScrcpyStreamingFrame(
            pixelBuffer: pixelBuffer,
            generation: generation
        )

        DispatchQueue.main.async { [weak self] in
            self?.frame = streamingFrame
        }

        // Keep the existing CGImage path temporarily so current SwiftUI
        // surfaces continue to work while Metal-backed rendering is introduced.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.image = image
            self?.pixelSize = CGSize(width: image.width, height: image.height)
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.image = nil
            self?.frame = nil
            self?.pixelSize = .zero
        }
    }
}
