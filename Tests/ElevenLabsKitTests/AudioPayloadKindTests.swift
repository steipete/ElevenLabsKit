@testable import ElevenLabsKit
import Foundation
import Testing

struct AudioPayloadKindTests {
    @Test
    func `requested pcm wins over a frame sync`() {
        let sync = Data([0xFF, 0xFB, 0x10, 0x00])
        #expect(AudioPayloadKind.detect(from: sync, requestedOutput: "pcm_44100") == .pcm)
        #expect(AudioPayloadKind.detect(from: sync, requestedOutput: "mp3_44100_128") == .mp3)
        #expect(AudioPayloadKind.detect(from: Data([0x49, 0x44, 0x33]), requestedOutput: "pcm_44100") == .mp3)
    }
}
