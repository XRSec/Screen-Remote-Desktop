import AppKit
import Foundation

func preflight(
    candidate: ResolvedConnectionCandidate,
    adbPath: String
) async -> ConnectionRaceOutcome {
    let result = await SessionProcessRunner.run(
        executable: adbPath,
        arguments: ["-s", candidate.adbSerial, "shell", ScreenSessionConstants.preflightCommand],
        timeout: 7
    )
    guard result.succeeded else {
        return ConnectionRaceOutcome(
            candidate: candidate,
            preflight: nil,
            error: result.failureDetail
        )
    }
    do {
        return ConnectionRaceOutcome(
            candidate: candidate,
            preflight: try parsePreflight(result.output),
            error: nil
        )
    } catch {
        return ConnectionRaceOutcome(
            candidate: candidate,
            preflight: nil,
            error: error.localizedDescription
        )
    }
}

func buildScrcpyArguments(
    device: Device,
    adbSerial: String,
    automaticVideoEncoder: RemoteVideoEncoder?
) -> [String] {
    let options = device.scrcpyOptions
    var arguments = [
        "--serial", adbSerial,
        "--window-title", "Screen Remote — \(device.name)"
    ]
    appendVideoArguments(options, automaticVideoEncoder: automaticVideoEncoder, to: &arguments)
    appendAudioArguments(options, to: &arguments)
    appendSessionArguments(options, to: &arguments)
    appendVirtualDisplayArguments(options, to: &arguments)
    return arguments
}

private func appendVideoArguments(
    _ options: ScrcpyDeviceOptions,
    automaticVideoEncoder: RemoteVideoEncoder?,
    to arguments: inout [String]
) {
    if options.maxSize > 0 { arguments += ["--max-size", String(options.maxSize)] }
    if !options.videoBitrate.isEmpty { arguments += ["--video-bit-rate", options.videoBitrate] }
    if options.maxFPS > 0 { arguments += ["--max-fps", String(options.maxFPS)] }
    if !options.videoEncoder.isEmpty {
        let codec = automaticVideoEncoder?.codec ?? inferVideoCodec(fromEncoderName: options.videoEncoder)
        if let codec { arguments += ["--video-codec", codec] }
        arguments += ["--video-encoder", options.videoEncoder]
    } else if let automaticVideoEncoder {
        arguments += ["--video-codec", automaticVideoEncoder.codec, "--video-encoder", automaticVideoEncoder.name]
    }
}

private func appendAudioArguments(
    _ options: ScrcpyDeviceOptions,
    to arguments: inout [String]
) {
    guard options.enableAudio else {
        arguments.append("--no-audio")
        return
    }
    let audioCodec = codecForAudioDecoderSelection(options.audioDecoder)
        ?? inferAudioCodec(fromEncoderName: options.audioEncoder)
    if let audioCodec { arguments += ["--audio-codec", audioCodec] }
    if !options.audioBitrate.isEmpty, audioCodec != "raw" {
        arguments += ["--audio-bit-rate", options.audioBitrate]
    }
    if !options.audioEncoder.isEmpty, audioCodec != "raw" {
        arguments += ["--audio-encoder", options.audioEncoder]
    }
}

private func appendSessionArguments(
    _ options: ScrcpyDeviceOptions,
    to arguments: inout [String]
) {
    if !options.clipboardSync { arguments.append("--no-clipboard-autosync") }
    if options.turnScreenOff { arguments.append("--turn-screen-off") }
    if options.powerOffOnClose && options.cleanupOnDisconnect { arguments.append("--power-off-on-close") }
    if options.keepDeviceAwake { arguments.append("--stay-awake") }
    if !options.cleanupOnDisconnect { arguments.append("--no-cleanup") }
    if options.ignoreVideoEncoderConstraints { arguments.append("--ignore-video-encoder-constraints") }
}

private func appendVirtualDisplayArguments(
    _ options: ScrcpyDeviceOptions,
    to arguments: inout [String]
) {
    guard options.newDisplayEnabled else { return }
    if options.newDisplayWidth > 0, options.newDisplayHeight > 0 {
        var newDisplay = "\(options.newDisplayWidth)x\(options.newDisplayHeight)"
        if options.newDisplayDPI > 0 { newDisplay += "/\(options.newDisplayDPI)" }
        arguments.append("--new-display=\(newDisplay)")
    } else {
        arguments.append("--new-display")
    }
    if !options.virtualDisplaySystemDecorations { arguments.append("--no-vd-system-decorations") }
    if options.preserveVirtualDisplayContent { arguments.append("--no-vd-destroy-content") }
    if !options.startApp.isEmpty { arguments += ["--start-app", options.startApp] }
}

