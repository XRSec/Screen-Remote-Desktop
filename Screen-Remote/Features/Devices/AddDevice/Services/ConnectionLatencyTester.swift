import Foundation

struct LatencyResult: Identifiable {
    let id = UUID()
    let label: String
    let samples: [Double]
    let failures: Int

    var average: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }
}

func measure(_ connection: DeviceConnection, adbPath: String) -> LatencyResult {
    var samples: [Double] = []
    var failures = 0
    for _ in 0..<10 {
        let start = CFAbsoluteTimeGetCurrent()
        let process = Process()
        if connection.transport == .tcp {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = ["-z", "-G", "2", connection.host, String(connection.port)]
        } else {
            process.executableURL = URL(fileURLWithPath: adbPath.isEmpty ? "/usr/bin/env" : adbPath)
            let target = connection.transport == .usb ? connection.serial : connection.host
            process.arguments = (adbPath.isEmpty ? ["adb"] : []) + ["-s", target, "shell", "echo", "ok"]
        }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                samples.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
            } else {
                failures += 1
            }
        } catch {
            failures += 1
        }
    }
    return LatencyResult(label: connection.displayAddress, samples: samples, failures: failures)
}
