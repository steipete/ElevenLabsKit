import Foundation
import Security

enum ExampleSecrets {
    static func discoverElevenLabsAPIKey() -> String? {
        firstNonEmpty([
            env("XI_API_KEY"),
            env("ELEVENLABS_API_KEY"),
            env("ELEVEN_API_KEY"),
            env("ELEVENLABS_XI_API_KEY"),
            keychainValue(service: "ElevenLabs", account: "xi-api-key"),
            keychainValue(service: "ElevenLabs", account: "apiKey"),
            keychainValue(service: "ElevenLabsKit", account: "xi-api-key"),
            keychainValue(service: "api.elevenlabs.io", account: "xi-api-key"),
            netrcPassword(machine: "api.elevenlabs.io")
        ])
    }

    static func discoverElevenLabsVoiceID() -> String? {
        firstNonEmpty([
            env("ELEVENLABS_VOICE_ID"),
            env("XI_VOICE_ID")
        ])
    }

    private static func env(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name]
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func keychainValue(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func netrcPassword(machine: String) -> String? {
        guard let text = try? String(contentsOf: netrcURL(), encoding: .utf8) else { return nil }
        let tokens = netrcTokens(from: text)

        var idx = 0
        while idx < tokens.count {
            guard tokens[idx] == "machine", idx + 1 < tokens.count else {
                idx += 1
                continue
            }

            let foundMachine = tokens[idx + 1]
            idx += 2

            var password: String?
            while idx < tokens.count, tokens[idx] != "machine" {
                guard idx + 1 < tokens.count else { break }
                let key = tokens[idx]
                let value = tokens[idx + 1]
                if key == "password" { password = value }
                idx += 2
            }

            if foundMachine == machine {
                return password?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }

        return nil
    }

    private static func netrcURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".netrc")
    }

    private static func netrcTokens(from text: String) -> [String] {
        let withoutComments = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            }
            .joined(separator: "\n")

        return withoutComments
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }.first
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
