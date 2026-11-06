@testable import ElevenLabsKit
import Foundation
import Testing

struct WAVPCMTests {
    @Test
    func `pcm bytes gain a riff header`() {
        let pcm = Data([0x00, 0x00, 0xFF, 0x7F])
        let file = WAVPCM.file(pcm: pcm, sampleRate: 44100)
        #expect(file.count == 48)
        #expect(file.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]))
        #expect(file.dropFirst(8).prefix(4) == Data([0x57, 0x41, 0x56, 0x45]))
        #expect(file.dropFirst(44) == pcm)
        #expect(WAVPCM.file(pcm: file, sampleRate: 44100) == file)
    }
}
