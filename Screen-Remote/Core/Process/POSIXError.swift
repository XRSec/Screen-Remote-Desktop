import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

func lastPOSIXError() -> String {
    String(cString: strerror(errno))
}
