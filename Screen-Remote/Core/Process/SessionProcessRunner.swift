import AppKit
import Foundation

enum SessionProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) async -> SessionCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = environment
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                let lock = NSLock()
                var didTimeOut = false
                do {
                    try process.run()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard process.isRunning else { return }
                        didTimeOut = true
                        process.terminate()
                    }
                    process.waitUntilExit()
                    lock.lock()
                    let timedOut = didTimeOut
                    lock.unlock()
                    continuation.resume(returning: SessionCommandResult(
                        exitCode: process.terminationStatus,
                        output: String(
                            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self
                        ),
                        error: String(
                            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self
                        ),
                        timedOut: timedOut
                    ))
                } catch {
                    continuation.resume(returning: SessionCommandResult(
                        exitCode: 126,
                        output: "",
                        error: error.localizedDescription,
                        timedOut: false
                    ))
                }
            }
        }
    }
}
