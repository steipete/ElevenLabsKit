import XCTest
@testable import ElevenLabsKit

final class ElevenLabsKitTests: XCTestCase {
    func testValidatedOutputFormat() {
        XCTAssertEqual(ElevenLabsTTSClient.validatedOutputFormat("mp3_44100_128"), "mp3_44100_128")
        XCTAssertEqual(ElevenLabsTTSClient.validatedOutputFormat("pcm_44100"), "pcm_44100")
        XCTAssertEqual(ElevenLabsTTSClient.validatedOutputFormat(" pcm_44100 \n"), "pcm_44100")
        XCTAssertNil(ElevenLabsTTSClient.validatedOutputFormat(nil))
        XCTAssertNil(ElevenLabsTTSClient.validatedOutputFormat(""))
        XCTAssertNil(ElevenLabsTTSClient.validatedOutputFormat(" wav_44100 "))
    }

    func testValidatedLanguage() {
        XCTAssertEqual(ElevenLabsTTSClient.validatedLanguage("en"), "en")
        XCTAssertEqual(ElevenLabsTTSClient.validatedLanguage(" EN "), "en")
        XCTAssertNil(ElevenLabsTTSClient.validatedLanguage("e"))
        XCTAssertNil(ElevenLabsTTSClient.validatedLanguage("eng"))
        XCTAssertNil(ElevenLabsTTSClient.validatedLanguage("e1"))
        XCTAssertNil(ElevenLabsTTSClient.validatedLanguage(""))
    }

    func testValidatedNormalize() {
        XCTAssertEqual(ElevenLabsTTSClient.validatedNormalize("auto"), "auto")
        XCTAssertEqual(ElevenLabsTTSClient.validatedNormalize(" ON "), "on")
        XCTAssertEqual(ElevenLabsTTSClient.validatedNormalize("off"), "off")
        XCTAssertNil(ElevenLabsTTSClient.validatedNormalize(nil))
        XCTAssertNil(ElevenLabsTTSClient.validatedNormalize(""))
        XCTAssertNil(ElevenLabsTTSClient.validatedNormalize("maybe"))
    }
}
