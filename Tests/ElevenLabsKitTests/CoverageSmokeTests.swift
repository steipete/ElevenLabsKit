import AVFoundation
@testable import ElevenLabsKit
import Testing

@Suite final class CoverageSmokeTests {
    @Test func audioToolboxClientLiveCanBeConstructed() {
        _ = AudioToolboxClient.live
        #expect(true)
    }

    @Test @MainActor func avAudioPlayerNodeAdapterBasicCallsDontCrash() {
        let engine = AVAudioEngine()
        let adapter = AVAudioPlayerNodeAdapter()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        adapter.attach(to: engine)
        adapter.connect(to: engine, format: format)
        adapter.stop()

        #expect(adapter.isPlaying == false)
        #expect(adapter.currentTimeSeconds() == nil)
    }

    @Test @MainActor func streamingAudioPlayerStopWithoutPlaybackReturnsNil() {
        #expect(StreamingAudioPlayer.shared.stop() == nil)
    }
}
