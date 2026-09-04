# ElevenLabsKit 📣 — Give your Swift app a voice.

[![CI](https://img.shields.io/github/actions/workflow/status/steipete/ElevenLabsKit/ci.yml?branch=main&style=flat-square&label=ci)](https://github.com/steipete/ElevenLabsKit/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/v/release/steipete/ElevenLabsKit?style=flat-square)](https://github.com/steipete/ElevenLabsKit/releases/latest)
[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-f05138?style=flat-square)](https://www.swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2017%2B%20%7C%20macOS%2015%2B-blue?style=flat-square)](Package.swift)
[![License](https://img.shields.io/github/license/steipete/ElevenLabsKit?style=flat-square)](LICENSE)

ElevenLabsKit is a Swift package for text-to-speech requests and streaming audio playback with ElevenLabs. It supports iOS and macOS apps that need async voice listing, synthesis, or low-level MP3 and PCM playback.

## Install

Add `https://github.com/steipete/ElevenLabsKit.git` in Xcode under **File → Add Package Dependencies**, or add the package and product to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/steipete/ElevenLabsKit.git", from: "0.1.1"),
],
targets: [
    .target(name: "YourApp", dependencies: ["ElevenLabsKit"]),
]
```

The current source tree requires Swift 6.3, iOS 17 or later, or macOS 15 or later.

## Quick start

Create a client, stream PCM audio, and play chunks as they arrive:

```swift
import ElevenLabsKit

let client = ElevenLabsTTSClient(apiKey: "<api-key>")
let request = ElevenLabsTTSRequest(
    text: "Hello from ElevenLabsKit",
    modelId: "eleven_v3",
    outputFormat: "pcm_44100")
let stream = client.streamSynthesize(voiceId: "<voice-id>", request: request)
let result = await PCMStreamingAudioPlayer.shared.play(stream: stream, sampleRate: 44_100)
```

The request needs an ElevenLabs API key and a voice ID from your account. `result.finished` reports whether playback completed; starting another playback session interrupts the active one.

## Synthesis

Use `synthesize` when you need the complete audio payload instead of a stream:

```swift
let data = try await client.synthesize(voiceId: "<voice-id>", request: request)
```

List the voices available to the account with `try await client.listVoices()`. `synthesize` retries rate-limit, server, and retryable transport failures up to three attempts; `synthesizeWithHardTimeout` adds an overall cancellation deadline.

## Playback

The package provides two shared players:

| Format | Player | Backend |
| --- | --- | --- |
| MP3 | `StreamingAudioPlayer.shared` | Audio Queue Services |
| PCM | `PCMStreamingAudioPlayer.shared` | `AVAudioEngine` and `AVAudioPlayerNode` |

Choose an output format that matches the player. For PCM formats, `TalkTTSValidation.pcmSampleRate(from:)` extracts the rate from values such as `pcm_44100`:

```swift
let sampleRate = TalkTTSValidation.pcmSampleRate(from: request.outputFormat) ?? 44_100
let result = await PCMStreamingAudioPlayer.shared.play(stream: stream, sampleRate: sampleRate)
```

Call `stop()` on either player to interrupt playback and receive its last timestamp when available.

## Request validation

`ElevenLabsTTSRequest` supports model, output format, speed, stability, similarity, style, speaker boost, seed, normalization, language, and streaming latency settings. `TalkTTSValidation` and the static helpers on `ElevenLabsTTSClient` validate common inputs before a request is sent:

- Speed accepts `0.7...1.2`, including conversion from words per minute.
- Stability accepts `0...1`; `eleven_v3` accepts `0`, `0.5`, or `1`.
- Similarity and style accept `0...1`.
- Streaming latency tier accepts `0...4`.
- Language accepts two-letter codes, and normalization accepts `auto`, `on`, or `off`.

## Examples

[`ElevenLabsKitExample`](Examples/ElevenLabsKitExample/Package.swift) is a macOS SwiftUI app for comparing streaming and fetched playback, selecting voices, and adjusting request parameters. Open its `Package.swift` in Xcode and run the `ElevenLabsKitExample` scheme.

[`ElevenLabsKitCLI`](Examples/ElevenLabsKitCLI/Package.swift) exercises the same APIs from a terminal:

```sh
cd Examples/ElevenLabsKitCLI
swift run ElevenLabsKitCLI --help
```

Speech and voice-list commands require `ELEVENLABS_API_KEY` or `--api-key`.
`--limit` accepts non-negative integers (zero lists no voices), and `--latency-tier` accepts integers from `0` through `4`. Invalid numeric options fail before any API request.

## Development

```sh
swift test
swiftformat Sources Tests Examples --lint
swiftlint lint --strict --config .swiftlint.yml
(cd Examples/ElevenLabsKitExample && swift build)
(cd Examples/ElevenLabsKitCLI && swift build)
./scripts/check-cli.sh
```

## License

ElevenLabsKit is available under the [MIT License](LICENSE).
