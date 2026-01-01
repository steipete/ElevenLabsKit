# Changelog

## Unreleased

- N/A.

## 0.1.0 — 2025-12-30

- ElevenLabs TTS client with retry/backoff, timeouts, and voice listing.
- Streaming and non-streaming synthesize APIs with output format handling (mp3/pcm).
- Streaming playback: MP3 (AudioQueue) + PCM (AVAudioEngine/AVAudioPlayerNode).
- Request helpers for model-specific validation (speed, stability, seed, latency, normalize, language).
- SwiftUI example app: API key/voice bootstrapping, voices list, streaming vs fetch, playback controls, timings, and advanced voice parameters.
- CLI example: sag-style interface with streaming/fetch playback, file output, and metrics.
