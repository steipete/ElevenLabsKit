# ElevenLabsKit

Swift helpers for ElevenLabs TTS on Apple platforms (iOS/macOS).

## What’s Included
- ElevenLabs TTS client + voice listing
- Streaming HTTP support
- MP3 streaming playback (AudioQueue)
- PCM streaming playback (AVAudioEngine + AVAudioPlayerNode)
- Validation helpers for model-specific settings

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
let result = await PCMStreamingAudioPlayer.shared.play(stream: stream, sampleRate: 44_100)
```

## Output Formats
- `pcm_44100`: lowest latency on Apple platforms.
- `mp3_44100_128`: MP3 streaming when needed.

## Validation Notes
- `stability` for `eleven_v3` is restricted to `0.0`, `0.5`, or `1.0`.
- `latency_tier` is validated to `0..4`.

## License
MIT
