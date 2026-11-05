import AudioToolbox
@testable import ElevenLabsKit
import Foundation
import OSLog
import Testing

private final class WeakPlayback {
    weak var value: StreamingAudioPlayback?
    init(_ value: StreamingAudioPlayback?) {
        self.value = value
    }
}

private final class TeardownProbe: @unchecked Sendable {
    struct Snapshot {
        let closes: Int
        let unsafeClose: Bool
        let unsafeStop: Bool
        let unsafeDispose: Bool
    }

    private let lock = NSLock()
    private var closes = 0
    private var parsing = false
    private var inCallback = false
    private var unsafeClose = false
    private var unsafeStop = false
    private var unsafeDispose = false
    private var clientAddress: UInt = 0

    func opened(_ client: UnsafeMutableRawPointer?) {
        lock.withLock { clientAddress = UInt(bitPattern: client) }
    }

    func client() -> UnsafeMutableRawPointer? {
        lock.withLock { UnsafeMutableRawPointer(bitPattern: clientAddress) }
    }

    func setParsing(_ value: Bool) {
        lock.withLock { parsing = value }
    }

    func setInCallback(_ value: Bool) {
        lock.withLock { inCallback = value }
    }

    func close() -> Int {
        lock.withLock {
            closes += 1
            unsafeClose = unsafeClose || parsing
            return closes
        }
    }

    func stop() {
        lock.withLock { unsafeStop = unsafeStop || parsing }
    }

    func dispose() {
        lock.withLock { unsafeDispose = unsafeDispose || inCallback }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(closes: closes, unsafeClose: unsafeClose, unsafeStop: unsafeStop, unsafeDispose: unsafeDispose)
        }
    }

    func makeBuffer(byteCapacity: UInt32) -> AudioQueueBufferRef {
        let buffer = UnsafeMutablePointer<AudioQueueBuffer>.allocate(capacity: 1)
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(byteCapacity), alignment: 1)
        buffer.initialize(to: AudioQueueBuffer(
            mAudioDataBytesCapacity: byteCapacity,
            mAudioData: data,
            mAudioDataByteSize: 0,
            mUserData: nil,
            mPacketDescriptionCapacity: 0,
            mPacketDescriptions: nil,
            mPacketDescriptionCount: 0
        ))
        return buffer
    }

    func audio() -> AudioToolboxClient {
        var audio = AudioToolboxClient.live
        audio.fileStreamOpen = { client, _, _, _, stream in
            self.opened(client)
            stream.pointee = OpaquePointer(bitPattern: 1)
            return noErr
        }
        audio.fileStreamParseBytes = { _, _, _, _ in noErr }
        audio.fileStreamGetPropertyInfo = { _, _, _, _ in -1 }
        audio.fileStreamClose = { _ in _ = self.close(); return noErr }
        audio.queueNewOutput = { _, _, _, _, _, _, queue in
            queue.pointee = OpaquePointer(bitPattern: 2)
            return noErr
        }
        audio.queueAddPropertyListener = { _, _, _, _ in noErr }
        audio.queueAllocateBuffer = { _, _, buffer in buffer.pointee = nil; return noErr }
        audio.queueStop = { _, _ in self.stop(); return noErr }
        audio.queueDispose = { _, _ in self.dispose(); return noErr }
        audio.queueGetCurrentTime = { _, _, timestamp, _ in timestamp.pointee.mSampleTime = 0; return noErr }
        audio.queueGetProperty = { _, _, data, _ in
            data.assumingMemoryBound(to: UInt32.self).pointee = 0
            return noErr
        }
        return audio
    }
}

@Suite(.serialized) final class StreamingAudioTeardownTests {
    @Test func `competing finishes close the stream once`() throws {
        let probe = TeardownProbe()
        let closing = DispatchSemaphore(value: 0)
        let releaseClose = DispatchSemaphore(value: 0)
        let closed = DispatchSemaphore(value: 0)
        var audio = probe.audio()
        audio.fileStreamClose = { _ in
            if probe.close() == 1 {
                closing.signal()
                _ = releaseClose.wait(timeout: .now() + 2)
            }
            closed.signal()
            return noErr
        }
        let playback = StreamingAudioPlayback(logger: Logger(), audio: audio)
        playback.start()
        playback.finishInput()
        defer { releaseClose.signal() }
        try #require(closing.wait(timeout: .now() + 1) == .success)

        playback.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
        #expect(probe.snapshot().closes == 1)
        releaseClose.signal()
        try #require(closed.wait(timeout: .now() + 1) == .success)
        playback.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
        #expect(probe.snapshot().closes == 1)
    }

    @Test func `finish waits for parsing and retains playback until close`() throws {
        let probe = TeardownProbe()
        let parsing = DispatchSemaphore(value: 0)
        let releaseParse = DispatchSemaphore(value: 0)
        let closed = DispatchSemaphore(value: 0)
        var audio = probe.audio()
        audio.fileStreamParseBytes = { _, _, _, _ in
            probe.setParsing(true)
            parsing.signal()
            _ = releaseParse.wait(timeout: .now() + 2)
            probe.setParsing(false)
            return noErr
        }
        audio.fileStreamClose = { _ in _ = probe.close(); closed.signal(); return noErr }
        var playback: StreamingAudioPlayback? = StreamingAudioPlayback(logger: Logger(), audio: audio)
        let weakPlayback = WeakPlayback(playback)
        playback?.start()
        playback?.append(Data([0]))
        defer { releaseParse.signal() }
        try #require(parsing.wait(timeout: .now() + 1) == .success)

        playback?.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
        playback = nil
        #expect(weakPlayback.value != nil)
        #expect(probe.snapshot().closes == 0)
        releaseParse.signal()
        try #require(closed.wait(timeout: .now() + 1) == .success)
        #expect(probe.snapshot().closes == 1)
        #expect(!probe.snapshot().unsafeClose)
    }

