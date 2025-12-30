import AVFoundation
import XCTest
@testable import ElevenLabsKit

@MainActor
private final class FakePCMPlayerNode: PCMPlayerNodeing {
    var isPlaying = false
    var currentTimeSecondsValue: Double?
    var scheduledBuffers: [AVAudioPCMBuffer] = []
    var onSchedule: (() -> Void)?

    func attach(to engine: AVAudioEngine) {}
    func connect(to engine: AVAudioEngine, format: AVAudioFormat) {}

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) async {
        self.scheduledBuffers.append(buffer)
        self.onSchedule?()
    }

    func play() {
        self.isPlaying = true
    }

    func stop() {
        self.isPlaying = false
    }

    func currentTimeSeconds() -> Double? {
        self.currentTimeSecondsValue
    }
}

final class PCMStreamingAudioPlayerTests: XCTestCase {
    @MainActor
    func testStopDuringPCMStreamReturnsInterruptedResult() async {
        let fakePlayer = FakePCMPlayerNode()
        fakePlayer.currentTimeSecondsValue = 1.25
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fakePlayer },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in }
        )
        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        let stream = AsyncThrowingStream<Data, Error> { cont in
            continuation = cont
            let samples = Data(repeating: 0, count: 44_100)
            cont.yield(samples)
        }

        let task = Task { @MainActor in
            await player.play(stream: stream, sampleRate: 44_100)
        }

        for _ in 0..<5 where fakePlayer.scheduledBuffers.isEmpty {
            await Task.yield()
        }

        let interruptedAt = player.stop()
        continuation?.finish()

        let result = await task.value
        XCTAssertFalse(result.finished)
        XCTAssertEqual(interruptedAt, 1.25)
    }
}
