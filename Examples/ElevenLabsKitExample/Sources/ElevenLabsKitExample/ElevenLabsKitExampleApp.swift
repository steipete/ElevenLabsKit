import AVFoundation
import ElevenLabsKit
import SwiftUI

#if os(macOS)
    import AppKit
#endif

@MainActor
@main
struct ElevenLabsKitExampleApp: App {
    enum RequestMode: String, CaseIterable, Identifiable {
        case streaming = "Streaming"
        case fetch = "Fetch"

        var id: String { rawValue }
    }

    @State private var apiKey: String = ""
    @State private var voiceId: String = ""
    @State private var modelId: String = "eleven_v3"
    @State private var outputFormat: String = "mp3_44100_128"
    @State private var text: String = "Hello from ElevenLabsKit"
    @State private var requestMode: RequestMode = .streaming

    @State private var voices: [ElevenLabsVoice] = []
    @State private var isWorking = false
    @State private var status: String = "Ready"
    @State private var audioPlayer: AVAudioPlayer?

    var body: some Scene {
        WindowGroup {
            ContentView(
                apiKey: $apiKey,
                voiceId: $voiceId,
                modelId: $modelId,
                outputFormat: $outputFormat,
                text: $text,
                requestMode: $requestMode,
                voices: $voices,
                isWorking: $isWorking,
                status: $status,
                audioPlayer: $audioPlayer
            )
            .frame(minWidth: 720, minHeight: 560)
        }
    }
}

@MainActor
private struct ContentView: View {
    @Binding var apiKey: String
    @Binding var voiceId: String
    @Binding var modelId: String
    @Binding var outputFormat: String
    @Binding var text: String
    @Binding var requestMode: ElevenLabsKitExampleApp.RequestMode

    @Binding var voices: [ElevenLabsVoice]
    @Binding var isWorking: Bool
    @Binding var status: String
    @Binding var audioPlayer: AVAudioPlayer?

    @State private var didBootstrap = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Config") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("API Key") {
                            SecureField("xi-api-key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 360)
                        }
                        LabeledContent("Voice ID") {
                            TextField("voice_id", text: $voiceId)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Model") {
                            TextField("model_id", text: $modelId)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Output") {
                            TextField("output_format (e.g. pcm_44100 / mp3_44100_128)", text: $outputFormat)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Request") {
                            Picker("Request", selection: $requestMode) {
                                ForEach(ElevenLabsKitExampleApp.RequestMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(minWidth: 260)
                        }
                    }
                }

