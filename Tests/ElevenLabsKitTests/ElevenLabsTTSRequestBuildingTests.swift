@testable import ElevenLabsKit
import Foundation
import Testing

@Suite final class ElevenLabsTTSRequestBuildingTests {
    @Test func buildSynthesizeRequestSetsAcceptHeaderFromOutputFormat() {
        let url = URL(string: "https://example.com")!
        let body = Data([0x01, 0x02, 0x03])

        let pcm = ElevenLabsTTSClient.buildSynthesizeRequest(
            url: url,
            apiKey: "k",
            body: body,
            timeoutSeconds: 1,
            outputFormat: "pcm_44100"
        )
        #expect(pcm.value(forHTTPHeaderField: "Accept") == "audio/pcm")

        let mp3 = ElevenLabsTTSClient.buildSynthesizeRequest(
            url: url,
            apiKey: "k",
            body: body,
            timeoutSeconds: 1,
            outputFormat: "mp3_44100_128"
        )
        #expect(mp3.value(forHTTPHeaderField: "Accept") == "audio/mpeg")

        let fallback = ElevenLabsTTSClient.buildSynthesizeRequest(
            url: url,
            apiKey: "k",
            body: body,
            timeoutSeconds: 1,
            outputFormat: nil
        )
        #expect(fallback.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
    }
}
