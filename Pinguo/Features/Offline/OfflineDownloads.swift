import Foundation
import Observation

enum OfflineScope: Hashable {
    case nextChapters(Int)
    case wholeBook
}

/// Downloads Claude translations and ElevenLabs narration for part of a document while online,
/// so the reader keeps its best quality on a flight.
@Observable
final class OfflineDownloads {
    static let shared = OfflineDownloads()

    struct Job {
        var completed = 0
        var total = 1
        var isFinished = false
        var failure: String?

        var fraction: Double { min(1, Double(completed) / Double(max(total, 1))) }
    }

    private(set) var jobs: [UUID: Job] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func job(for document: Document) -> Job? {
        jobs[document.id]
    }

    func isDownloading(_ document: Document) -> Bool {
        tasks[document.id] != nil
    }

    static func chapters(of document: Document, scope: OfflineScope) -> [[String]] {
        let chapters = document.orderedChapters.filter { $0.index >= document.lastChapterIndex || scope == .wholeBook }
        let selected: ArraySlice<Chapter> = switch scope {
        case .nextChapters(let count): chapters.prefix(count)
        case .wholeBook: chapters[...]
        }
        return selected.map { $0.orderedSentences.map(\.text) }
    }

    /// Characters ElevenLabs would bill for narrating `scope` (cached audio is free).
    static func narrationCharacters(of document: Document, scope: OfflineScope) -> Int {
        chapters(of: document, scope: scope).joined().reduce(0) { $0 + $1.count }
    }

    func start(_ document: Document, scope: OfflineScope, voiceID: String, modelID: String) {
        guard tasks[document.id] == nil else { return }
        let documentID = document.id
        let chapters = Self.chapters(of: document, scope: scope)
        let sentences = chapters.flatMap { $0 }
        let chunks = chapters.flatMap { sentences in NarrationPlanner.chunks(for: sentences).map { Array(sentences[$0.sentenceRange]) } }
        jobs[documentID] = Job(completed: 0, total: sentences.count + chunks.count)

        tasks[documentID] = Task {
            defer {
                tasks[documentID] = nil
                jobs[documentID]?.isFinished = true
            }
            do {
                try await TranslationService.shared.prepareTranslations(for: sentences) { done, total in
                    await MainActor.run { self.jobs[documentID]?.completed = done + (sentences.count - total) }
                }
                for chunk in chunks {
                    try Task.checkCancellation()
                    _ = try await AudioCache.shared.cloudClip(sentences: chunk, voiceID: voiceID, modelID: modelID)
                    jobs[documentID]?.completed += 1
                }
            } catch is CancellationError {
                jobs[documentID] = nil
            } catch {
                jobs[documentID]?.failure = error.localizedDescription
            }
        }
    }

    func cancel(_ document: Document) {
        tasks[document.id]?.cancel()
        tasks[document.id] = nil
        jobs[document.id] = nil
    }
}
