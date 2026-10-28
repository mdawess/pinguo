import Foundation
import Observation
import SwiftData

/// Creates cards from lookups and runs FSRS scheduling, respecting the daily new-card and review limits.
@Observable
final class ReviewStore {
    private let context: ModelContext
    private let wordStates: WordStateStore
    private let fsrs = FSRS()
    private(set) var cardWords: Set<String> = []
    private(set) var dueCount = 0
    private var refreshTask: Task<Void, Never>?

    init(context: ModelContext, wordStates: WordStateStore) {
        self.context = context
        self.wordStates = wordStates
        refresh()
    }

    func refresh() {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        cardWords = Set(cards.filter { $0.kind == .word }.map(\.word))
        dueCount = dueQueue().count
    }

    /// Up to `limit` words from the deck that are due soonest or were added most recently, for the tutor to reuse.
    func practiceWords(limit: Int = 20) -> [String] {
        let cards = ((try? context.fetch(FetchDescriptor<Card>())) ?? []).filter { $0.kind == .word }
        let dueSoon = cards.filter { $0.state != .new }.sorted { $0.due < $1.due }
        let recent = cards.sorted { $0.createdAt > $1.createdAt }
        var words: [String] = []
        for card in dueSoon.prefix(limit / 2) + recent where !words.contains(card.word) {
            words.append(card.word)
            if words.count == limit { break }
        }
        return words
    }

    func hasCard(for word: String) -> Bool {
        cardWords.contains(word)
    }

    // MARK: Creating cards

    @discardableResult
    func addWordCard(word: String, sentence: String, document: Document?, chapterTitle: String?, voiceID: String?) -> Card? {
        guard !hasCard(for: word) else { return nil }
        let card = Card(kind: .word, word: word, sentenceText: sentence)
        attach(card, document: document, chapterTitle: chapterTitle, voiceID: voiceID)
        cardWords.insert(word)
        if wordStates.familiarity(of: word) == .new {
            wordStates.setFamiliarity(.seen, for: word)
        }
        return card
    }

    @discardableResult
    func addSentenceCard(sentence: String, document: Document?, chapterTitle: String?, voiceID: String?) -> Card {
        let card = Card(kind: .sentence, word: sentence, sentenceText: sentence)
        attach(card, document: document, chapterTitle: chapterTitle, voiceID: voiceID)
        return card
    }

    private func attach(_ card: Card, document: Document?, chapterTitle: String?, voiceID: String?) {
        card.documentID = document?.id
        card.documentTitle = document?.title
        card.chapterTitle = chapterTitle
        card.audioVoiceID = voiceID
        context.insert(card)
        save()
        let sentence = card.sentenceText
        Task {
            card.sentenceTranslation = try? await TranslationService.shared.translate(sentence)
            save()
        }
    }

    // MARK: Reviewing

    /// Due learning and review cards, plus as many new cards as today's limit allows, in that order.
    func dueQueue(now: Date = .now) -> [Card] {
        let settings = AppSettings.current(in: context)
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.due <= now }, sortBy: [SortDescriptor(\.due)])
        let due = (try? context.fetch(descriptor)) ?? []
        let startOfDay = Calendar.current.startOfDay(for: now)
        let todaysLogs = (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.reviewedAt >= startOfDay }))) ?? []
        let newIntroducedToday = todaysLogs.filter { $0.stateBefore == .new }.count
        let reviewedToday = todaysLogs.filter { $0.stateBefore == .review }.count

        let learning = due.filter { $0.state == .learning || $0.state == .relearning }
        let reviews = due.filter { $0.state == .review }.prefix(max(0, settings.dailyReviews - reviewedToday))
        let fresh = due.filter { $0.state == .new }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(max(0, settings.dailyNewCards - newIntroducedToday))
        return learning + reviews + fresh
    }

    func intervals(for card: Card, now: Date = .now) -> [Rating: String] {
        fsrs.preview(card.scheduling, now: now).mapValues { IntervalFormatter.label(from: now, to: $0.due) }
    }

    func rate(_ card: Card, _ rating: Rating, now: Date = .now) {
        let before = card.scheduling
        let elapsed = before.lastReview.map { now.timeIntervalSince($0) / 86_400 } ?? 0
        card.scheduling = fsrs.schedule(before, rating: rating, now: now)
        let log = ReviewLog(rating: rating, reviewedAt: now, elapsedDays: elapsed, stateBefore: before.state)
        context.insert(log)
        log.card = card
        if card.kind == .word { updateFamiliarity(of: card.word, after: rating) }
        save()
        dueCount = dueQueue(now: now).count
    }

    /// Ratings feed the Reader: Easy moves a word toward Known, forgetting moves it back to learning.
    private func updateFamiliarity(of word: String, after rating: Rating) {
        let current = wordStates.familiarity(of: word)
        switch rating {
        case .easy:
            wordStates.setFamiliarity(Familiarity(rawValue: min(Familiarity.known.rawValue, current.rawValue + 1)) ?? .known, for: word)
        case .good where current == .new:
            wordStates.setFamiliarity(.seen, for: word)
        case .again where current.rawValue > Familiarity.seen.rawValue:
            wordStates.setFamiliarity(Familiarity(rawValue: current.rawValue - 1) ?? .seen, for: word)
        default:
            break
        }
    }

    func delete(_ card: Card) {
        context.delete(card)
        save()
        refresh()
    }

    private func save() {
        try? context.save()
    }
}
