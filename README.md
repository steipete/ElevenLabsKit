# ElevenLabsKit

Swift helpers for ElevenLabs TTS on Apple platforms (iOS/macOS).

## What’s Included
- ElevenLabs TTS client + voice listing
- Streaming HTTP support
- MP3 streaming playback (AudioQueue)
- PCM streaming playback (AVAudioEngine + AVAudioPlayerNode)
- Validation helpers for model-specific settings

## Requirements
- Swift 6.2 (SwiftPM `swift-tools-version: 6.2`)
- iOS 17+
- macOS 15+

## Install (Swift Package Manager)
```
https://github.com/steipete/ElevenLabsKit.git
```

## Quick Start
```swift
import ElevenLabsKit

let client = ElevenLabsTTSClient(apiKey: "<api-key>")
let request = ElevenLabsTTSRequest(
    text: "Hello",
    modelId: "eleven_v3",
    outputFormat: "pcm_44100")

let stream = client.streamSynthesize(voiceId: "<voice-id>", request: request)
let sampleRate = TalkTTSValidation.pcmSampleRate(from: request.outputFormat) ?? 44_100
let result = await PCMStreamingAudioPlayer.shared.play(stream: stream, sampleRate: sampleRate)
```

## Non-Streaming (Fetch)
```swift
let data = try await client.synthesize(voiceId: "<voice-id>", request: request)
```

## Output Formats
- `pcm_44100`: lowest latency on Apple platforms.
- `mp3_44100_128`: MP3 streaming when needed.

## Playback Choices
- MP3: `StreamingAudioPlayer.shared.play(stream:)`
- PCM: `PCMStreamingAudioPlayer.shared.play(stream:sampleRate:)`

## Validation Notes
- `stability` for `eleven_v3` is restricted to `0.0`, `0.5`, or `1.0`.
- `latencyTier` is validated to `0..4`.

## Example App (SwiftUI)
- Run: `cd Examples/ElevenLabsKitExample && swift run`
- Or open `Examples/ElevenLabsKitExample/Package.swift` in Xcode and run `ElevenLabsKitExample`.
- Toggle `Streaming` vs `Fetch` to compare streaming vs non-streaming requests.

## Example CLI
- Run: `cd Examples/ElevenLabsKitCLI && swift run ElevenLabsKitCLI --help`
- Requires `ELEVENLABS_API_KEY` (or pass `--api-key`).

## Dev
- Tests: `swift test`
- Format: `swiftformat Sources Tests Examples`
- Lint: `swiftlint lint --strict --config .swiftlint.yml`

## License
MIT
