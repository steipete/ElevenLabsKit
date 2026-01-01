@testable import ElevenLabsKit
import Testing

@Suite final class TalkTTSValidationTests {
    @Test func resolveSpeedUsesRateWPMWhenProvided() {
        let resolved = TalkTTSValidation.resolveSpeed(speed: nil, rateWPM: 175)
        #expect(resolved != nil)
        #expect(abs((resolved ?? 0) - 1.0) < 0.0001)
        #expect(TalkTTSValidation.resolveSpeed(speed: nil, rateWPM: 400) == nil)
    }

    @Test func validatedUnitBounds() {
        #expect(TalkTTSValidation.validatedUnit(0) == 0)
        #expect(TalkTTSValidation.validatedUnit(1) == 1)
        #expect(TalkTTSValidation.validatedUnit(-0.01) == nil)
        #expect(TalkTTSValidation.validatedUnit(1.01) == nil)
    }

    @Test func validatedStability() {
        #expect(TalkTTSValidation.validatedStability(0, modelId: "eleven_v3") == 0)
        #expect(TalkTTSValidation.validatedStability(0.5, modelId: "eleven_v3") == 0.5)
        #expect(TalkTTSValidation.validatedStability(1, modelId: "eleven_v3") == 1)
        #expect(TalkTTSValidation.validatedStability(0.7, modelId: "eleven_v3") == nil)
        #expect(TalkTTSValidation.validatedStability(0.7, modelId: "eleven_multilingual_v2") == 0.7)
    }

    @Test func validatedSeedBounds() {
        #expect(TalkTTSValidation.validatedSeed(0) == 0)
        #expect(TalkTTSValidation.validatedSeed(1234) == 1234)
        #expect(TalkTTSValidation.validatedSeed(-1) == nil)
    }

    @Test func validatedLatencyTier() {
        #expect(TalkTTSValidation.validatedLatencyTier(0) == 0)
        #expect(TalkTTSValidation.validatedLatencyTier(4) == 4)
        #expect(TalkTTSValidation.validatedLatencyTier(-1) == nil)
        #expect(TalkTTSValidation.validatedLatencyTier(5) == nil)
    }

    @Test func pcmSampleRateParse() {
        #expect(TalkTTSValidation.pcmSampleRate(from: "pcm_44100") == 44100)
        #expect(TalkTTSValidation.pcmSampleRate(from: "mp3_44100_128") == nil)
        #expect(TalkTTSValidation.pcmSampleRate(from: "pcm_bad") == nil)
    }
}
