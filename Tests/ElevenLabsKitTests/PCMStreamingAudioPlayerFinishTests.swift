import AVFoundation
import XCTest
@testable import ElevenLabsKit

@MainActor
private final class FakePCMPlayerNodeForFinish: PCMPlayerNodeing {
    var isPlaying = false
    var currentTimeSecondsValue: Double?
    var scheduledBuffers: [AVAudioPCMBuffer] = []

    func attach(to engine: AVAudioEngine) {}
    func connect(to engine: AVAudioEngine, format: AVAudioFormat) {}

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) async {
        self.scheduledBuffers.append(buffer)
        await Task.yield()
    }

    func play() { self.isPlaying = true }
    func stop() { self.isPlaying = false }
    func currentTimeSeconds() -> Double? { self.currentTimeSecondsValue }
}

final class PCMStreamingAudioPlayerFinishTests: XCTestCase {
    @MainActor
    func testPCMStreamFinishesWhenInputEnds() async {
        let fakePlayer = FakePCMPlayerNodeForFinish()
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fakePlayer },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in }
        )

        let stream = AsyncThrowingStream<Data, Error> { cont in
            cont.yield(Data(repeating: 0, count: 44_100))
            cont.finish()
        }

        let result = await player.play(stream: stream, sampleRate: 44_100)
        XCTAssertTrue(result.finished)
        XCTAssertNil(result.interruptedAt)
        XCTAssertFalse(fakePlayer.scheduledBuffers.isEmpty)
    }

    @MainActor
    func testEmptyChunksAreIgnored() async {
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

        let result = await player.play(stream: stream, sampleRate: 44_100)
        XCTAssertTrue(result.finished)
        XCTAssertEqual(fakePlayer.scheduledBuffers.count, 1)
    }
}

