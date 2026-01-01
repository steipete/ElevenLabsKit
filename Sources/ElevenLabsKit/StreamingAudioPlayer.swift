import AudioToolbox
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

struct AudioToolboxClient: Sendable {
    var fileStreamOpen: @Sendable (
        UnsafeMutableRawPointer?,
        AudioFileStream_PropertyListenerProc,
        AudioFileStream_PacketsProc,
        AudioFileTypeID,
        UnsafeMutablePointer<AudioFileStreamID?>) -> OSStatus

    var fileStreamParseBytes: @Sendable (
        AudioFileStreamID,
        UInt32,
        UnsafeRawPointer?,
        AudioFileStreamParseFlags) -> OSStatus

    var fileStreamGetPropertyInfo: @Sendable (
        AudioFileStreamID,
        AudioFileStreamPropertyID,
        UnsafeMutablePointer<UInt32>,
        UnsafeMutablePointer<DarwinBoolean>) -> OSStatus

    var fileStreamGetProperty: @Sendable (
        AudioFileStreamID,
        AudioFileStreamPropertyID,
        UnsafeMutablePointer<UInt32>,
        UnsafeMutableRawPointer) -> OSStatus

    var fileStreamClose: @Sendable (AudioFileStreamID) -> OSStatus

    var queueNewOutput: @Sendable (
        UnsafeMutablePointer<AudioStreamBasicDescription>,
        AudioQueueOutputCallback,
        UnsafeMutableRawPointer?,
        CFRunLoop?,
        CFString?,
        UInt32,
        UnsafeMutablePointer<AudioQueueRef?>) -> OSStatus

    var queueAddPropertyListener: @Sendable (
        AudioQueueRef,
        AudioQueuePropertyID,
        AudioQueuePropertyListenerProc,
        UnsafeMutableRawPointer?) -> OSStatus

    var queueAllocateBuffer: @Sendable (AudioQueueRef, UInt32, UnsafeMutablePointer<AudioQueueBufferRef?>) -> OSStatus
    var queueEnqueueBuffer: @Sendable (
        AudioQueueRef,
        AudioQueueBufferRef,
        UInt32,
        UnsafePointer<AudioStreamPacketDescription>?) -> OSStatus
    var queueStart: @Sendable (AudioQueueRef, UnsafePointer<AudioTimeStamp>?) -> OSStatus
    var queueStop: @Sendable (AudioQueueRef, Bool) -> OSStatus
    var queueDispose: @Sendable (AudioQueueRef, Bool) -> OSStatus
    var queueSetProperty: @Sendable (AudioQueueRef, AudioQueuePropertyID, UnsafeRawPointer, UInt32) -> OSStatus
    var queueGetCurrentTime: @Sendable (
        AudioQueueRef,
        AudioQueueTimelineRef?,
        UnsafeMutablePointer<AudioTimeStamp>,
        UnsafeMutablePointer<DarwinBoolean>?) -> OSStatus
    var queueGetProperty: @Sendable (
        AudioQueueRef,
        AudioQueuePropertyID,
        UnsafeMutableRawPointer,
        UnsafeMutablePointer<UInt32>) -> OSStatus

    static let live = AudioToolboxClient(
        fileStreamOpen: { clientData, propertyProc, packetsProc, fileType, outStream in
            AudioFileStreamOpen(clientData, propertyProc, packetsProc, fileType, outStream)
        },
        fileStreamParseBytes: { stream, count, data, flags in
            AudioFileStreamParseBytes(stream, count, data, flags)
        },
        fileStreamGetPropertyInfo: { stream, propertyID, size, writable in
            AudioFileStreamGetPropertyInfo(stream, propertyID, size, writable)
        },
        fileStreamGetProperty: { stream, propertyID, size, outData in
            AudioFileStreamGetProperty(stream, propertyID, size, outData)
        },
        fileStreamClose: { stream in
            AudioFileStreamClose(stream)
        },
        queueNewOutput: { format, callback, userData, runLoop, runLoopMode, flags, outQueue in
            AudioQueueNewOutput(format, callback, userData, runLoop, runLoopMode, flags, outQueue)
        },
        queueAddPropertyListener: { queue, propertyID, listener, userData in
            AudioQueueAddPropertyListener(queue, propertyID, listener, userData)
        },
        queueAllocateBuffer: { queue, size, outBuffer in
            AudioQueueAllocateBuffer(queue, size, outBuffer)
        },
        queueEnqueueBuffer: { queue, buffer, packetCount, packetDescs in
            AudioQueueEnqueueBuffer(queue, buffer, packetCount, packetDescs)
        },
        queueStart: { queue, startTime in
            AudioQueueStart(queue, startTime)
        },
        queueStop: { queue, immediate in
            AudioQueueStop(queue, immediate)
        },
        queueDispose: { queue, immediate in
            AudioQueueDispose(queue, immediate)
        },
        queueSetProperty: { queue, propertyID, data, size in
            AudioQueueSetProperty(queue, propertyID, data, size)
        },
        queueGetCurrentTime: { queue, timeline, outTimeStamp, outDiscontinuity in
            AudioQueueGetCurrentTime(queue, timeline, outTimeStamp, outDiscontinuity)
        },
        queueGetProperty: { queue, propertyID, outData, ioDataSize in
            AudioQueueGetProperty(queue, propertyID, outData, ioDataSize)
        }
    )
}

