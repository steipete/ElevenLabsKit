import Foundation

/// A minimal voice descriptor returned by the ElevenLabs voices endpoint.
public struct ElevenLabsVoice: Decodable, Sendable {
    /// Unique voice identifier.
    public let voiceId: String
    /// Human-readable voice name.
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name
    }
}

/// Request payload for text-to-speech synthesis.
public struct ElevenLabsTTSRequest: Sendable {
    /// Text to synthesize.
    public var text: String
    /// Model ID (e.g. `eleven_v3`).
    public var modelId: String?
    /// Output format (e.g. `mp3_44100_128`, `pcm_44100`).
    public var outputFormat: String?
    /// Speed multiplier (0.5–2.0).
    public var speed: Double?
    /// Stability control (0–1). v3 supports 0, 0.5, 1.
    public var stability: Double?
    /// Similarity boost (0–1).
    public var similarity: Double?
    /// Style amount (0–1).
    public var style: Double?
    /// Toggle speaker boost (model dependent).
    public var speakerBoost: Bool?
    /// Optional seed for repeatability.
    public var seed: UInt32?
    /// Text normalization mode (`auto`, `on`, `off`).
    public var normalize: String?
    /// Language code (ISO 639-1).
    public var language: String?
    /// Streaming latency tier (0–4).
    public var latencyTier: Int?

    /// Creates a request payload.
    public init(
        text: String,
        modelId: String? = nil,
        outputFormat: String? = nil,
        speed: Double? = nil,
        stability: Double? = nil,
        similarity: Double? = nil,
        style: Double? = nil,
        speakerBoost: Bool? = nil,
        seed: UInt32? = nil,
        normalize: String? = nil,
        language: String? = nil,
        latencyTier: Int? = nil
    ) {
        self.text = text
        self.modelId = modelId
        self.outputFormat = outputFormat
        self.speed = speed
        self.stability = stability
        self.similarity = similarity
        self.style = style
        self.speakerBoost = speakerBoost
        self.seed = seed
        self.normalize = normalize
        self.language = language
        self.latencyTier = latencyTier
    }
}

/// HTTP client for ElevenLabs text-to-speech endpoints.
public struct ElevenLabsTTSClient: Sendable {
    /// API key for authentication.
    public var apiKey: String
    /// Timeout for synthesize requests.
    public var requestTimeoutSeconds: TimeInterval
    /// Timeout for list voices requests.
    public var listVoicesTimeoutSeconds: TimeInterval
    /// Base URL for the API (defaults to `https://api.elevenlabs.io`).
    public var baseUrl: URL

    private let urlSession: URLSession
    private let sleep: @Sendable (TimeInterval) async -> Void

    /// Creates a client.
    public init(
        apiKey: String,
        requestTimeoutSeconds: TimeInterval = 45,
        listVoicesTimeoutSeconds: TimeInterval = 15,
        baseUrl: URL = URL(string: "https://api.elevenlabs.io")!,
        urlSession: URLSession = .shared,
        sleep: (@Sendable (TimeInterval) async -> Void)? = nil
    ) {
        self.apiKey = apiKey
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.listVoicesTimeoutSeconds = listVoicesTimeoutSeconds
        self.baseUrl = baseUrl
        self.urlSession = urlSession
        self.sleep = sleep ?? { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    /// Synthesizes speech with a hard timeout that cancels any longer request.
    public func synthesizeWithHardTimeout(
        voiceId: String,
        request: ElevenLabsTTSRequest,
        hardTimeoutSeconds: TimeInterval
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await synthesize(voiceId: voiceId, request: request)
            }
            group.addTask {
                await sleep(hardTimeoutSeconds)
                throw NSError(domain: "ElevenLabsTTS", code: 408, userInfo: [
                    NSLocalizedDescriptionKey: "ElevenLabs TTS timed out after \(hardTimeoutSeconds)s"
                ])
            }
            let data = try await group.next()!
            group.cancelAll()
            return data
        }
    }

