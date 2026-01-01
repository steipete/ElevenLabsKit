import Foundation
import XCTest
@testable import ElevenLabsKit

final class ElevenLabsTTSRequestBuildingTests: XCTestCase {
    func testBuildSynthesizeRequestSetsAcceptHeaderFromOutputFormat() {
        let url = URL(string: "https://example.com")!
        let body = Data([0x01, 0x02, 0x03])

        let pcm = ElevenLabsTTSClient.buildSynthesizeRequest(
            url: url,
            apiKey: "k",
            body: body,
            timeoutSeconds: 1,
            outputFormat: "pcm_44100")
        XCTAssertEqual(pcm.value(forHTTPHeaderField: "Accept"), "audio/pcm")

        let mp3 = ElevenLabsTTSClient.buildSynthesizeRequest(
            url: url,
            apiKey: "k",
            body: body,
            timeoutSeconds: 1,
            outputFormat: "mp3_44100_128")
        XCTAssertEqual(mp3.value(forHTTPHeaderField: "Accept"), "audio/mpeg")

        let fallback = ElevenLabsTTSClient.buildSynthesizeRequest(
            url: url,
            apiKey: "k",
            body: body,
            timeoutSeconds: 1,
            outputFormat: nil)
        XCTAssertEqual(fallback.value(forHTTPHeaderField: "Accept"), "audio/mpeg")
    }
}

