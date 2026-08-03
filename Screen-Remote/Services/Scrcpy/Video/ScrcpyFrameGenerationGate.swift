import Foundation

/// Prevents frames from a previous scrcpy session from being rendered after
/// reconnects or parameter-driven session replacement.
final class ScrcpyFrameGenerationGate {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func beginSession() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    func invalidate() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }

    func accepts(_ frameGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return frameGeneration == generation
    }

    var currentGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }
}
