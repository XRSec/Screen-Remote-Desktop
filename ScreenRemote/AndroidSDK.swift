import Foundation

struct AndroidSDKInstallation {
    let root: URL
    let toolsBin: URL

    var sdkmanager: URL { toolsBin.appendingPathComponent("sdkmanager") }
    var avdmanager: URL { toolsBin.appendingPathComponent("avdmanager") }
    var adb: URL { root.appendingPathComponent("platform-tools/adb") }
    var emulator: URL { root.appendingPathComponent("emulator/emulator") }
    var scrcpy: URL { root.appendingPathComponent("scrcpy/scrcpy") }
}

struct AndroidCLIInstallation {
    let root: URL
    let executable: URL
}

enum AndroidCLILocator {
    static func locate(
        preferredExecutable: String? = nil,
        preferredRoot: String? = nil,
        preferredTools: String? = nil
    ) -> AndroidCLIInstallation? {
        let fm = FileManager.default
        var roots: [URL] = []
        if let preferredRoot, !preferredRoot.isEmpty { roots.append(URL(fileURLWithPath: preferredRoot)) }
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["ANDROID_HOME"] ?? environment["ANDROID_SDK_ROOT"] {
            roots.append(URL(fileURLWithPath: value))
        }
        roots += [
            AndroidSDKLocator.defaultSDKRoot,
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Android/Sdk")
        ]

        var candidates: [(URL, URL)] = []
        if let preferredExecutable, !preferredExecutable.isEmpty {
            let executable = URL(fileURLWithPath: preferredExecutable)
            candidates.append((roots.first ?? AndroidSDKLocator.defaultSDKRoot, executable))
        }
        if let preferredTools, !preferredTools.isEmpty {
            candidates.append((roots.first ?? AndroidSDKLocator.defaultSDKRoot,
                               URL(fileURLWithPath: preferredTools).appendingPathComponent("android")))
        }
        for root in roots {
            let commandTools = root.appendingPathComponent("cmdline-tools", isDirectory: true)
            candidates.append((root, commandTools.appendingPathComponent("latest/bin/android")))
            if let versions = try? fm.contentsOfDirectory(
                at: commandTools, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    candidates.append((root, version.appendingPathComponent("bin/android")))
                }
            }
        }
        candidates += [
            (roots.first ?? AndroidSDKLocator.defaultSDKRoot, URL(fileURLWithPath: "/opt/homebrew/bin/android")),
            (roots.first ?? AndroidSDKLocator.defaultSDKRoot, URL(fileURLWithPath: "/usr/local/bin/android"))
        ]

        var seen = Set<String>()
        for (root, executable) in candidates where seen.insert(executable.path).inserted {
            if fm.isExecutableFile(atPath: executable.path) {
                return AndroidCLIInstallation(root: root, executable: executable)
            }
        }
        return nil
    }
}

enum AndroidSDKLocator {
    static var defaultSDKRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Android/sdk", isDirectory: true)
    }

    static func locate(preferredRoot: String? = nil, preferredTools: String? = nil) -> AndroidSDKInstallation? {
        let fm = FileManager.default
        var roots: [URL] = []
        if let preferredRoot, !preferredRoot.isEmpty { roots.append(URL(fileURLWithPath: preferredRoot)) }
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["ANDROID_HOME"] ?? environment["ANDROID_SDK_ROOT"] {
            roots.append(URL(fileURLWithPath: value))
        }
        roots += [
            defaultSDKRoot,
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Android/Sdk")
        ]

        var uniqueRoots: [URL] = []
        for root in roots where !uniqueRoots.contains(root) { uniqueRoots.append(root) }
        roots = uniqueRoots
        let targetRoot = roots.first ?? defaultSDKRoot

        var bins: [(URL, URL)] = []
        if let preferredTools, !preferredTools.isEmpty {
            let bin = URL(fileURLWithPath: preferredTools)
            bins.append((targetRoot, bin))
        }
        for root in roots {
            let commandTools = root.appendingPathComponent("cmdline-tools", isDirectory: true)
            bins.append((root, commandTools.appendingPathComponent("latest/bin")))
            if let versions = try? fm.contentsOfDirectory(
                at: commandTools, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    bins.append((root, version.appendingPathComponent("bin")))
                }
            }
        }
        bins += [
            (targetRoot, URL(fileURLWithPath: "/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin")),
            (targetRoot, URL(fileURLWithPath: "/usr/local/share/android-commandlinetools/cmdline-tools/latest/bin"))
        ]

        for (root, bin) in bins where
            fm.isExecutableFile(atPath: bin.appendingPathComponent("sdkmanager").path) &&
            fm.isExecutableFile(atPath: bin.appendingPathComponent("avdmanager").path) {
            return AndroidSDKInstallation(root: root, toolsBin: bin)
        }
        return nil
    }

}

struct ProcessOutput {
    let status: Int32
    let standardOutput: String
    let standardError: String
    var succeeded: Bool { status == 0 }
}

enum AndroidCommandRunner {
    static func run(
        executable: URL,
        arguments: [String],
        sdkRoot: URL,
        avdHome: String? = nil,
        input: String? = nil
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()
                let inputPipe = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = errors
                if input != nil { process.standardInput = inputPipe }

                var environment = ProcessInfo.processInfo.environment
                environment["ANDROID_HOME"] = sdkRoot.path
                environment["ANDROID_SDK_ROOT"] = sdkRoot.path
                if let avdHome, !avdHome.isEmpty { environment["ANDROID_AVD_HOME"] = avdHome }
                environment["PATH"] = "\(sdkRoot.appendingPathComponent("platform-tools").path):\(environment["PATH"] ?? "")"
                process.environment = environment

                do {
                    try process.run()
                    if let input, let data = input.data(using: .utf8) {
                        inputPipe.fileHandleForWriting.write(data)
                        inputPipe.fileHandleForWriting.closeFile()
                    }
                    let group = DispatchGroup()
                    var stdout = Data()
                    var stderr = Data()
                    group.enter()
                    DispatchQueue.global().async {
                        stdout = output.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        stderr = errors.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    process.waitUntilExit()
                    group.wait()
                    continuation.resume(returning: ProcessOutput(
                        status: process.terminationStatus,
                        standardOutput: String(data: stdout, encoding: .utf8) ?? "",
                        standardError: String(data: stderr, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
