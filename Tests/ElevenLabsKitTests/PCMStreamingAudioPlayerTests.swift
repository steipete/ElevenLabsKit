import AVFoundation
@testable import ElevenLabsKit
import Testing

@MainActor
private final class FakePCMPlayerNode: PCMPlayerNodeing {
    var isPlaying = false
    var currentTimeSecondsValue: Double?
    var scheduledBuffers: [AVAudioPCMBuffer] = []
    var onSchedule: (() -> Void)?
    var suspendScheduling = false
    var scheduleContinuations: [CheckedContinuation<Void, Never>] = []

    func attach(to _: AVAudioEngine) {}
    func connect(to _: AVAudioEngine, format _: AVAudioFormat) {}

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) async {
        scheduledBuffers.append(buffer)
        onSchedule?()
        if suspendScheduling {
            await withCheckedContinuation { continuation in
                scheduleContinuations.append(continuation)
            }
        }
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

    func resumeNextSchedule() {
        guard scheduleContinuations.isEmpty == false else { return }
        scheduleContinuations.removeFirst().resume()
    }
}

@MainActor
private final class PCMBufferSchedulingGate {
    private(set) var invocationCount = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?

    func waitIfFirst() async {
        invocationCount += 1
        guard invocationCount == 1 else { return }
        await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func resumeFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

final class PCMStreamingAudioPlayerTests {
    @MainActor @Test func `stop during PCM stream returns interrupted result`() async {
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

    @MainActor @Test func `starting new PCM stream interrupts previous playback`() async {
        let fakePlayer = FakePCMPlayerNode()
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fakePlayer },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in }
        )

        let firstStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 0, count: 4))
        }
        let firstTask = Task { @MainActor in
            await player.play(stream: firstStream, sampleRate: 44100)
        }

        for _ in 0..<5 where fakePlayer.scheduledBuffers.isEmpty {
            await Task.yield()
        }

        let secondStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish()
        }
        let secondTask = Task { @MainActor in
            await player.play(stream: secondStream, sampleRate: 44100)
        }

        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        #expect(firstResult.finished == false)
        #expect(secondResult.finished)
    }

    @MainActor @Test func `stale buffer completion does not finish replacement stream`() async {
        let fakePlayer = FakePCMPlayerNode()
        fakePlayer.suspendScheduling = true
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fakePlayer },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in }
        )

        let firstStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 0, count: 4))
        }
        let firstTask = Task { @MainActor in
            await player.play(stream: firstStream, sampleRate: 44100)
        }
        for _ in 0..<10 where fakePlayer.scheduleContinuations.count < 1 {
            await Task.yield()
        }

        let secondStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 0, count: 4))
            continuation.finish()
        }
        var secondCompleted = false
        let secondTask = Task { @MainActor in
            let result = await player.play(stream: secondStream, sampleRate: 44100)
            secondCompleted = true
            return result
        }
        for _ in 0..<10 where fakePlayer.scheduleContinuations.count < 2 {
            await Task.yield()
        }

        fakePlayer.resumeNextSchedule()
        await Task.yield()
        #expect(secondCompleted == false)

        fakePlayer.resumeNextSchedule()
        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        #expect(firstResult.finished == false)
        #expect(secondResult.finished)
    }

    @MainActor @Test func `stale buffer is not scheduled into replacement playback`() async {
        let fakePlayer = FakePCMPlayerNode()
        let schedulingGate = PCMBufferSchedulingGate()
        let player = PCMStreamingAudioPlayer(
            playerFactory: { fakePlayer },
            engineFactory: { AVAudioEngine() },
            startEngine: { _ in },
            stopEngine: { _ in },
            beforeSchedulingBuffer: { await schedulingGate.waitIfFirst() }
        )

        let firstStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 1, count: 4))
        }
        let firstTask = Task { @MainActor in
            await player.play(stream: firstStream, sampleRate: 44100)
        }
        for _ in 0..<10 where schedulingGate.invocationCount < 1 {
            await Task.yield()
        }

        let secondStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 2, count: 4))
            continuation.finish()
        }
        let secondTask = Task { @MainActor in
            await player.play(stream: secondStream, sampleRate: 44100)
        }
        for _ in 0..<10 where fakePlayer.scheduledBuffers.isEmpty {
            await Task.yield()
        }

        schedulingGate.resumeFirst()
        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        await Task.yield()
        #expect(firstResult.finished == false)
        #expect(secondResult.finished)
        #expect(fakePlayer.scheduledBuffers.count == 1)
    }
}
