import Foundation

/// Sentence translation on-device, cached in memory and on disk so each sentence is translated once.
actor TranslationService {
    static let shared = TranslationService()

    private var cache: [String: String] = [:]
    private let cacheURL = URL.cachesDirectory.appending(path: "sentence-translations-on-device.json")
    private var loaded = false

    func translate(_ sentence: String) async throws -> String {
        loadIfNeeded()
        if let cached = cache[sentence] { return cached }
        let translation = try await AppleTranslator.chineseToEnglish.translate(sentence)
        cache[sentence] = translation
        persist()
        return translation
    }

    /// Translates every uncached sentence up front so tapping one later is instant.
    func prepare(_ sentences: [String]) async throws {
        loadIfNeeded()
        var seen = Set<String>()
        let missing = sentences.filter { cache[$0] == nil && seen.insert($0).inserted }
        for start in stride(from: 0, to: missing.count, by: 50) {
            try Task.checkCancellation()
            let batch = Array(missing[start..<min(start + 50, missing.count)])
            let translations = try await AppleTranslator.chineseToEnglish.translate(batch)
            for (sentence, translation) in zip(batch, translations) where translation != sentence {
                cache[sentence] = translation
            }
            persist()
        }
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