func resolveAutomaticVideoEncoder(
    device: Device,
    adbSerial: String,
    configuration: SessionLaunchConfiguration,
    log: @escaping (String) -> Void
) async -> RemoteVideoEncoder? {
    var environment = ProcessInfo.processInfo.environment
    environment["ADB"] = configuration.adbPath
    let result = await SessionProcessRunner.run(
        executable: configuration.scrcpyPath,
        arguments: ["--serial", adbSerial, "--list-encoders"],
        environment: environment,
        timeout: 15
    )
    guard result.succeeded else {
        log("Automatic video encoder detection failed; using the scrcpy default: \(result.failureDetail)")
        return nil
    }

    let capabilities = parseScrcpyRemoteEncoders("\(result.output)\n\(result.error)")
    let selection = selectNativeVideoCodec(
        remoteEncoders: capabilities,
        requestedEncoder: device.scrcpyOptions.videoEncoder,
        requestedDecoder: device.scrcpyOptions.videoDecoder,
        supportedCodecs: ["h265", "h264", "av1", "vp9", "vp8"]
    )
    guard let encoder = selection.encoder else { return nil }
    let selected = RemoteVideoEncoder(codec: selection.codec, name: encoder)
    log("Video encoder selected: codec=\(selected.codec), encoder=\(selected.name)")
    return selected
}

func resolveCandidates(
    _ connections: [DeviceConnection],
    mdnsOutput: String
) -> [ResolvedConnectionCandidate] {
    let mdnsServices = parseMDNSEndpoints(mdnsOutput)
    return connections
        .sorted { $0.priority < $1.priority }
        .compactMap { connection in
            let serial: String
            switch connection.transport {
            case .usb:
                serial = connection.serial.trimmingCharacters(in: .whitespacesAndNewlines)
            case .tcp:
                let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
                serial = hostPort(host: host, port: connection.port)
            case .mdns:
                let configured = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
                let configuredSerial = mdnsDeviceSerial(configured)
                serial = mdnsServices.first {
                    $0.service.caseInsensitiveCompare(configured) == .orderedSame
                        || $0.endpoint.caseInsensitiveCompare(configured) == .orderedSame
                        || mdnsDeviceSerial($0.service).caseInsensitiveCompare(configuredSerial) == .orderedSame
                }?.endpoint ?? configured
            }
            guard !serial.isEmpty else { return nil }
            return ResolvedConnectionCandidate(connection: connection, adbSerial: serial)
        }
}

func parseConnectedADBDevices(_ output: String) -> [ADBConnectedDevice] {
    output
        .split(whereSeparator: \.isNewline)
        .dropFirst()
        .compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2 else { return nil }
            return ADBConnectedDevice(serial: fields[0], state: fields[1])
        }
}

func parseMDNSEndpoints(_ output: String) -> [(service: String, endpoint: String)] {
    output
        .split(whereSeparator: \.isNewline)
        .compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2,
                  !line.lowercased().contains("list of discovered"),
                  fields.contains(where: { $0.localizedCaseInsensitiveContains("_adb-tls-connect") }),
                  let endpoint = fields.last(where: { looksLikeNetworkEndpoint($0) }) else {
                return nil
            }
            return (fields[0], endpoint)
        }
}

