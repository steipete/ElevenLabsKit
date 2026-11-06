import Foundation

public enum WAVPCM {
    public static func file(pcm: Data, sampleRate: Int, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        if pcm.count >= 12,
           pcm.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]),
           pcm.dropFirst(8).prefix(4) == Data([0x57, 0x41, 0x56, 0x45])
        {
            return pcm
        }
        return header(dataBytes: pcm.count, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample) + pcm
    }

    public static func header(dataBytes: Int, sampleRate: Int, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * blockAlign
        var bytes = Data()
        bytes.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        bytes.append(contentsOf: le32(UInt32(36 + dataBytes)))
        bytes.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        bytes.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        bytes.append(contentsOf: le32(16))
        bytes.append(contentsOf: le16(1))
        bytes.append(contentsOf: le16(UInt16(channels)))
        bytes.append(contentsOf: le32(UInt32(sampleRate)))
        bytes.append(contentsOf: le32(UInt32(byteRate)))
        bytes.append(contentsOf: le16(UInt16(blockAlign)))
        bytes.append(contentsOf: le16(UInt16(bitsPerSample)))
        bytes.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        bytes.append(contentsOf: le32(UInt32(dataBytes)))
        return bytes
    }

    private static func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }
}
