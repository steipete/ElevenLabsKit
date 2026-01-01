import AVFoundation
import ElevenLabsKit
import Foundation

@main
struct ElevenLabsKitCLI {
    static func main() async {
        do {
            let parsed = try CLIArguments.parse()
            if parsed.showHelp {
                CLIArguments.printUsage()
                return
            }
            try await run(parsed)
        } catch {
            CLIArguments.printUsage()
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run(_ args: CLIArguments) async throws {
        let apiKey = args.apiKey ?? CLISecrets.apiKeyFromEnvironment()
        guard let apiKey, apiKey.isEmpty == false else {
            throw CLIError("Missing API key. Set ELEVENLABS_API_KEY or pass --api-key.")
        }

        let client = ElevenLabsTTSClient(apiKey: apiKey)
        switch args.command {
        case .voices:
            let voices = try await client.listVoices()
            let filtered = args.search.map { query in
                voices.filter {
                    ($0.name ?? "").localizedCaseInsensitiveContains(query) || $0.voiceId.localizedCaseInsensitiveContains(query)
                }
            } ?? voices
            let limited = args.limit.map { Array(filtered.prefix($0)) } ?? filtered
            for voice in limited {
                let label = voice.name ?? "Unnamed"
                print("\(label)\t\(voice.voiceId)")
            }
        case .speak:
            let text = try resolveText(from: args)
            let voiceId = try await resolveVoiceId(args: args, client: client)
            let outputFormat = resolveOutputFormat(from: args)
            let request = ElevenLabsTTSRequest(
                text: text,
                modelId: args.modelId,
                outputFormat: outputFormat,
                latencyTier: args.latencyTier
            )

            if args.stream {
                try await streamAndMaybePlay(
                    client: client,
                    request: request,
                    options: PlaybackOptions(
                        voiceId: voiceId,
                        play: args.play,
                        outputPath: args.outputPath,
                        metrics: args.metrics
                    )
                )
            } else {
                try await fetchAndMaybePlay(
                    client: client,
                    request: request,
                    options: PlaybackOptions(
                        voiceId: voiceId,
                        play: args.play,
                        outputPath: args.outputPath,
                        metrics: args.metrics
                    )
                )
            }
        }
    }
}

private enum CLICommand {
    case speak
    case voices
}

private struct CLIArguments {
    var command: CLICommand
    var showHelp: Bool
    var apiKey: String?
    var voiceId: String?
    var modelId: String?
    var outputFormat: String?
    var latencyTier: Int?
    var stream: Bool
    var play: Bool
    var metrics: Bool
    var outputPath: String?
    var search: String?
    var limit: Int?
    var textParts: [String]

    static func parse() throws -> CLIArguments {
        var args = Array(CommandLine.arguments.dropFirst())
        var command: CLICommand = .speak
        var showHelp = false

        if let first = args.first, first == "voices" || first == "speak" {
            command = first == "voices" ? .voices : .speak
            args.removeFirst()
        }

        var parsed = CLIArguments(
            command: command,
            showHelp: false,
            apiKey: nil,
            voiceId: nil,
            modelId: nil,
            outputFormat: nil,
            latencyTier: nil,
            stream: true,
            play: true,
            metrics: false,
            outputPath: nil,
            search: nil,
            limit: nil,
            textParts: []
        )

        while args.isEmpty == false {
            let arg = args.removeFirst()
            switch arg {
            case "-h", "--help":
                showHelp = true
                parsed.showHelp = true
            case "--api-key":
                parsed.apiKey = try requireValue(&args, flag: arg)
            case "-v", "--voice":
                parsed.voiceId = try requireValue(&args, flag: arg)
            case "--model-id":
                parsed.modelId = try requireValue(&args, flag: arg)
            case "--format":
                parsed.outputFormat = try requireValue(&args, flag: arg)
            case "--latency-tier":
                parsed.latencyTier = try Int(requireValue(&args, flag: arg))
            case "--stream":
                parsed.stream = true
            case "--no-stream":
                parsed.stream = false
            case "--play":
                parsed.play = true
            case "--no-play":
                parsed.play = false
            case "--metrics":
                parsed.metrics = true
            case "-o", "--output":
                parsed.outputPath = try requireValue(&args, flag: arg)
            case "--search":
                parsed.search = try requireValue(&args, flag: arg)
            case "--limit":
                parsed.limit = try Int(requireValue(&args, flag: arg))
            default:
                parsed.textParts.append(arg)
            }
        }

        if parsed.voiceId == "?" {
            parsed.command = .voices
        }

        if showHelp {
            parsed.showHelp = true
        }

        return parsed
    }

    static func printUsage() {
        let text = """
        ElevenLabsKitCLI

        Usage:
          ElevenLabsKitCLI [speak] [options] <text>
          ElevenLabsKitCLI voices [options]

        Options:
          --api-key <key>        API key (default: ELEVENLABS_API_KEY env)
          -v, --voice <id>       Voice ID (or ? to list voices)
          --model-id <id>        Model ID (default: eleven_v3)
          --format <format>      Output format (pcm_44100, mp3_44100_128, ...)
          --latency-tier <n>     Optimize streaming latency (0-4)
          --stream / --no-stream Stream audio (default: --stream)
          --play / --no-play     Play audio (default: --play)
          --metrics              Print timing + byte metrics to stderr
          -o, --output <path>    Write audio to file

        Voices:
          --search <text>        Filter voices by name/id
          --limit <n>            Limit number of voices

        Examples:
          ELEVENLABS_API_KEY=... ElevenLabsKitCLI "Hello"
          ElevenLabsKitCLI speak -v <voice-id> --format mp3_44100_128 "Hello"
          ElevenLabsKitCLI voices --search english --limit 10
        """
        print(text)
    }
}

private enum CLISecrets {
    static func apiKeyFromEnvironment() -> String? {
        env("ELEVENLABS_API_KEY")
            ?? env("XI_API_KEY")
            ?? env("ELEVEN_API_KEY")
    }

    static func voiceIdFromEnvironment() -> String? {
        env("ELEVENLABS_VOICE_ID")
            ?? env("SAG_VOICE_ID")
            ?? env("XI_VOICE_ID")
    }

    private static func env(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name]
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private func resolveText(from args: CLIArguments) throws -> String {
    if args.textParts.isEmpty == false {
        return args.textParts.joined(separator: " ")
    }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.isEmpty == false, let text = String(data: data, encoding: .utf8) else {
        throw CLIError("Missing input text.")
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { throw CLIError("Missing input text.") }
    return trimmed
}

private func resolveVoiceId(args: CLIArguments, client: ElevenLabsTTSClient) async throws -> String {
    if let voiceId = args.voiceId, voiceId.isEmpty == false {
        return voiceId
    }
    if let envVoice = CLISecrets.voiceIdFromEnvironment() {
        return envVoice
    }
    let voices = try await client.listVoices()
    guard let first = voices.first else { throw CLIError("No voices available.") }
    return first.voiceId
}

private func resolveOutputFormat(from args: CLIArguments) -> String? {
    if let outputFormat = args.outputFormat { return outputFormat }
    guard let outputPath = args.outputPath else { return nil }
    let lower = outputPath.lowercased()
    if lower.hasSuffix(".wav") { return "pcm_44100" }
    if lower.hasSuffix(".mp3") { return "mp3_44100_128" }
    return nil
}

private func seconds(from clock: ContinuousClock, since start: ContinuousClock.Instant) -> Double {
    let duration = clock.now - start
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}

private func formatSeconds(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.2fs", value)
}

private func writeFile(data: Data, path: String) throws {
    let url = URL(fileURLWithPath: path)
    try data.write(to: url, options: [.atomic])
}

private struct PlaybackOptions {
    let voiceId: String
    let play: Bool
    let outputPath: String?
    let metrics: Bool
}

private func fetchAndMaybePlay(
    client: ElevenLabsTTSClient,
    request: ElevenLabsTTSRequest,
    options: PlaybackOptions
) async throws {
    let clock = ContinuousClock()
    let start = clock.now

    let data = try await client.synthesize(voiceId: options.voiceId, request: request)
    let requestSeconds = seconds(from: clock, since: start)
    if let outputPath = options.outputPath {
        try writeFile(data: data, path: outputPath)
    }
    guard options.play else { return }

    let normalizedOutput = ElevenLabsTTSClient.validatedOutputFormat(request.outputFormat)
        ?? request.outputFormat?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""
    let detected = AudioKind.detect(from: data, requestedOutput: normalizedOutput)

    switch detected {
    case .pcm:
        guard let sampleRate = TalkTTSValidation.pcmSampleRate(from: normalizedOutput) else {
            throw CLIError("Invalid PCM output format.")
        }
        let stream = AsyncThrowingStream<Data, Error> { cont in
            cont.yield(data)
            cont.finish()
        }
        _ = await PCMStreamingAudioPlayer.shared.play(stream: stream, sampleRate: sampleRate)
    case .wav, .mp3:
        try await playWithAVAudioPlayer(data)
    case .unknown:
        let stream = AsyncThrowingStream<Data, Error> { cont in
            cont.yield(data)
            cont.finish()
        }
        _ = await StreamingAudioPlayer.shared.play(stream: stream)
    }

    if options.metrics {
        let bytes = data.count
        let message = String(format: "fetch_request_seconds=%.2f bytes=%d", requestSeconds, bytes)
        fputs("\(message)\n", stderr)
    }
}

private func streamAndMaybePlay(
    client: ElevenLabsTTSClient,
    request: ElevenLabsTTSRequest,
    options: PlaybackOptions
) async throws {
    let clock = ContinuousClock()
    let start = clock.now
    let streamMetrics = options.metrics ? StreamMetrics() : nil

    let stream = client.streamSynthesize(voiceId: options.voiceId, request: request)
    let outputSink = try options.outputPath.map { try FileSink(path: $0) }

    if options.play == false {
        try await drain(stream: stream, sink: outputSink, metrics: streamMetrics, start: start, clock: clock)
        if let streamMetrics {
            let snapshot = await streamMetrics.snapshot()
            printStreamMetrics(snapshot)
        }
        return
    }

    var iterator = stream.makeAsyncIterator()
    guard let firstChunk = try await iterator.next() else {
        throw CLIError("No audio returned.")
    }
    if let streamMetrics {
        await streamMetrics.setTTFB(seconds(from: clock, since: start))
    }

    let normalizedOutput = ElevenLabsTTSClient.validatedOutputFormat(request.outputFormat)
        ?? request.outputFormat?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""
    let detected = AudioKind.detect(from: firstChunk, requestedOutput: normalizedOutput)

    let onChunk: (@Sendable (Int) async -> Void)?
    let onStreamFinished: (@Sendable () async -> Void)?
    if let streamMetrics {
        onChunk = { bytes in await streamMetrics.addBytes(bytes) }
        onStreamFinished = { await streamMetrics.setDownload(seconds(from: clock, since: start)) }
    } else {
        onChunk = nil
        onStreamFinished = nil
    }

    let replayStream = makeReplayStream(
        iterator: iterator,
        firstChunk: firstChunk,
        stripWavHeader: detected == .wav,
        sink: outputSink,
        onChunk: onChunk,
        onStreamFinished: onStreamFinished
    )

    switch detected {
    case .pcm, .wav:
        guard let sampleRate = TalkTTSValidation.pcmSampleRate(from: normalizedOutput) else {
            throw CLIError("Invalid PCM output format.")
        }
        _ = await PCMStreamingAudioPlayer.shared.play(stream: replayStream, sampleRate: sampleRate)
    case .mp3, .unknown:
        _ = await StreamingAudioPlayer.shared.play(stream: replayStream)
    }

    if let streamMetrics {
        await streamMetrics.setPlayback(seconds(from: clock, since: start))
        let snapshot = await streamMetrics.snapshot()
        printStreamMetrics(snapshot)
    }
}

private func drain(
    stream: AsyncThrowingStream<Data, Error>,
    sink: FileSink?,
    metrics: StreamMetrics?,
    start: ContinuousClock.Instant,
    clock: ContinuousClock
) async throws {
    var didSetTTFB = false
    for try await chunk in stream {
        if let sink { await sink.write(chunk) }
        if let metrics { await metrics.addBytes(chunk.count) }
        if didSetTTFB == false, let metrics {
            didSetTTFB = true
            await metrics.setTTFB(seconds(from: clock, since: start))
        }
    }
    if let sink { await sink.close() }
    if let metrics {
        await metrics.setDownload(seconds(from: clock, since: start))
    }
}

private func playWithAVAudioPlayer(_ data: Data) async throws {
    let player = try AVAudioPlayer(data: data)
    player.play()
    while player.isPlaying {
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}

private enum AudioKind: String {
    case wav
    case mp3
    case pcm
    case unknown

    static func detect(from data: Data, requestedOutput: String) -> AudioKind {
        if data.count >= 12,
           data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46]),
           data.dropFirst(8).prefix(4) == Data([0x57, 0x41, 0x56, 0x45])
        {
            return .wav
        }

        if data.count >= 3, data.prefix(3) == Data([0x49, 0x44, 0x33]) {
            return .mp3
        }

        if data.count >= 2 {
            let bytes = [UInt8](data.prefix(2))
            if bytes[0] == 0xFF, (bytes[1] & 0xE0) == 0xE0 {
                return .mp3
            }
        }

        if requestedOutput.lowercased().hasPrefix("pcm_") {
            return .pcm
        }

        return .unknown
    }
}

private func makeReplayStream(
    iterator: AsyncThrowingStream<Data, Error>.Iterator,
    firstChunk: Data,
    stripWavHeader: Bool,
    sink: FileSink?,
    onChunk: (@Sendable (Int) async -> Void)? = nil,
    onStreamFinished: (@Sendable () async -> Void)? = nil
) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        let sendableIterator = UnsafeSendableIterator(iterator: iterator)
        Task {
            var iterator = sendableIterator.iterator
            var headerBuffer = Data()
            var headerStripped = stripWavHeader == false

            func drainHeaderIfPossible() {
                guard headerStripped == false else { return }
                guard headerBuffer.count >= 44 else { return }
                let remainder = headerBuffer.dropFirst(44)
                if remainder.isEmpty == false {
                    continuation.yield(Data(remainder))
                }
                headerBuffer.removeAll(keepingCapacity: true)
                headerStripped = true
            }

            do {
                if let sink { await sink.write(firstChunk) }
                if let onChunk { await onChunk(firstChunk.count) }

                if stripWavHeader {
                    headerBuffer.append(firstChunk)
                    drainHeaderIfPossible()
                } else {
                    continuation.yield(firstChunk)
                }

                while let chunk = try await iterator.next() {
                    if let sink { await sink.write(chunk) }
                    if let onChunk { await onChunk(chunk.count) }

                    if stripWavHeader, headerStripped == false {
                        headerBuffer.append(chunk)
                        drainHeaderIfPossible()
                        continue
                    }
                    continuation.yield(chunk)
                }

                if headerStripped == false, headerBuffer.isEmpty == false {
                    continuation.yield(headerBuffer)
                }
                if let onStreamFinished { await onStreamFinished() }
                if let sink { await sink.close() }
                continuation.finish()
            } catch {
                if let onStreamFinished { await onStreamFinished() }
                if let sink { await sink.close() }
                continuation.finish(throwing: error)
            }
        }
    }
}

private struct UnsafeSendableIterator: @unchecked Sendable {
    var iterator: AsyncThrowingStream<Data, Error>.Iterator
}

private actor StreamMetrics {
    private var bytes: Int = 0
    private var ttfbSeconds: Double?
    private var downloadSeconds: Double?
    private var playbackSeconds: Double?

    func addBytes(_ value: Int) {
        bytes += value
    }

    func setTTFB(_ value: Double) {
        if ttfbSeconds == nil {
            ttfbSeconds = value
        }
    }

    func setDownload(_ value: Double) {
        downloadSeconds = value
    }

    func setPlayback(_ value: Double) {
        playbackSeconds = value
    }

    func snapshot() -> StreamMetricsSnapshot {
        StreamMetricsSnapshot(
            bytes: bytes,
            ttfbSeconds: ttfbSeconds,
            downloadSeconds: downloadSeconds,
            playbackSeconds: playbackSeconds
        )
    }
}

private struct StreamMetricsSnapshot {
    let bytes: Int
    let ttfbSeconds: Double?
    let downloadSeconds: Double?
    let playbackSeconds: Double?
}

private func printStreamMetrics(_ metrics: StreamMetricsSnapshot) {
    let ttfb = formatSeconds(metrics.ttfbSeconds)
    let download = formatSeconds(metrics.downloadSeconds)
    let playback = formatSeconds(metrics.playbackSeconds)
    let message = "stream_ttfb=\(ttfb) stream_download=\(download) stream_playback=\(playback) bytes=\(metrics.bytes)"
    fputs("\(message)\n", stderr)
}

private actor FileSink {
    private let handle: FileHandle

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) == false {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        self.handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
    }

    func write(_ data: Data) {
        try? handle.write(contentsOf: data)
    }

    func close() {
        try? handle.close()
    }
}

private struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private func requireValue(_ args: inout [String], flag: String) throws -> String {
    guard let value = args.first else {
        throw CLIError("Missing value for \(flag).")
    }
    args.removeFirst()
    return value
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
