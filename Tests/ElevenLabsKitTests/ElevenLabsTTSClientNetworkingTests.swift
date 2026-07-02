@testable import ElevenLabsKit
import Foundation
import Testing

@Suite(.serialized) final class ElevenLabsTTSClientNetworkingTests {
    private actor SleepRecorder {
        private var calls: [TimeInterval] = []
        func record(_ seconds: TimeInterval) {
            calls.append(seconds)
        }

        func snapshot() -> [TimeInterval] {
            calls
        }
    }

    @Test func `synthesize returns data on success`() async throws {
        let url = try #require(URL(string: "https://example.invalid/v1/text-to-speech/voice"))
        URLProtocolStub.setStubs([
            .init(
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                    "Content-Type": "audio/mpeg"
                ]),
                dataChunks: [Data([0x01, 0x02, 0x03])],
                error: nil
            )
        ])
        defer {
            URLProtocolStub.setRequestObserver(nil)
            URLProtocolStub.setStubs([])
        }

        var capturedRequest: URLRequest?
        URLProtocolStub.setRequestObserver { capturedRequest = $0 }

        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(apiKey: "k", baseUrl: #require(URL(string: "https://example.invalid")), urlSession: session)
        let request = ElevenLabsTTSRequest(text: "hi", outputFormat: "mp3_44100_128")

        let data = try await client.synthesize(voiceId: "voice", request: request)
        #expect(data == Data([0x01, 0x02, 0x03]))
        #expect(capturedRequest?.url?.query == "output_format=mp3_44100_128")
        #expect(ElevenLabsTTSClient.buildPayload(request)["output_format"] == nil)
    }

    @Test func `hard timeout permits request to finish first`() async throws {
        let url = try #require(URL(string: "https://example.invalid/v1/text-to-speech/voice"))
        URLProtocolStub.setStubs([
            .init(
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                    "Content-Type": "audio/mpeg"
                ]),
                dataChunks: [Data([0x01])],
                error: nil
            )
        ])
        defer { URLProtocolStub.setStubs([]) }

        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(
            apiKey: "k",
            baseUrl: #require(URL(string: "https://example.invalid")),
            urlSession: session,
            sleep: { _ in try? await Task.sleep(for: .seconds(10)) }
        )

        let data = try await client.synthesizeWithHardTimeout(
            voiceId: "voice",
            request: ElevenLabsTTSRequest(text: "hi"),
            hardTimeoutSeconds: 10
        )
        #expect(data == Data([0x01]))
    }

    @Test func `hard timeout rejects invalid duration`() async throws {
        let client = ElevenLabsTTSClient(apiKey: "k")
        await #expect(throws: Error.self) {
            _ = try await client.synthesizeWithHardTimeout(
                voiceId: "voice",
                request: ElevenLabsTTSRequest(text: "hi"),
                hardTimeoutSeconds: 0
            )
        }
    }

    @Test func `synthesize retries on 500 without sleeping in tests`() async throws {
        let url = try #require(URL(string: "https://example.invalid/v1/text-to-speech/voice"))
        URLProtocolStub.setStubs([
            .init(
                response: HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: [
                    "Content-Type": "application/json"
                ]),
                dataChunks: [Data("nope".utf8)],
                error: nil
            ),
            .init(
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                    "Content-Type": "audio/mpeg"
                ]),
                dataChunks: [Data("ok".utf8)],
                error: nil
            )
        ])
        defer { URLProtocolStub.setStubs([]) }

        let sleepRecorder = SleepRecorder()
        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(
            apiKey: "k",
            baseUrl: #require(URL(string: "https://example.invalid")),
            urlSession: session,
            sleep: { seconds in await sleepRecorder.record(seconds) }
        )

        let data = try await client.synthesize(voiceId: "voice", request: ElevenLabsTTSRequest(text: "hi", outputFormat: "mp3_44100_128"))
        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect(await (sleepRecorder.snapshot()).count == 1)
    }

    @Test func `synthesize does not retry client errors`() async throws {
        let url = try #require(URL(string: "https://example.invalid/v1/text-to-speech/voice"))
        URLProtocolStub.setStubs([
            .init(
                response: HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: [
                    "Content-Type": "application/json"
                ]),
                dataChunks: [Data(#"{"detail":"bad request"}"#.utf8)],
                error: nil
            )
        ])
        defer {
            URLProtocolStub.setRequestObserver(nil)
            URLProtocolStub.setStubs([])
        }

        var requestCount = 0
        URLProtocolStub.setRequestObserver { _ in requestCount += 1 }
        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(apiKey: "k", baseUrl: #require(URL(string: "https://example.invalid")), urlSession: session)

        await #expect(throws: Error.self) {
            _ = try await client.synthesize(voiceId: "voice", request: ElevenLabsTTSRequest(text: "hi"))
        }
        #expect(requestCount == 1)
    }

    @Test func `synthesize does not retry cancellation`() async throws {
        URLProtocolStub.setStubs([
            .init(response: nil, dataChunks: [], error: URLError(.cancelled))
        ])
        defer {
            URLProtocolStub.setRequestObserver(nil)
            URLProtocolStub.setStubs([])
        }

        var requestCount = 0
        URLProtocolStub.setRequestObserver { _ in requestCount += 1 }
        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(apiKey: "k", baseUrl: #require(URL(string: "https://example.invalid")), urlSession: session)

        await #expect(throws: Error.self) {
            _ = try await client.synthesize(voiceId: "voice", request: ElevenLabsTTSRequest(text: "hi"))
        }
        #expect(requestCount == 1)
    }

    @Test func `synthesize accepts octet stream for PCM`() async throws {
        let url = try #require(URL(string: "https://example.invalid/v1/text-to-speech/voice"))
        URLProtocolStub.setStubs([
            .init(
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                    "Content-Type": "application/octet-stream"
                ]),
                dataChunks: [Data(repeating: 0, count: 4)],
                error: nil
            )
        ])
        defer { URLProtocolStub.setStubs([]) }

        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(apiKey: "k", baseUrl: #require(URL(string: "https://example.invalid")), urlSession: session)
        let data = try await client.synthesize(voiceId: "voice", request: ElevenLabsTTSRequest(text: "hi", outputFormat: "pcm_44100"))
        #expect(data.count == 4)
    }

    @Test func `synthesize throws for non audio content type`() async throws {
        let url = try #require(URL(string: "https://example.invalid/v1/text-to-speech/voice"))
        URLProtocolStub.setStubs([
            .init(
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                    "Content-Type": "text/plain"
                ]),
                dataChunks: [Data("no audio".utf8)],
                error: nil
            )
        ])
        defer { URLProtocolStub.setStubs([]) }

        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(apiKey: "k", baseUrl: #require(URL(string: "https://example.invalid")), urlSession: session)

        await #expect(throws: Error.self) {
            _ = try await client.synthesize(voiceId: "voice", request: ElevenLabsTTSRequest(text: "hi", outputFormat: "mp3_44100_128"))
        }
    }

    @Test func `list voices decodes response`() async throws {
        let url = try #require(URL(string: "https://example.invalid/v1/voices"))
        URLProtocolStub.setStubs([
            .init(
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
                dataChunks: [Data(#"{"voices":[{"voice_id":"v1","name":"A"},{"voice_id":"v2"}]}"#.utf8)],
                error: nil
            )
        ])
        defer { URLProtocolStub.setStubs([]) }

        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(apiKey: "k", baseUrl: #require(URL(string: "https://example.invalid")), urlSession: session)
        let voices = try await client.listVoices()
        #expect(voices.count == 2)
        #expect(voices[0].voiceId == "v1")
        #expect(voices[0].name == "A")
        #expect(voices[1].voiceId == "v2")
    }

    @Test func `stream synthesize builds URL with output format and latency tier`() async throws {
        let url = try #require(URL(string: "https://example.invalid/v1/text-to-speech/voice/stream?output_format=mp3_44100_128&optimize_streaming_latency=4"))
        URLProtocolStub.setStubs([
            .init(
                response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                    "Content-Type": "audio/mpeg"
                ]),
                dataChunks: [Data(repeating: 0x7F, count: 10000)],
                error: nil
            )
        ])
        defer {
            URLProtocolStub.setRequestObserver(nil)
            URLProtocolStub.setStubs([])
        }

        var requestedURL: URL?
        URLProtocolStub.setRequestObserver { request in requestedURL = request.url }

        let session = URLProtocolStub.makeSession()
        let client = try ElevenLabsTTSClient(apiKey: "k", baseUrl: #require(URL(string: "https://example.invalid")), urlSession: session)
        let request = ElevenLabsTTSRequest(text: "hi", outputFormat: "mp3_44100_128", latencyTier: 4)

        var chunks: [Data] = []
        for try await chunk in client.streamSynthesize(voiceId: "voice", request: request) {
            chunks.append(chunk)
        }

        #expect(requestedURL?.absoluteString.contains("output_format=mp3_44100_128") == true)
        #expect(requestedURL?.absoluteString.contains("optimize_streaming_latency=4") == true)
        #expect(chunks.first?.count == 2048)
        #expect(chunks.reduce(0) { $0 + $1.count } == 10000)
    }
}
