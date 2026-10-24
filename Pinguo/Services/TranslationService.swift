import Foundation

/// Sentence translation with an in-memory and on-disk cache so each sentence is only sent once.
actor TranslationService {
    static let shared = TranslationService()

    private let client = ClaudeClient()
    private var cache: [String: String] = [:]
    private let cacheURL = URL.cachesDirectory.appending(path: "sentence-translations.json")
    private var loaded = false

    func translate(_ sentence: String, context: String? = nil) async throws -> String {
        loadIfNeeded()
        if let cached = cache[sentence] { return cached }
        var prompt = "Translate this Mandarin sentence into natural English. Reply with the translation only.\n\n\(sentence)"
        if let context, !context.isEmpty {
            prompt += "\n\nSurrounding text for context (do not translate):\n\(context)"
        }
        let translation = try await client.text(
            system: "You translate Mandarin Chinese for an English-speaking learner around HSK 3–4. Be faithful and natural.",
            messages: [.user(prompt)]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        cache[sentence] = translation
        persist()
        return translation
    }

    func cachedTranslation(of sentence: String) -> String? {
        loadIfNeeded()
        return cache[sentence]
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: cacheURL), let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = stored
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
