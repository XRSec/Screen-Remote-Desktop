import AppKit
import CoreImage
import CryptoKit
import Foundation
import VideoToolbox
import Darwin

struct NativeProcessResult {
    let status: Int32
    let output: String
    let error: String

    var failureDetail: String {
        let stderr = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        let stdout = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? "exit status \(status)" : stdout
    }
}

enum NativeProcess {
    static func run(_ executable: String, _ arguments: [String]) throws -> NativeProcessResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return NativeProcessResult(
            status: process.terminationStatus,
            output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            error: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
