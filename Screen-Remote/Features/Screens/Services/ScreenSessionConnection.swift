import AppKit
import Foundation

@MainActor
extension ScreenSessionManager {
    func resolveADBTarget(
        connections: [DeviceConnection],
        adbPath configuredADBPath: String,
        log: @escaping (String) -> Void
    ) async throws -> ResolvedADBTarget {
        let adbPath = executablePath(configuredADBPath, fallback: .adb)
        let winner = try await resolveConnection(
            connections: connections,
            adbPath: adbPath,
            log: log
        )
        return ResolvedADBTarget(
            serial: winner.candidate.adbSerial,
            transport: winner.candidate.transport,
            adbPath: adbPath
        )
    }

    func runStartup(
        device: Device,
        configuration: SessionLaunchConfiguration,
        log: @escaping (String) -> Void
    ) async throws {
        let winner: ConnectionRaceOutcome
        if let connectedWinner = connectedOutcome(for: device) {
            winner = connectedWinner
        } else {
            update(device.id, phase: .checkingExisting, detail: "")
            winner = try await resolveConnection(
                connections: device.connections,
                adbPath: configuration.adbPath,
                log: log,
                onNetworkRaceStarted: { [weak self] in
                    self?.update(device.id, phase: .racing, detail: "")
                }
            )
        }
        try await prepareAndLaunch(
            device: device,
            winner: winner,
            configuration: configuration,
            log: log
        )
    }

    func connectedOutcome(for device: Device) -> ConnectionRaceOutcome? {
        let snapshot = session(for: device.id)
        guard snapshot.isConnected,
              let transport = snapshot.transport,
              let preflight = snapshot.preflight,
              let connection = device.connections.first(where: { $0.transport == transport })
                ?? device.connections.first else {
            return nil
        }
        return ConnectionRaceOutcome(
            candidate: ResolvedConnectionCandidate(
                connection: connection,
                adbSerial: snapshot.adbSerial
            ),
            preflight: preflight,
            error: nil
        )
    }

    func resolveConnection(
        connections: [DeviceConnection],
        adbPath: String,
        log: @escaping (String) -> Void,
        onNetworkRaceStarted: (() -> Void)? = nil
    ) async throws -> ConnectionRaceOutcome {
        guard FileManager.default.isExecutableFile(atPath: adbPath) else {
            throw ScreenSessionError.adbNotFound
        }
        guard !connections.isEmpty else {
            throw ScreenSessionError.noConnectionCandidates
        }

        let needsMDNSDiscovery = connections.contains { $0.transport == .mdns }
        let existingResult: SessionCommandResult
        let mdnsOutput: String
        if needsMDNSDiscovery {
            async let existingRead = SessionProcessRunner.run(
                executable: adbPath,
                arguments: ["devices", "-l"],
                timeout: 5
            )
            async let mdnsRead = SessionProcessRunner.run(
                executable: adbPath,
                arguments: ["mdns", "services"],
                timeout: 5
            )
            let results = await (existingRead, mdnsRead)
            existingResult = results.0
            mdnsOutput = results.1.output
        } else {
            existingResult = await SessionProcessRunner.run(
                executable: adbPath,
                arguments: ["devices", "-l"],
                timeout: 5
            )
            mdnsOutput = ""
        }
        guard existingResult.succeeded else {
            throw ScreenSessionError.commandFailed(existingResult.failureDetail)
        }
        let candidates = resolveCandidates(connections, mdnsOutput: mdnsOutput)
        if let winner = await chooseExistingConnection(
            candidates: candidates,
            connectedDevices: parseConnectedADBDevices(existingResult.output),
            adbPath: adbPath,
            log: log
        ) {
            return winner
        }

        let networkCandidates = candidates.filter { $0.transport != .usb }
        guard !networkCandidates.isEmpty else {
            throw ScreenSessionError.usbUnavailable
        }
        onNetworkRaceStarted?()
        log(
            "ADB connection race started: \(networkCandidates.map { "\($0.transport.rawValue):\($0.adbSerial)" }.joined(separator: ", "))"
        )
        return try await raceNetworkConnections(
            networkCandidates,
            adbPath: adbPath,
            log: log
        )
    }

