@testable import ElevenLabsKit
import Foundation
import Testing

private final class StreamTerminationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false

    func markTerminated() {
        lock.lock()
        terminated = true
        lock.unlock()
    }

    func isTerminated() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }
}

final class StreamingAudioPlayerTests {
    @MainActor @Test func `stop cancels stream consumption`() async {
        let termination = StreamTerminationFlag()
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.onTermination = { _ in termination.markTerminated() }
        }
        let player = StreamingAudioPlayer()
        let playbackTask = Task { @MainActor in
            await player.play(stream: stream)
        }

        await Task.yield()
        _ = player.stop()

        let result = await playbackTask.value
        for _ in 0..<10 where !termination.isTerminated() {
            await Task.yield()
        }
        #expect(result.finished == false)
        #expect(termination.isTerminated())
    }
}
