import Foundation

public enum AudioPayloadKind: String, Sendable {
    case wav
    case mp3
    case pcm
    case unknown

    public static func detect(from data: Data, requestedOutput: String) -> AudioPayloadKind {
        if data.count >= 12,
           data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]),
           data.dropFirst(8).prefix(4) == Data([0x57, 0x41, 0x56, 0x45])
        {
            return .wav
        }

        if data.count >= 3, data.prefix(3) == Data([0x49, 0x44, 0x33]) {
            return .mp3
        }

        if requestedOutput.lowercased().hasPrefix("pcm_") {
            return .pcm
        }

        if data.count >= 2 {
            let bytes = [UInt8](data.prefix(2))
            if bytes[0] == 0xFF, (bytes[1] & 0xE0) == 0xE0 {
                return .mp3
            }
        }

        return .unknown
    }
}