    @Test func `stop and input completion do not dispose an active parser`() throws {
        let probe = TeardownProbe()
        let parsing = DispatchSemaphore(value: 0)
        let releaseParse = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let closed = DispatchSemaphore(value: 0)
        var audio = probe.audio()
        audio.fileStreamParseBytes = { _, _, _, _ in
            probe.setParsing(true)
            parsing.signal()
            _ = releaseParse.wait(timeout: .now() + 2)
            probe.setParsing(false)
            return noErr
        }
        audio.fileStreamClose = { _ in _ = probe.close(); closed.signal(); return noErr }
        let playback = StreamingAudioPlayback(logger: Logger(), audio: audio)
        playback.start()
        var format = AudioStreamBasicDescription()
        format.mSampleRate = 44100
        playback.setupQueueIfNeeded(format)
        playback.append(Data([0]))
        defer { releaseParse.signal() }
        try #require(parsing.wait(timeout: .now() + 1) == .success)

        DispatchQueue.global().async {
            _ = playback.stop(immediate: true)
            playback.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
            stopped.signal()
        }
        playback.finishInput()
        playback.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
        #expect(probe.snapshot().closes == 0)
        releaseParse.signal()
        try #require(stopped.wait(timeout: .now() + 1) == .success)
        try #require(closed.wait(timeout: .now() + 1) == .success)
        #expect(probe.snapshot().closes == 1)
        #expect(!probe.snapshot().unsafeClose)
        #expect(!probe.snapshot().unsafeStop)
    }

    @Test func `immediate stop wakes a parser waiting for an audio buffer`() throws {
        let probe = TeardownProbe()
        let waiting = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let closed = DispatchSemaphore(value: 0)
        let enqueued = OSAllocatedUnfairLock(initialState: 0)
        let started = OSAllocatedUnfairLock(initialState: false)
        let queueBufferBytes = 32 * 1024
        let blockedFor = OSAllocatedUnfairLock(initialState: 0.0)
        var audio = probe.audio()
        audio.queueAllocateBuffer = { _, size, outBuffer in
            outBuffer.pointee = probe.makeBuffer(byteCapacity: size)
            return noErr
        }
        audio.queueEnqueueBuffer = { _, _, _, _ in
            enqueued.withLock { $0 += 1 }
            return noErr
        }
        audio.queueStart = { _, _ in
            started.withLock { $0 = true }
            return noErr
        }
        audio.fileStreamParseBytes = { _, _, _, _ in
            guard let client = probe.client() else { return -1 }
            let playback = Unmanaged<StreamingAudioPlayback>.fromOpaque(client).takeUnretainedValue()
            let packet = [UInt8](repeating: 0x11, count: queueBufferBytes)
            probe.setParsing(true)
            packet.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                for _ in 0..<6 {
                    playback.handlePackets(
                        numberBytes: UInt32(packet.count),
                        numberPackets: 1,
                        inputData: base,
                        packetDescriptions: nil
                    )
                }
                waiting.signal()
                let blockedAt = Date()
                playback.handlePackets(
                    numberBytes: UInt32(packet.count),
                    numberPackets: 1,
                    inputData: base,
                    packetDescriptions: nil
                )
                blockedFor.withLock { $0 = Date().timeIntervalSince(blockedAt) }
            }
            probe.setParsing(false)
            return noErr
        }
        audio.fileStreamClose = { _ in _ = probe.close(); closed.signal(); return noErr }
        let playback = StreamingAudioPlayback(logger: Logger(), audio: audio)
        playback.start()
        var format = AudioStreamBasicDescription()
        format.mSampleRate = 44100
        playback.setupQueueIfNeeded(format)
        playback.append(Data([0]))
        defer { playback.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil)) }
        try #require(waiting.wait(timeout: .now() + 1) == .success)
        Thread.sleep(forTimeInterval: 0.05)

        DispatchQueue.global().async {
            _ = playback.stop(immediate: true)
            playback.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
            stopped.signal()
        }
        try #require(stopped.wait(timeout: .now() + 1) == .success)
        try #require(closed.wait(timeout: .now() + 1) == .success)
        #expect(probe.snapshot().closes == 1)
        #expect(!probe.snapshot().unsafeClose)
        #expect(!probe.snapshot().unsafeStop)
        #expect(started.withLock { $0 })
        #expect(enqueued.withLock { $0 } == 3)
        #expect(blockedFor.withLock { $0 } > 0.04)
    }

    @Test func `queue callback defers disposal until the callback returns`() throws {
        let probe = TeardownProbe()
        let closed = DispatchSemaphore(value: 0)
        var audio = probe.audio()
        audio.queueStop = { queue, _ in
            probe.setInCallback(true)
            isRunningCallbackProc(inUserData: probe.client(), inAQ: queue, inID: kAudioQueueProperty_IsRunning)
            probe.setInCallback(false)
            return noErr
        }
        audio.fileStreamClose = { _ in _ = probe.close(); closed.signal(); return noErr }
        let playback = StreamingAudioPlayback(logger: Logger(), audio: audio)
        playback.start()
        var format = AudioStreamBasicDescription()
        format.mSampleRate = 44100
        playback.setupQueueIfNeeded(format)
        playback.finishInput()

        try #require(closed.wait(timeout: .now() + 1) == .success)
        #expect(probe.snapshot().closes == 1)
        #expect(!probe.snapshot().unsafeDispose)
    }
}
