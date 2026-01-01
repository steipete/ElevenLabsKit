import AVFoundation
@testable import ElevenLabsKit
import Testing

@MainActor
private final class FakePCMPlayerNode: PCMPlayerNodeing {
    var isPlaying = false
    var currentTimeSecondsValue: Double?
    var scheduledBuffers: [AVAudioPCMBuffer] = []
    var onSchedule: (() -> Void)?

    func attach(to _: AVAudioEngine) {}
    func connect(to _: AVAudioEngine, format _: AVAudioFormat) {}

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) async {
        scheduledBuffers.append(buffer)
        onSchedule?()
    }

    func play() {
        isPlaying = true
    }

    func stop() {
        isPlaying = false
    }

    func currentTimeSeconds() -> Double? {
        currentTimeSecondsValue
    }
}

@Suite final class PCMStreamingAudioPlayerTests {
    @MainActor @Test func stopDuringPCMStreamReturnsInterruptedResult() async {
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
            let samples = Data(repeating: 0, count: 44100)
            cont.yield(samples)
        }

        let task = Task { @MainActor in
            await player.play(stream: stream, sampleRate: 44100)
        }

        for _ in 0..<5 where fakePlayer.scheduledBuffers.isEmpty {
            await Task.yield()
        }

        let interruptedAt = player.stop()
        continuation?.finish()

        let result = await task.value
        #expect(result.finished == false)
        #expect(interruptedAt == 1.25)
    }
}
