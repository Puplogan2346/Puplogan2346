import Foundation
import Observation

/// Talks to the Claude API (Anthropic Messages API) over HTTPS.
///
/// Swift has no official Anthropic SDK, so we call `POST /v1/messages` directly with
/// URLSession. The API key is read from the Keychain and never leaves the device except
/// in the request to api.anthropic.com.
///
/// NOTE: For a shipping app you'd typically proxy these calls through your own backend so
/// the API key isn't on the device at all. For a personal starter, on-device + Keychain is
/// a reasonable place to begin — see Settings for where the key is entered.
@Observable
final class ClaudeService {
    static let apiKeyKeychainKey = "anthropic_api_key"
    private let model = "claude-opus-4-8"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var hasAPIKey: Bool { (Keychain.get(Self.apiKeyKeychainKey)?.isEmpty == false) }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(trimmed.isEmpty ? nil : trimmed, for: Self.apiKeyKeychainKey)
    }

    enum ClaudeError: LocalizedError {
        case missingKey
        case http(Int, String)
        case refusal
        case malformed

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Add your Claude API key in Settings to use AI features."
            case .http(let code, let msg): return "Claude API error (\(code)): \(msg)"
            case .refusal: return "Claude declined to answer that one."
            case .malformed: return "Couldn't read Claude's response."
            }
        }
    }

    /// Send a conversation and get back assistant text.
    func send(system: String, messages: [ChatMessage]) async throws -> String {
        guard let key = Keychain.get(Self.apiKeyKeychainKey), !key.isEmpty else {
            throw ClaudeError.missingKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.malformed }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
                ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.http(http.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.malformed
        }

        // Always check stop_reason before reading content — a safety refusal returns 200.
        if (json["stop_reason"] as? String) == "refusal" { throw ClaudeError.refusal }

        guard let content = json["content"] as? [[String: Any]] else { throw ClaudeError.malformed }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()

        return text.isEmpty ? "(No response)" : text
    }
}
