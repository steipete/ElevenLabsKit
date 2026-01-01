import AVFoundation
@testable import ElevenLabsKit
import Testing

@MainActor
private final class FakePCMPlayerNodeForFinish: PCMPlayerNodeing {
    var isPlaying = false
    var currentTimeSecondsValue: Double?
    var scheduledBuffers: [AVAudioPCMBuffer] = []

    func attach(to _: AVAudioEngine) {}
    func connect(to _: AVAudioEngine, format _: AVAudioFormat) {}

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) async {
        scheduledBuffers.append(buffer)
        await Task.yield()
    }

    func play() { isPlaying = true }
    func stop() { isPlaying = false }
    func currentTimeSeconds() -> Double? { currentTimeSecondsValue }
}

@Suite final class PCMStreamingAudioPlayerFinishTests {
    @MainActor @Test func pcmStreamFinishesWhenInputEnds() async {
        let fakePlayer = FakePCMPlayerNodeForFinish()
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fakePlayer },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in }
        )

        let stream = AsyncThrowingStream<Data, Error> { cont in
            cont.yield(Data(repeating: 0, count: 44100))
            cont.finish()
        }

        let result = await player.play(stream: stream, sampleRate: 44100)
        #expect(result.finished)
        #expect(result.interruptedAt == nil)
        #expect(fakePlayer.scheduledBuffers.isEmpty == false)
    }

    @MainActor @Test func emptyChunksAreIgnored() async {
        let fakePlayer = FakePCMPlayerNodeForFinish()
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fakePlayer },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in }
        )

        let stream = AsyncThrowingStream<Data, Error> { cont in
            cont.yield(Data())
            cont.yield(Data(repeating: 0, count: 4))
            cont.finish()
        }

        let result = await player.play(stream: stream, sampleRate: 44100)
        #expect(result.finished)
        #expect(fakePlayer.scheduledBuffers.count == 1)
    }
}
