import AVFoundation
import ElevenLabsKit
import SwiftUI

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
    @State private var outputFormat: String = "pcm_44100"
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

            GroupBox("Voices") {
                List(voices, id: \.voiceId) { voice in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name ?? "Unnamed")
                        Text(voice.voiceId)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
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
        isWorking = true
        status = "Listing voices…"
        defer { isWorking = false }

        do {
            let client = ElevenLabsTTSClient(apiKey: apiKey)
            voices = try await client.listVoices()
            status = "Voices: \(voices.count)"
        } catch {
            status = "Error: \(error.localizedDescription)"
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

        if let sampleRate = TalkTTSValidation.pcmSampleRate(from: normalizedOutput) {
            let result = await PCMStreamingAudioPlayer.shared.play(stream: stream, sampleRate: sampleRate)
            status = result.finished ? "Finished (PCM)" : "Stopped (PCM) at \(result.interruptedAt ?? 0)s"
        } else {
            let result = await StreamingAudioPlayer.shared.play(stream: stream)
            status = result.finished ? "Finished (MP3)" : "Stopped (MP3) at \(result.interruptedAt ?? 0)s"
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

            if let sampleRate = TalkTTSValidation.pcmSampleRate(from: normalizedOutput) {
                let stream = AsyncThrowingStream<Data, Error> { cont in
                    cont.yield(data)
                    cont.finish()
                }
                let result = await PCMStreamingAudioPlayer.shared.play(stream: stream, sampleRate: sampleRate)
                status = result.finished ? "Finished (PCM)" : "Stopped (PCM) at \(result.interruptedAt ?? 0)s"
                return
            }

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
            status = "Playing (MP3)"
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
}
