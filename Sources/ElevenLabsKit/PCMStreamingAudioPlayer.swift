@preconcurrency import AVFoundation
import Foundation
import OSLog

@MainActor
public final class PCMStreamingAudioPlayer {
    public static let shared = PCMStreamingAudioPlayer()

    private let logger = Logger(subsystem: "com.steipete.clawdis", category: "talk.tts.pcm")
    private let playerFactory: () -> PCMPlayerNodeing
    private let engineFactory: () -> AVAudioEngine
    private let startEngine: (AVAudioEngine) throws -> Void
    private let stopEngine: (AVAudioEngine) -> Void
    private var engine: AVAudioEngine
    private var player: PCMPlayerNodeing
    private var format: AVAudioFormat?
    private var pendingBuffers: Int = 0
    private var inputFinished = false
    private var continuation: CheckedContinuation<StreamingPlaybackResult, Never>?

    public init() {
        self.playerFactory = { AVAudioPlayerNodeAdapter() }
        self.engineFactory = { AVAudioEngine() }
        self.startEngine = { engine in try engine.start() }
        self.stopEngine = { engine in engine.stop() }
        self.engine = engineFactory()
        self.player = playerFactory()
        player.attach(to: engine)
    }

    init(
        playerFactory: @escaping () -> PCMPlayerNodeing,
        engineFactory: @escaping () -> AVAudioEngine,
        startEngine: @escaping (AVAudioEngine) throws -> Void,
        stopEngine: @escaping (AVAudioEngine) -> Void
    ) {
        self.playerFactory = playerFactory
        self.engineFactory = engineFactory
        self.startEngine = startEngine
        self.stopEngine = stopEngine
        self.engine = engineFactory()
        self.player = playerFactory()
        player.attach(to: engine)
    }

    public func play(stream: AsyncThrowingStream<Data, Error>, sampleRate: Double) async -> StreamingPlaybackResult {
        stopInternal()

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )

        guard let format else {
            return StreamingPlaybackResult(finished: false, interruptedAt: nil)
        }
        configure(format: format)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pendingBuffers = 0
            self.inputFinished = false

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await chunk in stream {
                        await enqueuePCM(chunk, format: format)
                    }
                    finishInput()
                } catch {
                    fail(error)
                }
            }
        }
    }

    public func stop() -> Double? {
        let interruptedAt = currentTimeSeconds()
        stopInternal()
        finish(StreamingPlaybackResult(finished: false, interruptedAt: interruptedAt))
        return interruptedAt
    }

    private func configure(format: AVAudioFormat) {
        if self.format?.sampleRate != format.sampleRate || self.format?.commonFormat != format.commonFormat {
            stopEngine(engine)
            engine = engineFactory()
            player = playerFactory()
            player.attach(to: engine)
        }
        self.format = format
        player.connect(to: engine, format: format)
    }

    private func enqueuePCM(_ data: Data, format: AVAudioFormat) async {
        guard !data.isEmpty else { return }
        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        data.withUnsafeBytes { raw in
            guard let src = raw.baseAddress else { return }
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            if let dst = audioBuffer.mData {
                memcpy(dst, src, frameCount * MemoryLayout<Int16>.size)
            }
        }

        pendingBuffers += 1
        Task { @MainActor [weak self] in
            guard let self else { return }
            await player.scheduleBuffer(buffer)
            pendingBuffers = max(0, pendingBuffers - 1)
            if inputFinished, pendingBuffers == 0 {
                finish(StreamingPlaybackResult(finished: true, interruptedAt: nil))
            }
        }

        if !player.isPlaying {
            do {
                try startEngine(engine)
                player.play()
            } catch {
                logger.error("pcm engine start failed: \(error.localizedDescription, privacy: .public)")
                fail(error)
            }
        }
    }

    private func finishInput() {
        inputFinished = true
        if pendingBuffers == 0 {
            finish(StreamingPlaybackResult(finished: true, interruptedAt: nil))
        }
    }

    private func fail(_ error: Error) {
        logger.error("pcm stream failed: \(error.localizedDescription, privacy: .public)")
        finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
    }

    private func stopInternal() {
        player.stop()
        stopEngine(engine)
        pendingBuffers = 0
        inputFinished = false
    }

    private func finish(_ result: StreamingPlaybackResult) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    private func currentTimeSeconds() -> Double? {
        player.currentTimeSeconds()
    }
}
