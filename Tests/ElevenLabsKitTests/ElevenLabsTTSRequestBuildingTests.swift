@testable import ElevenLabsKit
import Foundation
import Testing

final class ElevenLabsTTSRequestBuildingTests {
    @Test func `synthesis URL puts output format in query`() throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let url = ElevenLabsTTSClient.synthesisURL(
            baseUrl: baseURL,
            voiceId: "voice",
            outputFormat: "pcm_44100",
            streaming: false,
            latencyTier: nil
        )

        #expect(url.absoluteString == "https://example.com/v1/text-to-speech/voice?output_format=pcm_44100")
    }

    @Test func `build synthesize request sets accept header from output format`() throws {
        let url = try #require(URL(string: "https://example.com"))
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
