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

    /// Whether a key is stored. Kept as a stored property (not computed off the Keychain)
    /// so `@Observable` tracking re-renders dependent views the moment it changes — the
    /// Settings placeholder, "Remove key" button, and the Assistant's hint all rely on this.
    private(set) var hasAPIKey: Bool

    init() {
        hasAPIKey = (Keychain.get(Self.apiKeyKeychainKey)?.isEmpty == false)
    }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(trimmed.isEmpty ? nil : trimmed, for: Self.apiKeyKeychainKey)
        hasAPIKey = !trimmed.isEmpty
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

    // MARK: - Request building

    private func makeRequest(system: String, messages: [ChatMessage], stream: Bool) throws -> URLRequest {
        guard let key = Keychain.get(Self.apiKeyKeychainKey), !key.isEmpty else {
            throw ClaudeError.missingKey
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": stream,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Streaming (preferred — replies appear token-by-token)

    /// Streams the assistant's reply as a sequence of text chunks via Server-Sent Events.
    /// Yields incremental `text_delta`s; throws on HTTP error, refusal, or cancellation.
    func streamText(system: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(system: system, messages: messages, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ClaudeError.malformed }

                    guard (200..<300).contains(http.statusCode) else {
                        // Error responses aren't streamed — drain the body for the message.
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                            .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
                            ?? String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw ClaudeError.http(http.statusCode, message)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, payload != "[DONE]",
                              let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = json["type"] as? String else { continue }

                        switch type {
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               (delta["type"] as? String) == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "message_delta":
                            // Always check stop_reason — a safety refusal arrives here.
                            if let delta = json["delta"] as? [String: Any],
                               (delta["stop_reason"] as? String) == "refusal" {
                                throw ClaudeError.refusal
                            }
                        case "error":
                            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Stream error"
                            throw ClaudeError.http(http.statusCode, msg)
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Non-streaming (single shot; used as a simple fallback)

    func send(system: String, messages: [ChatMessage]) async throws -> String {
        let request = try makeRequest(system: system, messages: messages, stream: false)
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
        if (json["stop_reason"] as? String) == "refusal" { throw ClaudeError.refusal }

        guard let content = json["content"] as? [[String: Any]] else { throw ClaudeError.malformed }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return text.isEmpty ? "(No response)" : text
    }

    // MARK: - Tool use (streaming agent loop)

    /// A tool Claude may call. `inputSchema` is a JSON-Schema object describing the arguments.
    struct ToolSpec {
        let name: String
        let description: String
        let inputSchema: [String: Any]

        var json: [String: Any] {
            ["name": name, "description": description, "input_schema": inputSchema]
        }
    }

    /// What the agent emits as it works: streamed reply text, or a note that a tool ran.
    enum AgentEvent {
        case text(String)
        case toolResult(String)
    }

    /// Streams Claude's reply while letting it call the supplied `tools`. When Claude requests
    /// a tool, `runTool` executes it on the main actor and the result is fed back so Claude can
    /// continue — a standard agentic loop, bounded by `maxTurns`. Text is streamed as it arrives.
    func streamAgent(
        system: String,
        history: [ChatMessage],
        tools: [ToolSpec],
        maxTurns: Int = 5,
        runTool: @escaping @MainActor (String, [String: Any]) -> String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = Keychain.get(Self.apiKeyKeychainKey), !key.isEmpty else {
                        throw ClaudeError.missingKey
                    }
                    // Seed the API conversation from the UI history (plain text turns).
                    var apiMessages: [[String: Any]] = history.map {
                        ["role": $0.role.rawValue, "content": $0.text]
                    }

                    for _ in 0..<maxTurns {
                        try Task.checkCancellation()
                        let request = try makeToolRequest(system: system, apiMessages: apiMessages,
                                                          tools: tools, key: key)
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else { throw ClaudeError.malformed }

                        guard (200..<300).contains(http.statusCode) else {
                            var data = Data()
                            for try await byte in bytes { data.append(byte) }
                            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String }
                                ?? String(data: data, encoding: .utf8) ?? "Unknown error"
                            throw ClaudeError.http(http.statusCode, message)
                        }

                        var assistantText = ""
                        // Tool-use blocks accumulated this turn, plus a map from SSE block index.
                        var toolUses: [(id: String, name: String, jsonBuffer: String)] = []
                        var indexToToolUse: [Int: Int] = [:]
                        var stopReason: String?

                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            guard line.hasPrefix("data:") else { continue }
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            guard !payload.isEmpty, payload != "[DONE]",
                                  let data = payload.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  let type = json["type"] as? String else { continue }

                            switch type {
                            case "content_block_start":
                                if let index = json["index"] as? Int,
                                   let block = json["content_block"] as? [String: Any],
                                   (block["type"] as? String) == "tool_use",
                                   let id = block["id"] as? String,
                                   let name = block["name"] as? String {
                                    toolUses.append((id: id, name: name, jsonBuffer: ""))
                                    indexToToolUse[index] = toolUses.count - 1
                                }
                            case "content_block_delta":
                                guard let delta = json["delta"] as? [String: Any] else { break }
                                switch delta["type"] as? String {
                                case "text_delta":
                                    if let text = delta["text"] as? String {
                                        assistantText += text
                                        continuation.yield(.text(text))
                                    }
                                case "input_json_delta":
                                    if let index = json["index"] as? Int,
                                       let tIdx = indexToToolUse[index],
                                       let partial = delta["partial_json"] as? String {
                                        toolUses[tIdx].jsonBuffer += partial
                                    }
                                default:
                                    break
                                }
                            case "message_delta":
                                if let delta = json["delta"] as? [String: Any],
                                   let reason = delta["stop_reason"] as? String {
                                    stopReason = reason
                                    if reason == "refusal" { throw ClaudeError.refusal }
                                }
                            case "error":
                                let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Stream error"
                                throw ClaudeError.http(http.statusCode, msg)
                            default:
                                break
                            }
                        }

                        // If Claude asked for tools, run them and loop; otherwise we're done.
                        guard stopReason == "tool_use", !toolUses.isEmpty else {
                            continuation.finish()
                            return
                        }

                        var assistantContent: [[String: Any]] = []
                        if !assistantText.isEmpty {
                            assistantContent.append(["type": "text", "text": assistantText])
                        }
                        for tu in toolUses {
                            assistantContent.append(["type": "tool_use", "id": tu.id, "name": tu.name,
                                                     "input": Self.parseJSONObject(tu.jsonBuffer)])
                        }
                        apiMessages.append(["role": "assistant", "content": assistantContent])

                        var resultBlocks: [[String: Any]] = []
                        for tu in toolUses {
                            let summary = await runTool(tu.name, Self.parseJSONObject(tu.jsonBuffer))
                            continuation.yield(.toolResult(summary))
                            resultBlocks.append(["type": "tool_result", "tool_use_id": tu.id, "content": summary])
                        }
                        apiMessages.append(["role": "user", "content": resultBlocks])
                    }
                    // Hit the turn limit — stop gracefully.
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func parseJSONObject(_ string: String) -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func makeToolRequest(system: String, apiMessages: [[String: Any]],
                                 tools: [ToolSpec], key: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "system": system,
            "messages": apiMessages,
            "tools": tools.map { $0.json }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
