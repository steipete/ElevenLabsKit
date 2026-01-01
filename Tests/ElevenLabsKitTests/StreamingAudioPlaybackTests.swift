import AudioToolbox
import Foundation
import OSLog
import Testing
@testable import ElevenLabsKit

@Suite(.serialized) final class StreamingAudioPlaybackTests {
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private final class BufferStore: @unchecked Sendable {
        var buffers: [AudioQueueBufferRef] = []
        var audioData: [UnsafeMutableRawPointer] = []

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
            buffers.append(buffer)
            audioData.append(data)
            return buffer
        }
    }

    @Test func startOpenFailureClosesStream() {
        let closeCalled = Flag()

        let audio = AudioToolboxClient(
            fileStreamOpen: { _, _, _, _, outStream in
                outStream.pointee = OpaquePointer(bitPattern: 0x1)
                return -1
            },
            fileStreamParseBytes: { _, _, _, _ in noErr },
            fileStreamGetPropertyInfo: { _, _, _, _ in noErr },
            fileStreamGetProperty: { _, _, _, _ in noErr },
            fileStreamClose: { _ in closeCalled.set(); return noErr },
            queueNewOutput: { _, _, _, _, _, _, _ in noErr },
            queueAddPropertyListener: { _, _, _, _ in noErr },
            queueAllocateBuffer: { _, _, _ in noErr },
            queueEnqueueBuffer: { _, _, _, _ in noErr },
            queueStart: { _, _ in noErr },
            queueStop: { _, _ in noErr },
            queueDispose: { _, _ in noErr },
            queueSetProperty: { _, _, _, _ in noErr },
            queueGetCurrentTime: { _, _, _, _ in noErr },
            queueGetProperty: { _, _, _, _ in noErr }
        )

        let playback = StreamingAudioPlayback(
            logger: Logger(subsystem: "test", category: "stream"),
            audio: audio,
            scheduleParseWork: { $0() }
        )
        playback.start()
        #expect(closeCalled.get())
    }

    @Test func appendParseErrorStopsAndTeardowns() {
        let stopCalled = Flag()
        let disposeCalled = Flag()
        let closeCalled = Flag()

        let buffers = BufferStore()

        let audio = AudioToolboxClient(
            fileStreamOpen: { _, _, _, _, outStream in
                outStream.pointee = OpaquePointer(bitPattern: 0x1)
                return noErr
            },
            fileStreamParseBytes: { _, _, _, _ in -50 },
            fileStreamGetPropertyInfo: { _, _, outSize, outWritable in
                outSize.pointee = 0
                outWritable.pointee = false
                return noErr
            },
            fileStreamGetProperty: { _, _, _, _ in noErr },
            fileStreamClose: { _ in closeCalled.set(); return noErr },
            queueNewOutput: { _, _, _, _, _, _, outQueue in
                outQueue.pointee = OpaquePointer(bitPattern: 0x2)
                return noErr
            },
            queueAddPropertyListener: { _, _, _, _ in noErr },
            queueAllocateBuffer: { _, size, outBuffer in
                outBuffer.pointee = buffers.makeBuffer(byteCapacity: size)
                return noErr
            },
            queueEnqueueBuffer: { _, _, _, _ in noErr },
            queueStart: { _, _ in noErr },
            queueStop: { _, _ in stopCalled.set(); return noErr },
            queueDispose: { _, _ in disposeCalled.set(); return noErr },
            queueSetProperty: { _, _, _, _ in noErr },
            queueGetCurrentTime: { _, _, _, _ in noErr },
            queueGetProperty: { _, _, _, _ in noErr }
        )

        let playback = StreamingAudioPlayback(
            logger: Logger(subsystem: "test", category: "stream"),
            audio: audio,
            scheduleParseWork: { $0() }
        )
        playback.start()

        var format = AudioStreamBasicDescription()
        format.mSampleRate = 44_100
        playback.setupQueueIfNeeded(format)

        playback.append(Data([0x00, 0x01, 0x02]))
        #expect(stopCalled.get())
        #expect(disposeCalled.get())
        #expect(closeCalled.get())
    }

    @Test func handlePacketsThenFinishInputEnqueuesAndStarts() {
        let enqueueCalled = Flag()
        let startCalled = Flag()
        let stopCalled = Flag()

        let buffers = BufferStore()

        let audio = AudioToolboxClient(
            fileStreamOpen: { _, _, _, _, outStream in
                outStream.pointee = OpaquePointer(bitPattern: 0x1)
                return noErr
            },
            fileStreamParseBytes: { _, _, _, _ in noErr },
            fileStreamGetPropertyInfo: { _, _, outSize, outWritable in
                outSize.pointee = 0
                outWritable.pointee = false
                return noErr
            },
            fileStreamGetProperty: { _, _, _, _ in noErr },
            fileStreamClose: { _ in noErr },
            queueNewOutput: { _, _, _, _, _, _, outQueue in
                outQueue.pointee = OpaquePointer(bitPattern: 0x2)
                return noErr
            },
            queueAddPropertyListener: { _, _, _, _ in noErr },
            queueAllocateBuffer: { _, size, outBuffer in
                outBuffer.pointee = buffers.makeBuffer(byteCapacity: size)
                return noErr
            },
            queueEnqueueBuffer: { _, _, _, _ in enqueueCalled.set(); return noErr },
            queueStart: { _, _ in startCalled.set(); return noErr },
            queueStop: { _, _ in stopCalled.set(); return noErr },
            queueDispose: { _, _ in noErr },
            queueSetProperty: { _, _, _, _ in noErr },
            queueGetCurrentTime: { _, _, _, _ in noErr },
            queueGetProperty: { _, _, _, _ in noErr }
        )

        let playback = StreamingAudioPlayback(
            logger: Logger(subsystem: "test", category: "stream"),
            audio: audio,
            scheduleParseWork: { $0() }
        )
        playback.start()

        var format = AudioStreamBasicDescription()
        format.mSampleRate = 44_100
        playback.setupQueueIfNeeded(format)

        let bytes = [UInt8](repeating: 0x11, count: 10)
        bytes.withUnsafeBytes { raw in
            playback.handlePackets(
                numberBytes: UInt32(raw.count),
                numberPackets: 2,
                inputData: raw.baseAddress!,
                packetDescriptions: nil)
        }

        playback.finishInput()
        #expect(enqueueCalled.get())
        #expect(startCalled.get())
        #expect(stopCalled.get())
    }

    @Test func stopReturnsNilWhenSampleTimeIsNaN() {
        let stopCalled = Flag()

        let audio = AudioToolboxClient(
            fileStreamOpen: { _, _, _, _, outStream in
                outStream.pointee = OpaquePointer(bitPattern: 0x1)
                return noErr
            },
            fileStreamParseBytes: { _, _, _, _ in noErr },
            fileStreamGetPropertyInfo: { _, _, _, _ in noErr },
            fileStreamGetProperty: { _, _, _, _ in noErr },
            fileStreamClose: { _ in noErr },
            queueNewOutput: { _, _, _, _, _, _, outQueue in
                outQueue.pointee = OpaquePointer(bitPattern: 0x2)
                return noErr
            },
            queueAddPropertyListener: { _, _, _, _ in noErr },
            queueAllocateBuffer: { _, _, _ in noErr },
            queueEnqueueBuffer: { _, _, _, _ in noErr },
            queueStart: { _, _ in noErr },
            queueStop: { _, _ in stopCalled.set(); return noErr },
            queueDispose: { _, _ in noErr },
            queueSetProperty: { _, _, _, _ in noErr },
            queueGetCurrentTime: { _, _, outTimeStamp, _ in
                outTimeStamp.pointee.mSampleTime = .nan
                return noErr
            },
            queueGetProperty: { _, _, _, _ in noErr }
        )

        let playback = StreamingAudioPlayback(
            logger: Logger(subsystem: "test", category: "stream"),
            audio: audio,
            scheduleParseWork: { $0() }
        )

        var format = AudioStreamBasicDescription()
        format.mSampleRate = 44_100
        playback.setupQueueIfNeeded(format)

        let interruptedAt = playback.stop(immediate: true)
        #expect(interruptedAt == nil)
        #expect(stopCalled.get())
    }
}
