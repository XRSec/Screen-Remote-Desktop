import CoreVideo
import Foundation

/// A transport object between the native scrcpy decoder and the macOS rendering layer.
///
/// The previous rendering path converted every decoded frame directly into CGImage.
/// Keeping the decoded CVPixelBuffer alive allows future Metal-backed surfaces to consume
/// frames without forcing an intermediate image conversion.
final class ScrcpyStreamingFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: UInt64
    let generation: UInt64

    init(
        pixelBuffer: CVPixelBuffer,
        timestamp: UInt64,
        generation: UInt64
    ) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
        self.generation = generation
    }
}
