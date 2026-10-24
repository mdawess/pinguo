import Foundation
import Observation
import SwiftData

/// One familiarity level per word, shared by the Reader, Review and Speak. Keeps an in-memory index of the
/// SwiftData `WordState` rows so rendering a chapter never hits the store per word.
@Observable
final class WordStateStore {
    private let context: ModelContext
    private(set) var familiarityByWord: [String: Familiarity] = [:]
    private var rowsByWord: [String: WordState] = [:]

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        let rows = (try? context.fetch(FetchDescriptor<WordState>())) ?? []
        var rowsByWord: [String: WordState] = [:]
        for row in rows {
            if let existing = rowsByWord[row.word] {
                // CloudKit cannot enforce uniqueness, so merge duplicates from other devices.
                let keep = existing.updatedAt >= row.updatedAt ? existing : row
                let drop = keep === existing ? row : existing
                keep.lookupCount = max(keep.lookupCount, drop.lookupCount)
                keep.firstSeenAt = min(keep.firstSeenAt, drop.firstSeenAt)
                context.delete(drop)
                rowsByWord[row.word] = keep
            } else {
                rowsByWord[row.word] = row
            }
        }
        self.rowsByWord = rowsByWord
        familiarityByWord = rowsByWord.mapValues(\.familiarity)
    }

    func familiarity(of word: String) -> Familiarity {
        familiarityByWord[word] ?? .new
    }

    var knownWordCount: Int {
        familiarityByWord.values.filter { $0 == .known }.count
    }

    func setFamiliarity(_ familiarity: Familiarity, for word: String) {
        row(for: word).familiarity = familiarity
        familiarityByWord[word] = familiarity
        save()
    }

    func recordLookup(of word: String) {
        DailyActivity.today(in: context).wordsLookedUp += 1
        let row = row(for: word)
        row.lookupCount += 1
        row.updatedAt = .now
        familiarityByWord[word] = row.familiarity
        save()
    }

    func markKnown(_ words: some Sequence<String>) {
        for word in words where familiarity(of: word) == .new {
            row(for: word).familiarity = .known
            familiarityByWord[word] = .known
        }
        save()
    }

    /// Unique words still at New ÷ unique words, the Library's difficulty signal.
    func newWordShare(of words: [String]) -> Double {
        guard !words.isEmpty else { return 0 }
        let newCount = words.reduce(0) { $0 + (familiarity(of: $1) == .new ? 1 : 0) }
        return Double(newCount) / Double(words.count)
    }

    private func row(for word: String) -> WordState {
        if let existing = rowsByWord[word] { return existing }
        let row = WordState(word: word)
        context.insert(row)
        rowsByWord[word] = row
        return row
    }

    private func save() {
        DailyActivity.today(in: context).knownWordCount = knownWordCount
        try? context.save()
    }
}