    /// Synthesizes speech and returns the full audio payload.
    public func synthesize(voiceId: String, request: ElevenLabsTTSRequest) async throws -> Data {
        var url = baseUrl
        url.appendPathComponent("v1")
        url.appendPathComponent("text-to-speech")
        url.appendPathComponent(voiceId)

        let body = try JSONSerialization.data(withJSONObject: Self.buildPayload(request), options: [])

        var lastError: Error?
        for attempt in 0..<3 {
            let req = Self.buildSynthesizeRequest(
                url: url,
                apiKey: apiKey,
                body: body,
                timeoutSeconds: requestTimeoutSeconds,
                outputFormat: request.outputFormat
            )

            do {
                let (data, response) = try await urlSession.data(for: req)
                if let http = response as? HTTPURLResponse {
                    let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "unknown").lowercased()
                    if http.statusCode == 429 || http.statusCode >= 500 {
                        let message = Self.truncatedErrorBody(data)
                        lastError = NSError(domain: "ElevenLabsTTS", code: http.statusCode, userInfo: [
                            NSLocalizedDescriptionKey: "ElevenLabs retryable failure: \(http.statusCode) ct=\(contentType) \(message)"
                        ])
                        if attempt < 2 {
                            let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "")
                            let baseDelay = [0.25, 0.75, 1.5][attempt]
                            let delaySeconds = max(baseDelay, retryAfter ?? 0)
                            await sleep(delaySeconds)
                            continue
                        }
                        throw lastError!
                    }

                    if http.statusCode >= 400 {
                        let message = Self.truncatedErrorBody(data)
                        throw NSError(domain: "ElevenLabsTTS", code: http.statusCode, userInfo: [
                            NSLocalizedDescriptionKey: "ElevenLabs failed: \(http.statusCode) ct=\(contentType) \(message)"
                        ])
                    }

                    if !Self.isAudioContentType(contentType, outputFormat: request.outputFormat) {
                        let message = Self.truncatedErrorBody(data)
                        throw NSError(domain: "ElevenLabsTTS", code: 415, userInfo: [
                            NSLocalizedDescriptionKey: "ElevenLabs returned non-audio ct=\(contentType) \(message)"
                        ])
                    }
                }
                return data
            } catch {
                lastError = error
                if attempt < 2 {
                    await sleep([0.25, 0.75, 1.5][attempt])
                    continue
                }
                throw error
            }
        }
        throw lastError ?? NSError(domain: "ElevenLabsTTS", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "ElevenLabs failed"
        ])
    }

    /// Synthesizes speech as a byte stream. Yields audio chunks as they arrive.
    public func streamSynthesize(
        voiceId: String,
        request: ElevenLabsTTSRequest
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let chunkSize = 2048
            let task = Task {
                do {
                    let url = Self.streamingURL(
                        baseUrl: baseUrl,
                        voiceId: voiceId,
                        outputFormat: request.outputFormat,
                        latencyTier: request.latencyTier
                    )
                    let body = try JSONSerialization.data(withJSONObject: Self.buildPayload(request), options: [])

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.httpBody = body
                    req.timeoutInterval = requestTimeoutSeconds
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let accept = Self.acceptHeader(for: request.outputFormat) {
                        req.setValue(accept, forHTTPHeaderField: "Accept")
                    }
                    req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

                    let (bytes, response) = try await urlSession.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw NSError(domain: "ElevenLabsTTS", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "ElevenLabs invalid response"
                        ])
                    }

                    let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "unknown").lowercased()
                    if http.statusCode >= 400 {
                        let message = try await Self.readErrorBody(bytes: bytes)
                        throw NSError(domain: "ElevenLabsTTS", code: http.statusCode, userInfo: [
                            NSLocalizedDescriptionKey: "ElevenLabs failed: \(http.statusCode) ct=\(contentType) \(message)"
                        ])
                    }
                    if !Self.isAudioContentType(contentType, outputFormat: request.outputFormat) {
                        let message = try await Self.readErrorBody(bytes: bytes)
                        throw NSError(domain: "ElevenLabsTTS", code: 415, userInfo: [
                            NSLocalizedDescriptionKey: "ElevenLabs returned non-audio ct=\(contentType) \(message)"
                        ])
                    }

                    var buffer = Data()
                    buffer.reserveCapacity(chunkSize)
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Lists available voices for the account.
    public func listVoices() async throws -> [ElevenLabsVoice] {
        var url = baseUrl
        url.appendPathComponent("v1")
        url.appendPathComponent("voices")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = listVoicesTimeoutSeconds
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let message = Self.truncatedErrorBody(data)
            throw NSError(domain: "ElevenLabsTTS", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "ElevenLabs voices failed: \(http.statusCode) \(message)"
            ])
        }

        struct VoicesResponse: Decodable { let voices: [ElevenLabsVoice] }
        return try JSONDecoder().decode(VoicesResponse.self, from: data).voices
    }

    /// Validates a supported output format string.
    public static func validatedOutputFormat(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("mp3_") || trimmed.hasPrefix("pcm_") else { return nil }
        return trimmed
    }

    /// Validates a 2-letter language code.
    public static func validatedLanguage(_ value: String?) -> String? {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 2, normalized.allSatisfy({ $0 >= "a" && $0 <= "z" }) else { return nil }
        return normalized
    }

    /// Validates a normalize option (`auto`, `on`, `off`).
    public static func validatedNormalize(_ value: String?) -> String? {
        let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["auto", "on", "off"].contains(normalized) else { return nil }
        return normalized
    }

    private static func buildPayload(_ request: ElevenLabsTTSRequest) -> [String: Any] {
        var payload: [String: Any] = ["text": request.text]
        if let modelId = request.modelId?.trimmingCharacters(in: .whitespacesAndNewlines), !modelId.isEmpty {
            payload["model_id"] = modelId
        }
        if let outputFormat = request.outputFormat?.trimmingCharacters(in: .whitespacesAndNewlines), !outputFormat.isEmpty {
            payload["output_format"] = outputFormat
        }
        if let seed = request.seed {
            payload["seed"] = seed
        }
        if let normalize = request.normalize {
            payload["apply_text_normalization"] = normalize
        }
        if let language = request.language {
            payload["language_code"] = language
        }

        var voiceSettings: [String: Any] = [:]
        if let speed = request.speed { voiceSettings["speed"] = speed }
        if let stability = request.stability { voiceSettings["stability"] = stability }
        if let similarity = request.similarity { voiceSettings["similarity_boost"] = similarity }
        if let style = request.style { voiceSettings["style"] = style }
        if let speakerBoost = request.speakerBoost { voiceSettings["use_speaker_boost"] = speakerBoost }
        if !voiceSettings.isEmpty {
            payload["voice_settings"] = voiceSettings
        }
        return payload
    }

    private static func truncatedErrorBody(_ data: Data) -> String {
        let raw = String(data: data.prefix(4096), encoding: .utf8) ?? "unknown"
        return raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    private static func streamingURL(
        baseUrl: URL,
        voiceId: String,
        outputFormat: String?,
        latencyTier: Int?
    ) -> URL {
        var url = baseUrl
        url.appendPathComponent("v1")
        url.appendPathComponent("text-to-speech")
        url.appendPathComponent(voiceId)
        url.appendPathComponent("stream")

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        if let outputFormat = outputFormat?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputFormat.isEmpty
        {
            items.append(URLQueryItem(name: "output_format", value: outputFormat))
        }
        if let latencyTier {
            items.append(URLQueryItem(name: "optimize_streaming_latency", value: "\(latencyTier)"))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? url
    }

    private static func acceptHeader(for outputFormat: String?) -> String? {
        let normalized = (outputFormat ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("pcm_") { return "audio/pcm" }
        if normalized.hasPrefix("mp3_") { return "audio/mpeg" }
        return nil
    }

    static func buildSynthesizeRequest(
        url: URL,
        apiKey: String,
        body: Data,
        timeoutSeconds: TimeInterval,
        outputFormat: String?
    ) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = timeoutSeconds
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.acceptHeader(for: outputFormat) ?? "audio/mpeg", forHTTPHeaderField: "Accept")
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        return req
    }

    private static func isAudioContentType(_ contentType: String, outputFormat: String?) -> Bool {
        if contentType.contains("audio") { return true }
        let normalized = (outputFormat ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("pcm_"), contentType.contains("octet-stream") {
            return true
        }
        return false
    }

    private static func readErrorBody(bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= 4096 { break }
        }
        return truncatedErrorBody(data)
    }
}
