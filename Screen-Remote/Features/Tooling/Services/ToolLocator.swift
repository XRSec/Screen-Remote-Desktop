import Foundation

enum ToolLocator {
    static func find(_ kind: ToolDownloadKind) -> String? {
        let name = kind.rawValue
        var candidates: [String] = []

        if let commandPath = commandPath(for: name) {
            candidates.append(commandPath)
        }

        let home = NSHomeDirectory()
        let support = "\(home)/Library/Application Support/Screen Remote/Tools"
        switch kind {
        case .adb:
            candidates += [
                "\(home)/Library/Android/sdk/platform-tools/adb",
                "/opt/homebrew/bin/adb",
                "/usr/local/bin/adb",
                "\(support)/platform-tools/adb",
                "\(home)/Library/Application Support/adb"
            ]
        case .scrcpy:
            candidates += [
                "\(home)/Library/Android/sdk/scrcpy/scrcpy",
                "/opt/homebrew/bin/scrcpy",
                "/usr/local/bin/scrcpy",
                "\(support)/scrcpy/scrcpy",
                "\(home)/Library/Application Support/scrcpy"
            ]
        case .androidCLI, .emulator, .skins:
            break
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func commandPath(for name: String) -> String? {
        guard let result = try? NativeProcess.run(
            "/bin/zsh",
            ["-lc", "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH; whence -p \(name)"]
        ), result.status == 0 else { return nil }
        return result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first
    }
}