func parsePreflight(_ output: String) throws -> ScreenDevicePreflight {
    func section(_ marker: String, next: String?) -> String {
        let suffix = output.components(separatedBy: marker).dropFirst().joined(separator: marker)
        guard let next else { return suffix.trimmingCharacters(in: .whitespacesAndNewlines) }
        return suffix.components(separatedBy: next).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    guard output.contains(ScreenSessionConstants.modelMarker),
          output.contains(ScreenSessionConstants.displayMarker) else {
        throw ScreenSessionError.invalidPreflight
    }
    let displaySection = section(ScreenSessionConstants.displayMarker, next: ScreenSessionConstants.batteryMarker)
    let displayInfo = parseScreenTargetDisplayInfo(displaySection)
    return ScreenDevicePreflight(
        model: section(ScreenSessionConstants.modelMarker, next: ScreenSessionConstants.androidMarker)
            .screenSessionFirstNonemptyLine,
        androidVersion: section(ScreenSessionConstants.androidMarker, next: ScreenSessionConstants.serialMarker)
            .screenSessionFirstNonemptyLine,
        serial: section(ScreenSessionConstants.serialMarker, next: ScreenSessionConstants.fingerprintMarker)
            .screenSessionFirstNonemptyLine,
        buildFingerprint: section(ScreenSessionConstants.fingerprintMarker, next: ScreenSessionConstants.displayMarker)
            .screenSessionFirstNonemptyLine,
        displaySize: displayInfo.map { "\($0.width)x\($0.height)" }
            ?? displaySection.components(separatedBy: .newlines)
                .first { $0.lowercased().contains("size") }
            ?? "",
        displayInfo: displayInfo,
        batteryLevel: parseBatteryLevel(
            section(ScreenSessionConstants.batteryMarker, next: nil)
        )
    )
}

func parseScreenTargetDisplayInfo(_ output: String) -> ScreenTargetDisplayInfo? {
    func matches(_ pattern: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(output.startIndex..., in: output)
        return expression.matches(in: output, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: output) else { return nil }
                return String(output[range])
            }
        }
    }

    let sizeMatches = matches("(Physical|Override)\\s+size:\\s*(\\d+)x(\\d+)")
    guard let currentSize = sizeMatches.last,
          currentSize.count == 3,
          let width = Int(currentSize[1]),
          let height = Int(currentSize[2]),
          width > 0, height > 0 else {
        return nil
    }
    let densityMatches = matches("(Physical|Override)\\s+density:\\s*(\\d+)")
    let physicalSize = sizeMatches.first(where: { $0.first?.lowercased() == "physical" })
    let physicalDensity = densityMatches.first(where: { $0.first?.lowercased() == "physical" })
    return ScreenTargetDisplayInfo(
        width: width,
        height: height,
        densityDPI: densityMatches.last.flatMap { $0.count > 1 ? Int($0[1]) : nil },
        physicalWidth: physicalSize.flatMap { $0.count > 2 ? Int($0[1]) : nil },
        physicalHeight: physicalSize.flatMap { $0.count > 2 ? Int($0[2]) : nil },
        physicalDensityDPI: physicalDensity.flatMap { $0.count > 1 ? Int($0[1]) : nil }
    )
}

func parseBatteryLevel(_ output: String) -> Int? {
    output
        .components(separatedBy: .newlines)
        .lazy
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { $0.lowercased().hasPrefix("level:") }?
        .split(separator: ":", maxSplits: 1)
        .last
        .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .flatMap { (0...100).contains($0) ? $0 : nil }
}

func adbConnectSucceeded(_ result: SessionCommandResult) -> Bool {
    let combined = "\(result.output)\n\(result.error)".lowercased()
    return combined.contains("connected to") || combined.contains("already connected")
}

func executablePath(_ configured: String, fallback: ToolDownloadKind) -> String {
    if FileManager.default.isExecutableFile(atPath: configured) {
        return configured
    }
    return ToolLocator.find(fallback) ?? configured
}

func normalizeADBSerial(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ".:", with: ":")
        .lowercased()
}

func hostPort(host: String, port: Int) -> String {
    guard !host.isEmpty else { return "" }
    if host.hasPrefix("[") || host.filter({ $0 == ":" }).count <= 1 {
        return "\(host):\(port)"
    }
    return "[\(host)]:\(port)"
}

func looksLikeNetworkEndpoint(_ value: String) -> Bool {
    if value.hasPrefix("["), let closing = value.firstIndex(of: "]") {
        return Int(value[value.index(after: closing)...].drop(while: { $0 == ":" })) != nil
    }
    guard let separator = value.lastIndex(of: ":") else { return false }
    return Int(value[value.index(after: separator)...]) != nil
}

func formatCommand(_ command: [String]) -> String {
    command.map { argument in
        let escaped = argument.replacingOccurrences(of: "'", with: "'\\''")
        return argument.contains(where: \.isWhitespace) ? "'\(escaped)'" : escaped
    }.joined(separator: " ")
}
