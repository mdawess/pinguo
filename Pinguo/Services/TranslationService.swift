import Foundation

nonisolated struct SentenceTranslation: Sendable {
    let text: String
    let isOnDevice: Bool
}

/// Sentence translation with an in-memory and on-disk cache so each sentence is only sent once.
/// Claude is preferred; offline, Apple's on-device translation fills in and is cached separately so the
/// Claude version replaces it once back online.
actor TranslationService {
    static let shared = TranslationService()

    private let client = ClaudeClient()
    private var cache: [String: String] = [:]
    private var onDeviceCache: [String: String] = [:]
    private let cacheURL = URL.cachesDirectory.appending(path: "sentence-translations.json")
    private let onDeviceCacheURL = URL.cachesDirectory.appending(path: "sentence-translations-on-device.json")
    private var loaded = false

    func translate(_ sentence: String, context: String? = nil) async throws -> String {
        try await translation(of: sentence, context: context).text
    }

    func translation(of sentence: String, context: String? = nil) async throws -> SentenceTranslation {
        loadIfNeeded()
        if let cached = cache[sentence] { return SentenceTranslation(text: cached, isOnDevice: false) }
        guard CloudReachability.shouldTryCloud, APIKeys.hasKey(for: .anthropic) else { return try await onDeviceTranslation(of: sentence) }
        do {
            return SentenceTranslation(text: try await cloudTranslation(of: sentence, context: context), isOnDevice: false)
        } catch where CloudReachability.isOffline(error) {
            return try await onDeviceTranslation(of: sentence)
        }
    }

    func cachedTranslation(of sentence: String) -> String? {
        loadIfNeeded()
        return cache[sentence]
    }

    /// Translates every uncached sentence with Claude in batches, ahead of going offline.
    func prepareTranslations(for sentences: [String], onProgress: @Sendable (_ done: Int, _ total: Int) async -> Void) async throws {
        loadIfNeeded()
        var seen = Set<String>()
        let unique = sentences.filter { seen.insert($0).inserted }
        let missing = unique.filter { cache[$0] == nil }
        var done = unique.count - missing.count
        await onProgress(done, unique.count)
        for start in stride(from: 0, to: missing.count, by: 40) {
            let batch = Array(missing[start..<min(start + 40, missing.count)])
            let translations = try await batchTranslation(of: batch)
            for (sentence, translation) in zip(batch, translations) { cache[sentence] = translation }
            persist()
            done += batch.count
            await onProgress(done, unique.count)
        }
    }

    private func cloudTranslation(of sentence: String, context: String?) async throws -> String {
        var prompt = "Translate this Mandarin sentence into natural English. Reply with the translation only.\n\n\(sentence)"
        if let context, !context.isEmpty {
            prompt += "\n\nSurrounding text for context (do not translate):\n\(context)"
        }
        let translation = try await client.text(system: Self.system, messages: [.user(prompt)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cache[sentence] = translation
        persist()
        return translation
    }

    private struct BatchResponse: Decodable {
        let translations: [String]
    }

    private func batchTranslation(of sentences: [String]) async throws -> [String] {
        let numbered = sentences.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "translations": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "One natural English translation per numbered sentence, in the same order, without numbers.",
                ],
            ],
            "required": ["translations"],
            "additionalProperties": false,
        ]
        let response = try await client.json(
            BatchResponse.self,
            system: Self.system,
            messages: [.user("Translate each of these \(sentences.count) consecutive Mandarin sentences into natural English, using the others as context.\n\n\(numbered)")],
            schema: schema
        )
        guard response.translations.count == sentences.count else { throw ServiceError.malformedResponse }
        return response.translations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func onDeviceTranslation(of sentence: String) async throws -> SentenceTranslation {
        if let cached = onDeviceCache[sentence] { return SentenceTranslation(text: cached, isOnDevice: true) }
        let translation = try await OnDeviceTranslator.shared.translate(sentence)
        onDeviceCache[sentence] = translation
        persist()
        return SentenceTranslation(text: translation, isOnDevice: true)
    }

    private static let system = "You translate Mandarin Chinese for an English-speaking learner around HSK 3–4. Be faithful and natural."

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        cache = Self.read(cacheURL)
        onDeviceCache = Self.read(onDeviceCacheURL)
    }

    private static func read(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(onDeviceCache) { try? data.write(to: onDeviceCacheURL, options: .atomic) }
    }
}
