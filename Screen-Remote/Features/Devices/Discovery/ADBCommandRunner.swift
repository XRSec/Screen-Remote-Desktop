import Foundation

struct ADBCommandResult: Sendable {
    let exitCode: Int32
    let output: String
    let error: String
}

enum ADBCommandRunner {
    static func run(executable: String, arguments: [String]) async -> ADBCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard FileManager.default.isExecutableFile(atPath: executable) else {
                    continuation.resume(returning: ADBCommandResult(
                        exitCode: 127,
                        output: "",
                        error: String(format: String.localizedKey("deviceDiscoveryADBNotFound %@"), executable)
                    ))
                    return
                }

                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: ADBCommandResult(
                        exitCode: process.terminationStatus,
                        output: String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                        error: String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    ))
                } catch {
                    continuation.resume(returning: ADBCommandResult(exitCode: 126, output: "", error: error.localizedDescription))
                }
            }
        }
    }
}
