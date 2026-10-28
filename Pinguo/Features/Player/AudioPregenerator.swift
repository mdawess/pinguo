import Foundation

/// Generates and caches narration for a whole document up front (opt-in on import, since it spends credits).
nonisolated enum AudioPregenerator {
    static func run(chapters: [[String]], voiceID: String, modelID: String) async {
        for sentences in chapters {
            for chunk in NarrationPlanner.chunks(for: sentences) {
                let text = Array(sentences[chunk.sentenceRange])
                do {
                    _ = try await AudioCache.shared.cloudClip(sentences: text, voiceID: voiceID, modelID: modelID)
                } catch {
                    return
                }
            }
        }
    }
}
