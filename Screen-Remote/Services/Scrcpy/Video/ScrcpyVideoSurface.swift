import AppKit
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

final class ScrcpyVideoSurface: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var pixelSize = CGSize.zero

    func publish(_ pixelBuffer: CVPixelBuffer) {
        var image: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard status == noErr, let image else { return }
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