                GroupBox("Text") {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)
                }

                HStack(spacing: 10) {
                    Button("List Voices") { Task { await listVoices() } }
                        .disabled(isWorking || apiKey.isEmpty)
                    Button(actionTitle) { Task { await synthesizeAndPlay() } }
                        .disabled(isWorking || apiKey.isEmpty || voiceId.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Stop") { stopPlayback() }
                        .disabled(isWorking == false && audioPlayer?.isPlaying != true)
                    Spacer()
                    ProgressView()
                        .opacity(isWorking ? 1 : 0)
                }

                Text(status)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .task {
                await bootstrapIfNeeded()
            }

            GroupBox("Voices") {
                List(selection: $voiceId) {
                    ForEach(voices, id: \.voiceId) { voice in
                        voiceRow(voice)
                            .tag(voice.voiceId)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func voiceRow(_ voice: ElevenLabsVoice) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(voice.name ?? "Unnamed")
            Text(voice.voiceId)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func bootstrapIfNeeded() async {
        guard didBootstrap == false else { return }
        didBootstrap = true

        #if os(macOS)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        #endif

        if apiKey.isEmpty, let systemKey = ExampleSecrets.discoverElevenLabsAPIKey() {
            apiKey = systemKey
        }
        if voiceId.isEmpty, let systemVoiceId = ExampleSecrets.discoverElevenLabsVoiceID() {
            voiceId = systemVoiceId
        }

        if apiKey.isEmpty == false {
            await listVoices()
        }
    }

    private var actionTitle: String {
        switch requestMode {
        case .streaming:
            "Stream + Play"
        case .fetch:
            "Fetch + Play"
        }
    }

    private func listVoices() async {
        guard isWorking == false else { return }

        isWorking = true
        status = "Listing voices…"
        defer { isWorking = false }

        do {
            let client = ElevenLabsTTSClient(apiKey: apiKey)
            voices = try await client.listVoices()
            status = "Voices: \(voices.count)"

            if voiceId.isEmpty || voices.contains(where: { $0.voiceId == voiceId }) == false {
                voiceId = voices.first?.voiceId ?? voiceId
            }
        } catch {
            handleRequestError(error)
        }
    }

    private func synthesizeAndPlay() async {
        switch requestMode {
        case .streaming:
            await streamAndPlay()
        case .fetch:
            await fetchAndPlay()
        }
    }

    private func streamAndPlay() async {
        isWorking = true
        status = "Streaming…"
        defer { isWorking = false }

        let normalizedOutput = ElevenLabsTTSClient.validatedOutputFormat(outputFormat) ?? outputFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = ElevenLabsTTSRequest(
            text: text,
            modelId: modelId,
            outputFormat: normalizedOutput
        )

        let client = ElevenLabsTTSClient(apiKey: apiKey)
        let stream = client.streamSynthesize(voiceId: voiceId, request: request)

        do {
            var iterator = stream.makeAsyncIterator()
            guard let firstChunk = try await iterator.next() else {
                status = "No audio returned"
                return
            }

            let detected = AudioKind.detect(from: firstChunk, requestedOutput: normalizedOutput)
            let replayStream = makeReplayStream(
                iterator: iterator,
                firstChunk: firstChunk,
                stripWavHeader: detected == .wav
            )

            switch detected {
            case .pcm, .wav:
                guard let sampleRate = TalkTTSValidation.pcmSampleRate(from: normalizedOutput) else {
                    status = "Invalid PCM output format"
                    return
                }
                let result = await PCMStreamingAudioPlayer.shared.play(stream: replayStream, sampleRate: sampleRate)
                status = result.finished ? "Finished (PCM)" : "Stopped (PCM) at \(result.interruptedAt ?? 0)s"
            case .mp3, .unknown:
                let result = await StreamingAudioPlayer.shared.play(stream: replayStream)
                status = result.finished ? "Finished (MP3)" : "Stopped (MP3) at \(result.interruptedAt ?? 0)s"
            }
        } catch {
            handleRequestError(error)
        }
    }

    private func fetchAndPlay() async {
        isWorking = true
        status = "Fetching…"
        defer { isWorking = false }

        let normalizedOutput = ElevenLabsTTSClient.validatedOutputFormat(outputFormat) ?? outputFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = ElevenLabsTTSRequest(
            text: text,
            modelId: modelId,
            outputFormat: normalizedOutput
        )

        do {
            let client = ElevenLabsTTSClient(apiKey: apiKey)
            let data = try await client.synthesize(voiceId: voiceId, request: request)

            let detected = AudioKind.detect(from: data, requestedOutput: normalizedOutput)

            switch detected {
            case .pcm:
                guard let sampleRate = TalkTTSValidation.pcmSampleRate(from: normalizedOutput) else {
                    status = "Invalid PCM output format"
                    return
                }
                let stream = AsyncThrowingStream<Data, Error> { cont in
                    cont.yield(data)
                    cont.finish()
                }
                let result = await PCMStreamingAudioPlayer.shared.play(stream: stream, sampleRate: sampleRate)
                status = result.finished ? "Finished (PCM)" : "Stopped (PCM) at \(result.interruptedAt ?? 0)s"
            case .wav, .mp3:
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.play()
                status = detected == .wav ? "Playing (WAV)" : "Playing (MP3)"
            case .unknown:
                let stream = AsyncThrowingStream<Data, Error> { cont in
                    cont.yield(data)
                    cont.finish()
                }
                let result = await StreamingAudioPlayer.shared.play(stream: stream)
                status = result.finished ? "Finished (MP3)" : "Stopped (MP3) at \(result.interruptedAt ?? 0)s"
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    private func stopPlayback() {
        _ = PCMStreamingAudioPlayer.shared.stop()
        _ = StreamingAudioPlayer.shared.stop()
        audioPlayer?.stop()
        audioPlayer = nil
        isWorking = false
        status = "Stopped"
    }

    private func handleRequestError(_ error: Error) {
        let message = error.localizedDescription
        if message.contains("output_format_not_allowed"), outputFormat.lowercased().hasPrefix("pcm_") {
            outputFormat = "mp3_44100_128"
            status = "PCM requires Pro. Switched to mp3_44100_128."
            return
        }
        status = "Error: \(message)"
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
    stripWavHeader: Bool
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
                if stripWavHeader {
                    headerBuffer.append(firstChunk)
                    drainHeaderIfPossible()
                } else {
                    continuation.yield(firstChunk)
                }

                while let chunk = try await iterator.next() {
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
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

private struct UnsafeSendableIterator: @unchecked Sendable {
    var iterator: AsyncThrowingStream<Data, Error>.Iterator
}
