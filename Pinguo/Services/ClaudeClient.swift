import Foundation

nonisolated enum ServiceError: LocalizedError {
    case missingKey(APIService)
    case http(status: Int, message: String)
    case refused
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingKey(let service): "Add your \(service.displayName) API key in Settings."
        case .http(let status, let message): "Request failed (\(status)): \(message)"
        case .refused: "The model declined this request."
        case .malformedResponse: "The response could not be read."
        }
    }
}

/// Raw HTTP client for the Claude Messages API (there is no official Swift SDK).
nonisolated struct ClaudeClient: Sendable {
    struct Message: Encodable, Sendable {
        let role: String
        let content: String

        static func user(_ text: String) -> Message { Message(role: "user", content: text) }
        static func assistant(_ text: String) -> Message { Message(role: "assistant", content: text) }
    }

    enum Effort: String, Sendable {
        case low, medium, high
    }

    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var session: URLSession = .shared

    func text(system: String, messages: [Message], effort: Effort = .low, maxTokens: Int = 4000) async throws -> String {
        try await send(system: system, messages: messages, effort: effort, maxTokens: maxTokens, schema: nil)
    }

    /// Structured output: the reply is constrained to `schema` and decoded into `T`.
    func json<T: Decodable>(
        _ type: T.Type,
        system: String,
        messages: [Message],
        schema: [String: Any],
        effort: Effort = .low,
        maxTokens: Int = 8000
    ) async throws -> T {
        let text = try await send(system: system, messages: messages, effort: effort, maxTokens: maxTokens, schema: schema)
        guard let data = text.data(using: .utf8) else { throw ServiceError.malformedResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(system: String, messages: [Message], effort: Effort, maxTokens: Int, schema: [String: Any]?) async throws -> String {
        guard let apiKey = APIKeys.key(for: .anthropic) else { throw ServiceError.missingKey(.anthropic) }

        var outputConfig: [String: Any] = ["effort": effort.rawValue]
        if let schema {
            outputConfig["format"] = ["type": "json_schema", "schema": schema]
        }
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "output_config": outputConfig,
            "fallbacks": "default",
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let json else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data, as: UTF8.self)
            throw ServiceError.http(status: status, message: message)
        }
        if json["stop_reason"] as? String == "refusal" { throw ServiceError.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw ServiceError.malformedResponse }
        return text
    }
}
