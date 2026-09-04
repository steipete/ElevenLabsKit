# Changelog

## Unreleased

- Reject invalid CLI voice limits and streaming latency tiers before requests, preventing negative voice limits from crashing after a successful voice listing.

## 0.1.2 — 2026-08-02

- Fix non-streaming output-format selection, provider speed validation, retry cancellation, and replacement of active playback sessions.
- Refresh the package, examples, formatting, and CI baseline for Swift 6.3.

## 0.1.1 — 2026-04-28

- Refresh package metadata for the patch release after dependency verification.

## 0.1.0 — 2026-01-19

- ElevenLabs TTS client with retry/backoff, timeouts, and voice listing.
- Async/await streaming + fetch synthesize APIs with output-format handling (mp3/pcm).
- Streaming playback engines: MP3 (AudioQueue) + PCM (AVAudioEngine/AVAudioPlayerNode).
- AudioToolbox client wrapper for testable MP3 playback and queue lifecycle.
- Request helpers for model-specific validation (speed, stability, seed, latency, normalize, language).
- SwiftUI example app: API key/voice bootstrapping, voices list, streaming vs fetch, playback controls, timings, advanced voice parameters.
- CLI example: sag-style interface with streaming/fetch playback, file output, and metrics.
- Streaming playback teardown guard + regression coverage for buffer waiters.
