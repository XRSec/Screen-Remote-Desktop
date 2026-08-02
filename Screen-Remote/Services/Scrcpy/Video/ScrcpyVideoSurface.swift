import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

final class ScrcpyVideoSurface: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var pixelSize = CGSize.zero

    private let context = CIContext(options: [.cacheIntermediates: false])

    func publish(_ pixelBuffer: CVPixelBuffer) {
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
            self?.pixelSize = .zero
        }
    }
}
