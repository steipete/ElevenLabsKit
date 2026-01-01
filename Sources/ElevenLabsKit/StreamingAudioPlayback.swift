import AudioToolbox
import Foundation
import OSLog

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

    fileprivate var inputFinished = false
    private var startRequested = false

    private var sampleRate: Double = 0

    init(
        logger: Logger,
        audio: AudioToolboxClient = .live,
        scheduleParseWork: ((@escaping @Sendable () -> Void) -> Void)? = nil
    ) {
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
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func start() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = audio.fileStreamOpen(
            selfPtr,
            propertyListenerProc,
            packetsProc,
            kAudioFileMP3Type,
            &audioFileStream
        )
        if status != noErr {
            logger.error("talk stream open failed: \(status)")
            finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
        }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        scheduleParseWork { [weak self] in
            guard let self else { return }
            guard let audioFileStream else { return }
            let status = data.withUnsafeBytes { bytes in
                audio.fileStreamParseBytes(
                    audioFileStream,
                    UInt32(bytes.count),
                    bytes.baseAddress,
                    []
                )
            }
            if status != noErr {
                logger.error("talk stream parse failed: \(status)")
                fail(NSError(domain: "StreamingAudio", code: Int(status)))
            }
        }
    }

    func finishInput() {
        scheduleParseWork { [weak self] in
            guard let self else { return }
            inputFinished = true
            if audioQueue == nil {
                finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
                return
            }
            enqueueCurrentBuffer(flushOnly: true)
            _ = stop(immediate: false)
        }
    }

    func fail(_ error: Error) {
        logger.error("talk stream failed: \(error.localizedDescription, privacy: .public)")
        _ = stop(immediate: true)
        finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
    }

    func stop(immediate: Bool) -> Double? {
        guard let audioQueue else { return nil }
        let interruptedAt = currentTimeSeconds()
        _ = audio.queueStop(audioQueue, immediate)
        return interruptedAt
    }

    func finish(_ result: StreamingPlaybackResult) {
        let continuation: CheckedContinuation<StreamingPlaybackResult, Never>?
        lock.lock()
        if finished {
            continuation = nil
        } else {
            finished = true
            continuation = self.continuation
            self.continuation = nil
        }
        lock.unlock()

        continuation?.resume(returning: result)
        teardown()
    }

    private func teardown() {
        if let audioQueue {
            _ = audio.queueDispose(audioQueue, true)
            self.audioQueue = nil
        }
        if let audioFileStream {
            _ = audio.fileStreamClose(audioFileStream)
            self.audioFileStream = nil
        }
        bufferLock.lock()
        availableBuffers.removeAll()
        bufferLock.unlock()
        currentBuffer = nil
        currentPacketDescs.removeAll()
    }

    func setupQueueIfNeeded(_ asbd: AudioStreamBasicDescription) {
        guard audioQueue == nil else { return }

        var format = asbd
        audioFormat = format
        sampleRate = format.mSampleRate

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = audio.queueNewOutput(
            &format,
            outputCallbackProc,
            selfPtr,
            nil,
            nil,
            0,
            &audioQueue
        )
        if status != noErr {
            logger.error("talk queue create failed: \(status)")
            finish(StreamingPlaybackResult(finished: false, interruptedAt: nil))
            return
        }

        if let audioQueue {
            _ = audio.queueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, isRunningCallbackProc, selfPtr)
        }

        if let audioFileStream {
            var cookieSize: UInt32 = 0
            var writable: DarwinBoolean = false
            let cookieStatus = audio.fileStreamGetPropertyInfo(
                audioFileStream,
                kAudioFileStreamProperty_MagicCookieData,
                &cookieSize,
                &writable
            )
            if cookieStatus == noErr, cookieSize > 0, let audioQueue {
                var cookie = [UInt8](repeating: 0, count: Int(cookieSize))
                let readStatus = cookie.withUnsafeMutableBytes { bytes -> OSStatus in
                    guard let base = bytes.baseAddress else { return -1 }
                    return audio.fileStreamGetProperty(
                        audioFileStream,
                        kAudioFileStreamProperty_MagicCookieData,
                        &cookieSize,
                        base
                    )
                }
                if readStatus == noErr {
                    _ = audio.queueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookie, cookieSize)
                }
            }
        }

        if let audioQueue {
            for _ in 0..<Self.bufferCount {
                var buffer: AudioQueueBufferRef?
                let allocStatus = audio.queueAllocateBuffer(audioQueue, UInt32(Self.bufferSize), &buffer)
                if allocStatus == noErr, let buffer {
                    bufferLock.lock()
                    availableBuffers.append(buffer)
                    bufferLock.unlock()
                }
            }
        }
    }

    private func enqueueCurrentBuffer(flushOnly: Bool = false) {
        guard let audioQueue, let buffer = currentBuffer else { return }
        guard currentBufferSize > 0 else { return }

        buffer.pointee.mAudioDataByteSize = UInt32(currentBufferSize)
        let packetCount = UInt32(currentPacketDescs.count)

        let status = currentPacketDescs.withUnsafeBufferPointer { descPtr in
            audio.queueEnqueueBuffer(audioQueue, buffer, packetCount, descPtr.baseAddress)
        }
        if status != noErr {
            logger.error("talk queue enqueue failed: \(status)")
        } else {
            if !startRequested {
                startRequested = true
                let startStatus = audio.queueStart(audioQueue, nil)
                if startStatus != noErr {
                    logger.error("talk queue start failed: \(startStatus)")
                }
            }
        }

        currentBuffer = nil
        currentBufferSize = 0
        currentPacketDescs.removeAll(keepingCapacity: true)
        if !flushOnly {
            bufferLock.lock()
            var next = availableBuffers.popLast()
            bufferLock.unlock()
            if next == nil {
                bufferSemaphore.wait()
                bufferLock.lock()
                next = availableBuffers.popLast()
                bufferLock.unlock()
            }
            if let next { currentBuffer = next }
        }
    }

    func handlePackets(
        numberBytes: UInt32,
        numberPackets: UInt32,
        inputData: UnsafeRawPointer,
        packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        if audioQueue == nil, let format = audioFormat {
            setupQueueIfNeeded(format)
        }

        if audioQueue == nil {
            return
        }

        if currentBuffer == nil {
            bufferLock.lock()
            currentBuffer = availableBuffers.popLast()
            bufferLock.unlock()
            if currentBuffer == nil {
                bufferSemaphore.wait()
                bufferLock.lock()
                currentBuffer = availableBuffers.popLast()
                bufferLock.unlock()
            }
            currentBufferSize = 0
            currentPacketDescs.removeAll(keepingCapacity: true)
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

            if currentBufferSize + packetSize > Self.bufferSize {
                enqueueCurrentBuffer()
            }

            guard let buffer = currentBuffer else { continue }
            let dest = buffer.pointee.mAudioData.advanced(by: currentBufferSize)
            memcpy(dest, bytes.advanced(by: packetOffset), packetSize)

            let desc = AudioStreamPacketDescription(
                mStartOffset: Int64(currentBufferSize),
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(packetSize)
            )
            currentPacketDescs.append(desc)
            currentBufferSize += packetSize
        }
    }

    private func currentTimeSeconds() -> Double? {
        guard let audioQueue, sampleRate > 0 else { return nil }
        var timeStamp = AudioTimeStamp()
        let status = audio.queueGetCurrentTime(audioQueue, nil, &timeStamp, nil)
        if status != noErr { return nil }
        if timeStamp.mSampleTime.isNaN { return nil }
        return timeStamp.mSampleTime / sampleRate
    }
}

func propertyListenerProc(
    inClientData: UnsafeMutableRawPointer,
    inAudioFileStream: AudioFileStreamID,
    inPropertyID: AudioFileStreamPropertyID,
    ioFlags _: UnsafeMutablePointer<AudioFileStreamPropertyFlags>
) {
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
    inPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
) {
    let playback = Unmanaged<StreamingAudioPlayback>.fromOpaque(inClientData).takeUnretainedValue()
    playback.handlePackets(
        numberBytes: inNumberBytes,
        numberPackets: inNumberPackets,
        inputData: inInputData,
        packetDescriptions: inPacketDescriptions
    )
}

func outputCallbackProc(
    inUserData: UnsafeMutableRawPointer?,
    inAQ _: AudioQueueRef,
    inBuffer: AudioQueueBufferRef
) {
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
    inID: AudioQueuePropertyID
) {
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