@MainActor
public final class StreamingAudioPlayer: NSObject {
    public static let shared = StreamingAudioPlayer()

    private let logger = Logger(subsystem: "com.steipete.clawdis", category: "talk.tts.stream")
    private var playback: StreamingAudioPlayback?

    public func play(stream: AsyncThrowingStream<Data, Error>) async -> StreamingPlaybackResult {
        self.stopInternal()

        let playback = StreamingAudioPlayback(logger: self.logger)
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
        self.finish(playback: playback, result: StreamingPlaybackResult(finished: false, interruptedAt: interruptedAt))
        return interruptedAt
    }

    private func stopInternal() {
        guard let playback else { return }
        let interruptedAt = playback.stop(immediate: true)
        self.finish(playback: playback, result: StreamingPlaybackResult(finished: false, interruptedAt: interruptedAt))
    }

    private func finish(playback: StreamingAudioPlayback, result: StreamingPlaybackResult) {
        playback.finish(result)
        guard self.playback === playback else { return }
        self.playback = nil
    }
}

final class StreamingAudioPlayback: @unchecked Sendable {
    private static let bufferCount: Int = 3
    private static let bufferSize: Int = 32 * 1024

    private let logger: Logger
    private let lock = NSLock()
    fileprivate let audio: AudioToolboxClient
    private let scheduleParseWork: (@escaping @Sendable () -> Void) -> Void
    fileprivate let bufferLock = NSLock()
    fileprivate let bufferSemaphore = DispatchSemaphore(value: bufferCount)

    private var continuation: CheckedContinuation<StreamingPlaybackResult, Never>?
    private var finished = false

    private var audioFileStream: AudioFileStreamID?
    private var audioQueue: AudioQueueRef?
    fileprivate var audioFormat: AudioStreamBasicDescription?
    fileprivate var maxPacketSize: UInt32 = 0

    fileprivate var availableBuffers: [AudioQueueBufferRef] = []
    private var currentBuffer: AudioQueueBufferRef?
    private var currentBufferSize: Int = 0
    private var currentPacketDescs: [AudioStreamPacketDescription] = []

    private var isRunning = false
    fileprivate var inputFinished = false
    private var startRequested = false

    private var sampleRate: Double = 0

    init(
        logger: Logger,
        audio: AudioToolboxClient = .live,
        scheduleParseWork: ((@escaping @Sendable () -> Void) -> Void)? = nil)
    {
        self.logger = logger
        self.audio = audio
        if let scheduleParseWork {
            self.scheduleParseWork = scheduleParseWork
        } else {
            let parseQueue = DispatchQueue(label: "talk.stream.parse")
            self.scheduleParseWork = { work in parseQueue.async(execute: work) }
        }
    }

    func setContinuation(_ continuation: CheckedContinuation<StreamingPlaybackResult, Never>) {
        self.lock.lock()
        self.continuation = continuation
        self.lock.unlock()
    }

