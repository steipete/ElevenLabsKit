# ElevenLabsKit

Swift helpers for ElevenLabs TTS on Apple platforms (iOS/macOS).

## Features
- ElevenLabs TTS client + voice listing
- Streaming HTTP support
- MP3 streaming playback (AudioQueue)
- PCM streaming playback (AVAudioEngine + AVAudioPlayerNode)
- Validation helpers for model-specific settings

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
- Use `pcm_44100` for lowest latency playback on Apple platforms.
- Use `mp3_44100_128` when you need MP3 streaming.

## Development
This package is designed to be used as a local path dependency during development.
Later you can switch to a git URL and use `swift package edit` to point back to your local checkout when iterating.

## License
MIT
