@testable import ElevenLabsKit
import Testing

final class TalkTTSValidationEdgeTests {
    @Test func `resolve speed accepts provider bounds`() {
        #expect(TalkTTSValidation.resolveSpeed(speed: 0.7, rateWPM: nil) == 0.7)
        #expect(TalkTTSValidation.resolveSpeed(speed: 1.2, rateWPM: nil) == 1.2)
        #expect(TalkTTSValidation.resolveSpeed(speed: 0.69, rateWPM: nil) == nil)
        #expect(TalkTTSValidation.resolveSpeed(speed: 1.21, rateWPM: nil) == nil)

        let low = TalkTTSValidation.resolveSpeed(speed: 0.7001, rateWPM: nil) ?? 0
        let high = TalkTTSValidation.resolveSpeed(speed: 1.199, rateWPM: nil) ?? 0
        #expect(abs(low - 0.7001) < 0.0001)
        #expect(abs(high - 1.199) < 0.0001)
    }

    @Test func `resolve speed prefers rate WPM`() {
        let rate = TalkTTSValidation.resolveSpeed(speed: 1.1, rateWPM: 175) ?? 0
        #expect(abs(rate - 1.0) < 0.0001)

        let fallback0 = TalkTTSValidation.resolveSpeed(speed: 1.1, rateWPM: 0) ?? 0
        let fallbackNeg = TalkTTSValidation.resolveSpeed(speed: 1.1, rateWPM: -1) ?? 0
        #expect(abs(fallback0 - 1.1) < 0.0001)
        #expect(abs(fallbackNeg - 1.1) < 0.0001)
    }

    @Test func `validated stability normalizes model id`() {
        #expect(TalkTTSValidation.validatedStability(0.5, modelId: " ELEVEN_V3 ") == 0.5)
        #expect(TalkTTSValidation.validatedStability(0.7, modelId: "ELEVEN_V3") == nil)
        #expect(TalkTTSValidation.validatedStability(0.7, modelId: " eleven_multilingual_v2 ") == 0.7)
    }
}