    func start() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = self.audio.fileStreamOpen(
            selfPtr,
            propertyListenerProc,
            packetsProc,
            kAudioFileMP3Type,
            &self.audioFileStream)
        if status != noErr {
            self.logger.error("talk stream open failed: \(status)")
            self.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
        }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        self.scheduleParseWork { [weak self] in
            guard let self else { return }
            guard let audioFileStream = self.audioFileStream else { return }
            let status = data.withUnsafeBytes { bytes in
                self.audio.fileStreamParseBytes(
                    audioFileStream,
                    UInt32(bytes.count),
                    bytes.baseAddress,
                    [])
            }
            if status != noErr {
                self.logger.error("talk stream parse failed: \(status)")
                self.fail(NSError(domain: "StreamingAudio", code: Int(status)))
            }
        }
    }

    func finishInput() {
        self.scheduleParseWork { [weak self] in
            guard let self else { return }
            self.inputFinished = true
            if self.audioQueue == nil {
                self.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
                return
            }
            self.enqueueCurrentBuffer(flushOnly: true)
            _ = self.stop(immediate: false)
        }
    }

    func fail(_ error: Error) {
        self.logger.error("talk stream failed: \(error.localizedDescription, privacy: .public)")
        _ = self.stop(immediate: true)
        self.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
    }

    func stop(immediate: Bool) -> Double? {
        guard let audioQueue else { return nil }
        let interruptedAt = self.currentTimeSeconds()
        _ = self.audio.queueStop(audioQueue, immediate)
        return interruptedAt
    }

    fileprivate func finish(_ result: StreamingPlaybackResult) {
        let continuation: CheckedContinuation<StreamingPlaybackResult, Never>?
        self.lock.lock()
        if self.finished {
            continuation = nil
        } else {
            self.finished = true
            continuation = self.continuation
            self.continuation = nil
        }
        self.lock.unlock()

        continuation?.resume(returning: result)
        self.teardown()
    }

    private func teardown() {
        if let audioQueue {
            _ = self.audio.queueDispose(audioQueue, true)
            self.audioQueue = nil
        }
        if let audioFileStream {
            _ = self.audio.fileStreamClose(audioFileStream)
            self.audioFileStream = nil
        }
        self.bufferLock.lock()
        self.availableBuffers.removeAll()
        self.bufferLock.unlock()
        self.currentBuffer = nil
        self.currentPacketDescs.removeAll()
    }

    func setupQueueIfNeeded(_ asbd: AudioStreamBasicDescription) {
        guard self.audioQueue == nil else { return }

        var format = asbd
        self.audioFormat = format
        self.sampleRate = format.mSampleRate

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = self.audio.queueNewOutput(
            &format,
            outputCallbackProc,
            selfPtr,
            nil,
            nil,
            0,
            &self.audioQueue)
        if status != noErr {
            self.logger.error("talk queue create failed: \(status)")
            self.finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
            return
        }

        if let audioQueue {
            _ = self.audio.queueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, isRunningCallbackProc, selfPtr)
        }

        if let audioFileStream {
            var cookieSize: UInt32 = 0
            var writable: DarwinBoolean = false
            let cookieStatus = self.audio.fileStreamGetPropertyInfo(
                audioFileStream,
                kAudioFileStreamProperty_MagicCookieData,
                &cookieSize,
                &writable)
            if cookieStatus == noErr, cookieSize > 0, let audioQueue {
                var cookie = [UInt8](repeating: 0, count: Int(cookieSize))
                let readStatus = cookie.withUnsafeMutableBytes { bytes -> OSStatus in
                    guard let base = bytes.baseAddress else { return -1 }
                    return self.audio.fileStreamGetProperty(
                        audioFileStream,
                        kAudioFileStreamProperty_MagicCookieData,
                        &cookieSize,
                        base)
                }
                if readStatus == noErr {
                    _ = self.audio.queueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookie, cookieSize)
                }
            }
        }

        if let audioQueue {
            for _ in 0..<Self.bufferCount {
                var buffer: AudioQueueBufferRef?
                let allocStatus = self.audio.queueAllocateBuffer(audioQueue, UInt32(Self.bufferSize), &buffer)
                if allocStatus == noErr, let buffer {
                    self.bufferLock.lock()
                    self.availableBuffers.append(buffer)
                    self.bufferLock.unlock()
                }
            }
        }
    }

    private func enqueueCurrentBuffer(flushOnly: Bool = false) {
        guard let audioQueue, let buffer = self.currentBuffer else { return }
        guard self.currentBufferSize > 0 else { return }

        buffer.pointee.mAudioDataByteSize = UInt32(self.currentBufferSize)
        let packetCount = UInt32(self.currentPacketDescs.count)

        let status = self.currentPacketDescs.withUnsafeBufferPointer { descPtr in
            self.audio.queueEnqueueBuffer(audioQueue, buffer, packetCount, descPtr.baseAddress)
        }
        if status != noErr {
            self.logger.error("talk queue enqueue failed: \(status)")
        } else {
            if !self.startRequested {
                self.startRequested = true
                let startStatus = self.audio.queueStart(audioQueue, nil)
                if startStatus != noErr {
                    self.logger.error("talk queue start failed: \(startStatus)")
                }
            }
        }

        self.currentBuffer = nil
        self.currentBufferSize = 0
        self.currentPacketDescs.removeAll(keepingCapacity: true)
        if !flushOnly {
            self.bufferLock.lock()
            var next = self.availableBuffers.popLast()
            self.bufferLock.unlock()
            if next == nil {
                self.bufferSemaphore.wait()
                self.bufferLock.lock()
                next = self.availableBuffers.popLast()
                self.bufferLock.unlock()
            }
            if let next { self.currentBuffer = next }
        }
    }

    func handlePackets(
        numberBytes: UInt32,
        numberPackets: UInt32,
        inputData: UnsafeRawPointer,
        packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?)
    {
        if self.audioQueue == nil, let format = self.audioFormat {
            self.setupQueueIfNeeded(format)
        }

        if self.audioQueue == nil {
            return
        }

        if self.currentBuffer == nil {
            self.bufferLock.lock()
            self.currentBuffer = self.availableBuffers.popLast()
            self.bufferLock.unlock()
            if self.currentBuffer == nil {
                self.bufferSemaphore.wait()
                self.bufferLock.lock()
                self.currentBuffer = self.availableBuffers.popLast()
                self.bufferLock.unlock()
            }
            self.currentBufferSize = 0
            self.currentPacketDescs.removeAll(keepingCapacity: true)
        }

        let bytes = inputData.assumingMemoryBound(to: UInt8.self)
        let packetCount = Int(numberPackets)
        for index in 0..<packetCount {
            let packetOffset: Int
            let packetSize: Int

            if let packetDescriptions {
                packetOffset = Int(packetDescriptions[index].mStartOffset)
                packetSize = Int(packetDescriptions[index].mDataByteSize)
            } else {
                let size = Int(numberBytes) / packetCount
                packetOffset = index * size
                packetSize = size
            }

            if packetSize > Self.bufferSize {
                continue
            }

            if self.currentBufferSize + packetSize > Self.bufferSize {
                self.enqueueCurrentBuffer()
            }

            guard let buffer = self.currentBuffer else { continue }
            let dest = buffer.pointee.mAudioData.advanced(by: self.currentBufferSize)
            memcpy(dest, bytes.advanced(by: packetOffset), packetSize)

            let desc = AudioStreamPacketDescription(
                mStartOffset: Int64(self.currentBufferSize),
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(packetSize))
            self.currentPacketDescs.append(desc)
            self.currentBufferSize += packetSize
        }
    }

    private func currentTimeSeconds() -> Double? {
        guard let audioQueue, sampleRate > 0 else { return nil }
        var timeStamp = AudioTimeStamp()
        let status = self.audio.queueGetCurrentTime(audioQueue, nil, &timeStamp, nil)
        if status != noErr { return nil }
        if timeStamp.mSampleTime.isNaN { return nil }
        return timeStamp.mSampleTime / sampleRate
    }
}

