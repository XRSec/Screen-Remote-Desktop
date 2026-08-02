import AppKit
import AudioToolbox
import SwiftUI
import VideoToolbox

struct LatencyResult: Identifiable {
    let id = UUID()
    let label: String
    let samples: [Double]
    let failures: Int

    var average: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }
}

struct ConnectionLatencyTestView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appState: AppState
    let connections: [DeviceConnection]
    @State private var results: [LatencyResult] = []
    @State private var running = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("sessionLatencyTest").font(.headline)
                    Text("sessionLatencyTestCaption").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(running ? "sessionStopTest" : "sessionRunAgain") { runTests() }
                    .disabled(running)
                Button("commonDone") { presentationMode.wrappedValue.dismiss() }
            }
            .padding(16)
            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    if results.isEmpty && running {
                        ProgressView("sessionTesting").padding(30)
                    }
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.label).font(.system(size: 13, weight: .semibold))
                            Text(String(
                                format: String.localizedKey("sessionLatencySummary"),
                                result.average, result.samples.count, result.failures
                            ))
                            .font(.caption)
                            .foregroundColor(result.samples.isEmpty ? .red : .secondary)
                            if !result.samples.isEmpty {
                                Text(result.samples.map { String(format: "%.1f", $0) }.joined(separator: " · ") + " ms")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(13)
                        .appCard(radius: 10)
                    }
                }
                .padding(16)
            }
        }
        .onAppear { runTests() }
    }

    private func runTests() {
        guard !running else { return }
        running = true
        results = []
        let endpoints = connections
        let adbPath = appState.adbPath
        Task {
            let measured = await Task.detached(priority: .userInitiated) {
                endpoints.map { measure($0, adbPath: adbPath) }
            }.value
            results = measured
            running = false
        }
    }
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

struct FormPickerControl<Content: View, Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13, weight: .medium))
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .frame(width: 150)
        }
    }
}

struct AccentPickerControl: View {
    let colors: [Color]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 9) {
            ForEach(colors.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Circle()
                        .fill(colors[index])
                        .frame(width: 20, height: 20)
                        .appOverlay(Circle().stroke(Color.white, lineWidth: selection == index ? 2 : 0).padding(3))
                        .appOverlay(Circle().stroke(colors[index].opacity(0.45), lineWidth: selection == index ? 3 : 0))
                }
                .buttonStyle(.plain)
                .help("addDeviceChooseLabelColor")
            }
        }
    }
}
