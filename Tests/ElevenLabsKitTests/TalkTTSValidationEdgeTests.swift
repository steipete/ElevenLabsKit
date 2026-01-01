@testable import ElevenLabsKit
import Testing

@Suite final class TalkTTSValidationEdgeTests {
    @Test func resolveSpeedBoundsAreExclusive() {
        #expect(TalkTTSValidation.resolveSpeed(speed: 0.5, rateWPM: nil) == nil)
        #expect(TalkTTSValidation.resolveSpeed(speed: 2.0, rateWPM: nil) == nil)

        let low = TalkTTSValidation.resolveSpeed(speed: 0.5001, rateWPM: nil) ?? 0
        let high = TalkTTSValidation.resolveSpeed(speed: 1.999, rateWPM: nil) ?? 0
        #expect(abs(low - 0.5001) < 0.0001)
        #expect(abs(high - 1.999) < 0.0001)
    }

    @Test func resolveSpeedPrefersRateWPM() {
        let rate = TalkTTSValidation.resolveSpeed(speed: 1.5, rateWPM: 175) ?? 0
        #expect(abs(rate - 1.0) < 0.0001)

        let fallback0 = TalkTTSValidation.resolveSpeed(speed: 1.5, rateWPM: 0) ?? 0
        let fallbackNeg = TalkTTSValidation.resolveSpeed(speed: 1.5, rateWPM: -1) ?? 0
        #expect(abs(fallback0 - 1.5) < 0.0001)
        #expect(abs(fallbackNeg - 1.5) < 0.0001)
    }

    @Test func validatedStabilityNormalizesModelId() {
        #expect(TalkTTSValidation.validatedStability(0.5, modelId: " ELEVEN_V3 ") == 0.5)
        #expect(TalkTTSValidation.validatedStability(0.7, modelId: "ELEVEN_V3") == nil)
        #expect(TalkTTSValidation.validatedStability(0.7, modelId: " eleven_multilingual_v2 ") == 0.7)
    }
}
