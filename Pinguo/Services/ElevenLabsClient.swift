import Foundation

nonisolated struct ElevenLabsVoice: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable { case library, shared }

    let id: String
    let name: String
    let description: String
    let gender: String?
    let accent: String?
    let useCase: String?
    let previewURL: URL?
    let source: Source
    let isCustom: Bool

    var isFemale: Bool { gender?.lowercased() == "female" }
    var isMale: Bool { gender?.lowercased() == "male" }

    var isSlowAndClear: Bool {
        let text = "\(name) \(description) \(useCase ?? "")".lowercased()
        return ["slow", "calm", "clear", "gentle", "educat", "teacher", "patient"].contains { text.contains($0) }
    }

    var shortName: String {
        name.split(separator: "-").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
    }

    var subtitle: String {
        let descriptor = name.split(separator: "-", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) }
        let accentLabel = accent.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        return [descriptor ?? (description.isEmpty ? nil : description), accentLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

nonisolated struct CharacterAlignment: Codable, Sendable {
    let characters: [String]
    let starts: [Double]
    let ends: [Double]
}

nonisolated struct VoicePreview: Identifiable, Sendable {
    let id: String
    let audio: Data
}

/// ElevenLabs REST: timestamped speech, voice listing and voice design.
nonisolated struct ElevenLabsClient: Sendable {
    static let defaultVoiceID = "Xb7hH8MSUJpSbSDYk0k2"
    static let defaultVoiceName = "Alice"
    static let defaultModelID = "eleven_multilingual_v2"
    private static let base = URL(string: "https://api.elevenlabs.io")!

    var session: URLSession = .shared

    func speech(text: String, voiceID: String, modelID: String) async throws -> (audio: Data, alignment: CharacterAlignment) {
        var components = URLComponents(url: Self.base.appending(path: "v1/text-to-speech/\(voiceID)/with-timestamps"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var body: [String: Any] = ["text": text, "model_id": modelID]
        if modelID.contains("v2_5") {
            // Flash/Turbo v2.5 accept a language hint, which keeps short or mixed text in Mandarin.
            body["language_code"] = "zh"
        }
        let json = try await send(url: components.url!, method: "POST", body: body)
        guard let base64 = json["audio_base64"] as? String, let audio = Data(base64Encoded: base64) else {
            throw ServiceError.malformedResponse
        }
        let alignment = (json["alignment"] as? [String: Any]).map { raw in
            CharacterAlignment(
                characters: raw["characters"] as? [String] ?? [],
                starts: raw["character_start_times_seconds"] as? [Double] ?? [],
                ends: raw["character_end_times_seconds"] as? [Double] ?? []
            )
        }
        return (audio, alignment ?? CharacterAlignment(characters: [], starts: [], ends: []))
    }

    func libraryVoices() async throws -> [ElevenLabsVoice] {
        var components = URLComponents(url: Self.base.appending(path: "v2/voices"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "page_size", value: "100")]
        let json = try await send(url: components.url!, method: "GET", body: nil)
        return (json["voices"] as? [[String: Any]] ?? []).map { raw in
            let labels = raw["labels"] as? [String: String] ?? [:]
            let category = raw["category"] as? String ?? ""
            return ElevenLabsVoice(
                id: raw["voice_id"] as? String ?? "",
                name: raw["name"] as? String ?? "Voice",
                description: (raw["description"] as? String) ?? labels["description"] ?? "",
                gender: labels["gender"],
                accent: labels["accent"],
                useCase: labels["use_case"] ?? labels["use case"],
                previewURL: (raw["preview_url"] as? String).flatMap(URL.init(string:)),
                source: .library,
                isCustom: category == "generated" || category == "cloned" || category == "professional"
            )
        }
    }

    /// Native Mandarin voices from the shared library (usable through the API on paid plans).
    func mandarinVoices() async throws -> [ElevenLabsVoice] {
        var components = URLComponents(url: Self.base.appending(path: "v1/shared-voices"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "page_size", value: "30"),
            URLQueryItem(name: "sort", value: "usage_character_count_1y"),
        ]
        let json = try await send(url: components.url!, method: "GET", body: nil)
        return (json["voices"] as? [[String: Any]] ?? []).map { raw in
            ElevenLabsVoice(
                id: raw["voice_id"] as? String ?? "",
                name: raw["name"] as? String ?? "Voice",
                description: raw["description"] as? String ?? "",
                gender: raw["gender"] as? String,
                accent: raw["accent"] as? String,
                useCase: raw["use_case"] as? String,
                previewURL: (raw["preview_url"] as? String).flatMap(URL.init(string:)),
                source: .shared,
                isCustom: false
            )
        }
    }

    func designVoicePreviews(description: String, sampleText: String) async throws -> [VoicePreview] {
        let body: [String: Any] = [
            "voice_description": description,
            "model_id": "eleven_multilingual_ttv_v2",
            "text": sampleText,
        ]
        let json = try await send(url: Self.base.appending(path: "v1/text-to-voice/design"), method: "POST", body: body)
        return (json["previews"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let id = raw["generated_voice_id"] as? String,
                  let audio = (raw["audio_base_64"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return VoicePreview(id: id, audio: audio)
        }
    }

    func saveDesignedVoice(previewID: String, name: String, description: String) async throws -> String {
        let body: [String: Any] = ["voice_name": name, "voice_description": description, "generated_voice_id": previewID]
        let json = try await send(url: Self.base.appending(path: "v1/text-to-voice"), method: "POST", body: body)
        guard let id = json["voice_id"] as? String else { throw ServiceError.malformedResponse }
        return id
    }

    private func send(url: URL, method: String, body: [String: Any]?) async throws -> [String: Any] {
        guard let apiKey = APIKeys.key(for: .elevenLabs) else { throw ServiceError.missingKey(.elevenLabs) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status), let json else {
            let detail = json?["detail"]
            let message = ((detail as? [String: Any])?["message"] as? String) ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw ServiceError.http(status: status, message: message)
        }
        return json
    }
}
