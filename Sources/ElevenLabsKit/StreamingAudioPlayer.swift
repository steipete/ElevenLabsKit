import Foundation
import OSLog

public struct StreamingPlaybackResult: Sendable {
    public let finished: Bool
    public let interruptedAt: Double?

    public init(finished: Bool, interruptedAt: Double?) {
        self.finished = finished
        self.interruptedAt = interruptedAt
    }
}

@MainActor
public final class StreamingAudioPlayer: NSObject {
    public static let shared = StreamingAudioPlayer()

    private let logger = Logger(subsystem: "com.steipete.clawdis", category: "talk.tts.stream")
    private var playback: StreamingAudioPlayback?

    public func play(stream: AsyncThrowingStream<Data, Error>) async -> StreamingPlaybackResult {
        stopInternal()

        let playback = StreamingAudioPlayback(logger: logger)
        self.playback = playback

        return await withCheckedContinuation { continuation in
            playback.setContinuation(continuation)
            playback.start()

            Task.detached {
                do {
                    for try await chunk in stream {
                        playback.append(chunk)
                    }
                    playback.finishInput()
                } catch {
                    playback.fail(error)
                }
            }
        }
    }

    public func stop() -> Double? {
        guard let playback else { return nil }
        let interruptedAt = playback.stop(immediate: true)
        finish(playback: playback, result: StreamingPlaybackResult(finished: false, interruptedAt: interruptedAt))
        return interruptedAt
    }

    private func stopInternal() {
        guard let playback else { return }
        let interruptedAt = playback.stop(immediate: true)
        finish(playback: playback, result: StreamingPlaybackResult(finished: false, interruptedAt: interruptedAt))
    }

    private func finish(playback: StreamingAudioPlayback, result: StreamingPlaybackResult) {
        playback.finish(result)
        guard self.playback === playback else { return }
        self.playback = nil
    }
}