    func chooseExistingConnection(
        candidates: [ResolvedConnectionCandidate],
        connectedDevices: [ADBConnectedDevice],
        adbPath: String,
        log: @escaping (String) -> Void
    ) async -> ConnectionRaceOutcome? {
        let connectedSerials = Set(
            connectedDevices
                .filter { $0.state == "device" }
                .map { normalizeADBSerial($0.serial) }
        )
        let existing = candidates
            .filter { connectedSerials.contains(normalizeADBSerial($0.adbSerial)) }

        for transport in [DeviceTransport.usb, .mdns, .tcp] {
            let transportCandidates = existing.filter { $0.transport == transport }
            guard !transportCandidates.isEmpty else { continue }

            log(
                "Existing ADB connection race started: \(transportCandidates.map { "\($0.transport.rawValue):\($0.adbSerial)" }.joined(separator: ", "))"
            )
            if let winner = await raceExistingConnections(
                transportCandidates,
                adbPath: adbPath,
                log: log
            ) {
                return winner
            }
        }
        return nil
    }

    func raceExistingConnections(
        _ candidates: [ResolvedConnectionCandidate],
        adbPath: String,
        log: @escaping (String) -> Void
    ) async -> ConnectionRaceOutcome? {
        let stream = AsyncStream<ConnectionRaceOutcome> { continuation in
            for candidate in candidates {
                Task {
                    let started = Date()
                    let outcome = await preflight(candidate: candidate, adbPath: adbPath)
                    let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
                    await MainActor.run {
                        if outcome.succeeded {
                            log(
                                "Existing ADB race candidate ready: \(candidate.transport.rawValue):\(candidate.adbSerial), preflight=\(elapsed)ms"
                            )
                        } else {
                            log(
                                "Existing ADB race candidate failed: \(candidate.transport.rawValue):\(candidate.adbSerial), preflight=\(elapsed)ms, \(outcome.error ?? "unknown error")"
                            )
                        }
                    }
                    continuation.yield(outcome)
                }
            }
        }

        var completed = 0
        for await outcome in stream {
            completed += 1
            if outcome.succeeded {
                log(
                    "Existing ADB connection race winner: \(outcome.candidate.transport.rawValue):\(outcome.candidate.adbSerial)"
                )
                return outcome
            }
            if completed == candidates.count { break }
        }
        return nil
    }

    func raceNetworkConnections(
        _ candidates: [ResolvedConnectionCandidate],
        adbPath: String,
        log: @escaping (String) -> Void
    ) async throws -> ConnectionRaceOutcome {
        let stream = AsyncStream<ConnectionRaceOutcome> { continuation in
            for candidate in candidates {
                Task {
                    let started = Date()
                    let connect = await SessionProcessRunner.run(
                        executable: adbPath,
                        arguments: ["connect", candidate.adbSerial],
                        timeout: 7
                    )
                    let outcome: ConnectionRaceOutcome
                    if connect.succeeded && adbConnectSucceeded(connect) {
                        outcome = await preflight(candidate: candidate, adbPath: adbPath)
                    } else {
                        outcome = ConnectionRaceOutcome(
                            candidate: candidate,
                            preflight: nil,
                            error: connect.failureDetail
                        )
                    }
                    let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
                    await MainActor.run {
                        if outcome.succeeded {
                            log(
                                "ADB race candidate ready: \(candidate.transport.rawValue):\(candidate.adbSerial), \(elapsed)ms"
                            )
                        } else {
                            log(
                                "ADB race candidate failed: \(candidate.transport.rawValue):\(candidate.adbSerial), \(elapsed)ms, \(outcome.error ?? "unknown error")"
                            )
                        }
                    }
                    if !outcome.succeeded {
                        let disconnect = await SessionProcessRunner.run(
                            executable: adbPath,
                            arguments: ["disconnect", candidate.adbSerial],
                            timeout: 5
                        )
                        await MainActor.run {
                            if disconnect.succeeded {
                                log(
                                    "Disconnected failed ADB race candidate: \(candidate.transport.rawValue):\(candidate.adbSerial)"
                                )
                            } else {
                                log(
                                    "Failed to disconnect ADB race candidate: \(candidate.transport.rawValue):\(candidate.adbSerial), \(disconnect.failureDetail)"
                                )
                            }
                        }
                    }
                    continuation.yield(outcome)
                }
            }
        }

        var completed = 0
        var lastError = ""
        for await outcome in stream {
            completed += 1
            if outcome.succeeded {
                log(
                    "ADB connection race winner: \(outcome.candidate.transport.rawValue):\(outcome.candidate.adbSerial)"
                )
                // Successful non-winning candidates stay available; failed candidates clean themselves up.
                return outcome
            }
            lastError = outcome.error ?? lastError
            if completed == candidates.count { break }
        }
        throw ScreenSessionError.connectionRaceFailed(lastError)
    }
}
