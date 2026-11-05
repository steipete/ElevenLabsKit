import AVFoundation
@testable import ElevenLabsKit
import Testing

@MainActor
private final class PlaybackCompletionFake: PCMPlayerNodeing {
    var isPlaying = false
    private(set) var startedBeforeBufferScheduled = false
    private(set) var callbackTypes: [AVAudioPlayerNodeCompletionCallbackType] = []
    private var playedBackHandlers: [@Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void] = []

    func attach(to _: AVAudioEngine) {}
    func connect(to _: AVAudioEngine, format _: AVAudioFormat) {}

    func scheduleBuffer(
        _ buffer: AVAudioPCMBuffer,
        completionCallbackType: AVAudioPlayerNodeCompletionCallbackType,
        completionHandler: @escaping @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void
    ) {
        _ = buffer
        callbackTypes.append(completionCallbackType)
        playedBackHandlers.append(completionHandler)
    }

    func deliver(_ callbackType: AVAudioPlayerNodeCompletionCallbackType, index: Int = 0) {
        guard playedBackHandlers.indices.contains(index) else { return }
        playedBackHandlers[index](callbackType)
    }

    func play() {
        if callbackTypes.isEmpty {
            startedBeforeBufferScheduled = true
        }
        isPlaying = true
    }

    func stop() {
        isPlaying = false
    }

    func currentTimeSeconds() -> Double? {
        nil
    }
}

final class PCMStreamingAudioPlayerPlaybackTests {
    @MainActor @Test func `pcm play waits for dataPlayedBack instead of schedule completion`() async {
        let fake = PlaybackCompletionFake()
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fake },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in }
        )
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 0, count: 4))
            continuation.finish()
        }

        var completed = false
        let task = Task { @MainActor in
            let result = await player.play(stream: stream, sampleRate: 44100)
            completed = true
            return result
        }

        for _ in 0..<40 where fake.callbackTypes.isEmpty {
            await Task.yield()
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(fake.callbackTypes == [.dataPlayedBack])
        #expect(fake.startedBeforeBufferScheduled == false)
        #expect(fake.isPlaying)
        #expect(completed == false)

        fake.deliver(.dataConsumed)
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(completed == false)

        fake.deliver(.dataPlayedBack)
        let result = await task.value
        #expect(completed)
        #expect(result.finished)
        #expect(result.interruptedAt == nil)
    }

    @MainActor @Test func `pcm play waits until every scheduled buffer has played back`() async {
        let fake = PlaybackCompletionFake()
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fake },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in }
        )
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 1, count: 4))
            continuation.yield(Data(repeating: 2, count: 4))
            continuation.finish()
        }

        var completed = false
        let task = Task { @MainActor in
            let result = await player.play(stream: stream, sampleRate: 44100)
            completed = true
            return result
        }

        for _ in 0..<40 where fake.callbackTypes.count < 2 {
            await Task.yield()
        }
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(fake.callbackTypes == [.dataPlayedBack, .dataPlayedBack])
        #expect(completed == false)

        fake.deliver(.dataPlayedBack, index: 0)
        for _ in 0..<10 {
            await Task.yield()
        }
        #expect(completed == false)

        fake.deliver(.dataPlayedBack, index: 1)
        let result = await task.value
        #expect(result.finished)
        #expect(result.interruptedAt == nil)
    }
}