func propertyListenerProc(
    inClientData: UnsafeMutableRawPointer,
    inAudioFileStream: AudioFileStreamID,
    inPropertyID: AudioFileStreamPropertyID,
    ioFlags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>)
{
    let playback = Unmanaged<StreamingAudioPlayback>.fromOpaque(inClientData).takeUnretainedValue()

    if inPropertyID == kAudioFileStreamProperty_DataFormat {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = playback.audio.fileStreamGetProperty(inAudioFileStream, inPropertyID, &size, &format)
        if status == noErr {
            playback.audioFormat = format
            playback.setupQueueIfNeeded(format)
        }
    } else if inPropertyID == kAudioFileStreamProperty_PacketSizeUpperBound {
        var maxPacketSize: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = playback.audio.fileStreamGetProperty(inAudioFileStream, inPropertyID, &size, &maxPacketSize)
        if status == noErr {
            playback.maxPacketSize = maxPacketSize
        }
    }
}

func packetsProc(
    inClientData: UnsafeMutableRawPointer,
    inNumberBytes: UInt32,
    inNumberPackets: UInt32,
    inInputData: UnsafeRawPointer,
    inPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?)
{
    let playback = Unmanaged<StreamingAudioPlayback>.fromOpaque(inClientData).takeUnretainedValue()
    playback.handlePackets(
        numberBytes: inNumberBytes,
        numberPackets: inNumberPackets,
        inputData: inInputData,
        packetDescriptions: inPacketDescriptions)
}

func outputCallbackProc(
    inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef)
{
    guard let inUserData else { return }
    let playback = Unmanaged<StreamingAudioPlayback>.fromOpaque(inUserData).takeUnretainedValue()
    playback.bufferLock.lock()
    playback.availableBuffers.append(inBuffer)
    playback.bufferLock.unlock()
    playback.bufferSemaphore.signal()
}

func isRunningCallbackProc(
    inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inID: AudioQueuePropertyID)
{
    guard let inUserData else { return }
    guard inID == kAudioQueueProperty_IsRunning else { return }

    let playback = Unmanaged<StreamingAudioPlayback>.fromOpaque(inUserData).takeUnretainedValue()
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = playback.audio.queueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &running, &size)
    if status != noErr { return }

    if running == 0, playback.inputFinished {
        playback.finish(StreamingPlaybackResult(finished: true, interruptedAt: nil))
    }
}
