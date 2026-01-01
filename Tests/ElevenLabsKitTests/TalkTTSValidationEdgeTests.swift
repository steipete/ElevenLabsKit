import XCTest
@testable import ElevenLabsKit

final class TalkTTSValidationEdgeTests: XCTestCase {
    func testResolveSpeedBoundsAreExclusive() {
        XCTAssertNil(TalkTTSValidation.resolveSpeed(speed: 0.5, rateWPM: nil))
        XCTAssertNil(TalkTTSValidation.resolveSpeed(speed: 2.0, rateWPM: nil))
        XCTAssertEqual(TalkTTSValidation.resolveSpeed(speed: 0.5001, rateWPM: nil) ?? 0, 0.5001, accuracy: 0.0001)
        XCTAssertEqual(TalkTTSValidation.resolveSpeed(speed: 1.999, rateWPM: nil) ?? 0, 1.999, accuracy: 0.0001)
    }

    func testResolveSpeedPrefersRateWPM() {
        XCTAssertEqual(TalkTTSValidation.resolveSpeed(speed: 1.5, rateWPM: 175) ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(TalkTTSValidation.resolveSpeed(speed: 1.5, rateWPM: 0) ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(TalkTTSValidation.resolveSpeed(speed: 1.5, rateWPM: -1) ?? 0, 1.5, accuracy: 0.0001)
    }

    func testValidatedStabilityNormalizesModelId() {
        XCTAssertEqual(TalkTTSValidation.validatedStability(0.5, modelId: " ELEVEN_V3 "), 0.5)
        XCTAssertNil(TalkTTSValidation.validatedStability(0.7, modelId: "ELEVEN_V3"))
        XCTAssertEqual(TalkTTSValidation.validatedStability(0.7, modelId: " eleven_multilingual_v2 "), 0.7)
    }
}
