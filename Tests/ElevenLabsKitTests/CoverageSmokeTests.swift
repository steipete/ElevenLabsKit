import AVFoundation
@testable import ElevenLabsKit
import Testing

final class CoverageSmokeTests {
    @Test func `audio toolbox client live can be constructed`() {
        _ = AudioToolboxClient.live
        #expect(true)
    }

    @Test @MainActor func `av audio player node adapter basic calls dont crash`() throws {
        let engine = AVAudioEngine()
        let adapter = AVAudioPlayerNodeAdapter()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))

        adapter.attach(to: engine)
        adapter.connect(to: engine, format: format)
        adapter.stop()

        #expect(adapter.isPlaying == false)
        #expect(adapter.currentTimeSeconds() == nil)
    }

    @Test @MainActor func `streaming audio player stop without playback returns nil`() {
        #expect(StreamingAudioPlayer.shared.stop() == nil)
    }
}
