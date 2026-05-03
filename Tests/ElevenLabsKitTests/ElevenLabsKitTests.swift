@testable import ElevenLabsKit
import Testing

final class ElevenLabsKitTests {
    @Test func `validated output format`() {
        #expect(ElevenLabsTTSClient.validatedOutputFormat("mp3_44100_128") == "mp3_44100_128")
        #expect(ElevenLabsTTSClient.validatedOutputFormat("pcm_44100") == "pcm_44100")
        #expect(ElevenLabsTTSClient.validatedOutputFormat(" pcm_44100 \n") == "pcm_44100")
        #expect(ElevenLabsTTSClient.validatedOutputFormat(nil) == nil)
        #expect(ElevenLabsTTSClient.validatedOutputFormat("") == nil)
        #expect(ElevenLabsTTSClient.validatedOutputFormat(" wav_44100 ") == nil)
    }

    @Test func `validated language`() {
        #expect(ElevenLabsTTSClient.validatedLanguage("en") == "en")
        #expect(ElevenLabsTTSClient.validatedLanguage(" EN ") == "en")
        #expect(ElevenLabsTTSClient.validatedLanguage("e") == nil)
        #expect(ElevenLabsTTSClient.validatedLanguage("eng") == nil)
        #expect(ElevenLabsTTSClient.validatedLanguage("e1") == nil)
        #expect(ElevenLabsTTSClient.validatedLanguage("") == nil)
    }

    @Test func `validated normalize`() {
        #expect(ElevenLabsTTSClient.validatedNormalize("auto") == "auto")
        #expect(ElevenLabsTTSClient.validatedNormalize(" ON ") == "on")
        #expect(ElevenLabsTTSClient.validatedNormalize("off") == "off")
        #expect(ElevenLabsTTSClient.validatedNormalize(nil) == nil)
        #expect(ElevenLabsTTSClient.validatedNormalize("") == nil)
        #expect(ElevenLabsTTSClient.validatedNormalize("maybe") == nil)
    }
}
