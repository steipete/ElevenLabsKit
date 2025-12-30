@preconcurrency import AVFoundation
import Foundation
import OSLog

@MainActor
public final class PCMStreamingAudioPlayer {
    public static let shared = PCMStreamingAudioPlayer()

    private let logger = Logger(subsystem: "com.steipete.clawdis", category: "talk.tts.pcm")
    private let playerFactory: () -> PCMPlayerNodeing
    private var engine = AVAudioEngine()
    private var player: PCMPlayerNodeing
    private var format: AVAudioFormat?
    private var pendingBuffers: Int = 0
    private var inputFinished = false
    private var continuation: CheckedContinuation<StreamingPlaybackResult, Never>?

    public init(playerFactory: @escaping () -> PCMPlayerNodeing = { AVAudioPlayerNodeAdapter() }) {
        self.playerFactory = playerFactory
        self.player = playerFactory()
        self.player.attach(to: self.engine)
    }

    public func play(stream: AsyncThrowingStream<Data, Error>, sampleRate: Double) async -> StreamingPlaybackResult {
        self.stopInternal()

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true)

        guard let format else {
            return StreamingPlaybackResult(finished: false, interruptedAt: nil)
        }
        self.configure(format: format)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pendingBuffers = 0
            self.inputFinished = false

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await chunk in stream {
                        await self.enqueuePCM(chunk, format: format)
                    }
                    self.finishInput()
                } catch {
                    self.fail(error)
                }
            }
        }
    }

    public func stop() -> Double? {
        let interruptedAt = self.currentTimeSeconds()
        self.stopInternal()
        self.finish(StreamingPlaybackResult(finished: false, interruptedAt: interruptedAt))
        return interruptedAt
    }

    private func configure(format: AVAudioFormat) {
        if self.format?.sampleRate != format.sampleRate || self.format?.commonFormat != format.commonFormat {
            self.engine.stop()
            self.engine = AVAudioEngine()
            self.player = self.playerFactory()
            self.player.attach(to: self.engine)
        }
        self.format = format
        self.player.connect(to: self.engine, format: format)
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

        self.pendingBuffers += 1
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.player.scheduleBuffer(buffer)
            self.pendingBuffers = max(0, self.pendingBuffers - 1)
            if self.inputFinished && self.pendingBuffers == 0 {
                self.finish(StreamingPlaybackResult(finished: true, interruptedAt: nil))
            }
        }

        if !self.player.isPlaying {
            do {
                try self.engine.start()
                self.player.play()
            } catch {
                self.logger.error("pcm engine start failed: \(error.localizedDescription, privacy: .public)")
                self.fail(error)
            }
        }
    }

    private func finishInput() {
        self.inputFinished = true
        if self.pendingBuffers == 0 {
            self.finish(StreamingPlaybackResult(finished: true, interruptedAt: nil))
        }
    }

    private func fail(_ error: Error) {
        self.logger.error("pcm stream failed: \(error.localizedDescription, privacy: .public)")
        self.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
    }

    private func stopInternal() {
        self.player.stop()
        self.engine.stop()
        self.pendingBuffers = 0
        self.inputFinished = false
    }

    private func finish(_ result: StreamingPlaybackResult) {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    private func currentTimeSeconds() -> Double? {
        self.player.currentTimeSeconds()
    }
}
