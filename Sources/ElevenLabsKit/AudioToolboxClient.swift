import AudioToolbox
import Foundation

struct AudioToolboxClient: Sendable {
    var fileStreamOpen: @Sendable (
        UnsafeMutableRawPointer?,
        AudioFileStream_PropertyListenerProc,
        AudioFileStream_PacketsProc,
        AudioFileTypeID,
        UnsafeMutablePointer<AudioFileStreamID?>
    ) -> OSStatus

    var fileStreamParseBytes: @Sendable (
        AudioFileStreamID,
        UInt32,
        UnsafeRawPointer?,
        AudioFileStreamParseFlags
    ) -> OSStatus

    var fileStreamGetPropertyInfo: @Sendable (
        AudioFileStreamID,
        AudioFileStreamPropertyID,
        UnsafeMutablePointer<UInt32>,
        UnsafeMutablePointer<DarwinBoolean>
    ) -> OSStatus

    var fileStreamGetProperty: @Sendable (
        AudioFileStreamID,
        AudioFileStreamPropertyID,
        UnsafeMutablePointer<UInt32>,
        UnsafeMutableRawPointer
    ) -> OSStatus

    var fileStreamClose: @Sendable (AudioFileStreamID) -> OSStatus

    var queueNewOutput: @Sendable (
        UnsafeMutablePointer<AudioStreamBasicDescription>,
        AudioQueueOutputCallback,
        UnsafeMutableRawPointer?,
        CFRunLoop?,
        CFString?,
        UInt32,
        UnsafeMutablePointer<AudioQueueRef?>
    ) -> OSStatus

    var queueAddPropertyListener: @Sendable (
        AudioQueueRef,
        AudioQueuePropertyID,
        AudioQueuePropertyListenerProc,
        UnsafeMutableRawPointer?
    ) -> OSStatus

    var queueAllocateBuffer: @Sendable (AudioQueueRef, UInt32, UnsafeMutablePointer<AudioQueueBufferRef?>) -> OSStatus
    var queueEnqueueBuffer: @Sendable (
        AudioQueueRef,
        AudioQueueBufferRef,
        UInt32,
        UnsafePointer<AudioStreamPacketDescription>?
    ) -> OSStatus
    var queueStart: @Sendable (AudioQueueRef, UnsafePointer<AudioTimeStamp>?) -> OSStatus
    var queueStop: @Sendable (AudioQueueRef, Bool) -> OSStatus
    var queueDispose: @Sendable (AudioQueueRef, Bool) -> OSStatus
    var queueSetProperty: @Sendable (AudioQueueRef, AudioQueuePropertyID, UnsafeRawPointer, UInt32) -> OSStatus
    var queueGetCurrentTime: @Sendable (
        AudioQueueRef,
        AudioQueueTimelineRef?,
        UnsafeMutablePointer<AudioTimeStamp>,
        UnsafeMutablePointer<DarwinBoolean>?
    ) -> OSStatus
    var queueGetProperty: @Sendable (
        AudioQueueRef,
        AudioQueuePropertyID,
        UnsafeMutableRawPointer,
        UnsafeMutablePointer<UInt32>
    ) -> OSStatus

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
