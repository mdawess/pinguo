import Foundation
import SwiftData

enum CardKind: String, Codable {
    case word, sentence
}

@Model
final class Card {
    var id: UUID = UUID()
    var kindRaw: String = CardKind.word.rawValue
    var word: String = ""
    var sentenceText: String = ""
    var sentenceTranslation: String?
    var documentID: UUID?
    var documentTitle: String?
    var chapterTitle: String?
    var audioVoiceID: String?
    var createdAt: Date = Date.now

    var stateRaw: Int = CardState.new.rawValue
    var step: Int = 0
    var stability: Double = 0
    var difficulty: Double = 0
    var due: Date = Date.now
    var lastReview: Date?
    var lapses: Int = 0
    var reps: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card) var logs: [ReviewLog]? = []

    init(kind: CardKind, word: String, sentenceText: String) {
        self.kindRaw = kind.rawValue
        self.word = word
        self.sentenceText = sentenceText
    }

    var kind: CardKind { CardKind(rawValue: kindRaw) ?? .word }
    var state: CardState { CardState(rawValue: stateRaw) ?? .new }

    var scheduling: SchedulingState {
        get {
            SchedulingState(
                state: state, step: step, stability: stability, difficulty: difficulty,
                due: due, lastReview: lastReview, lapses: lapses, reps: reps
            )
        }
        set {
            stateRaw = newValue.state.rawValue
            step = newValue.step
            stability = newValue.stability
            difficulty = newValue.difficulty
            due = newValue.due
            lastReview = newValue.lastReview
            lapses = newValue.lapses
            reps = newValue.reps
        }
    }

    var sourceLine: String? {
        guard let documentTitle else { return nil }
        guard let chapterTitle, chapterTitle != documentTitle else { return "From \(documentTitle)" }
        return "From \(documentTitle) · \(chapterTitle)"
    }
}

@Model
final class ReviewLog {
    var id: UUID = UUID()
    var ratingRaw: Int = Rating.good.rawValue
    var reviewedAt: Date = Date.now
    var elapsedDays: Double = 0
    var stateBeforeRaw: Int = CardState.new.rawValue
    var card: Card?

    init(rating: Rating, reviewedAt: Date, elapsedDays: Double, stateBefore: CardState) {
        self.ratingRaw = rating.rawValue
        self.reviewedAt = reviewedAt
        self.elapsedDays = elapsedDays
        self.stateBeforeRaw = stateBefore.rawValue
    }

    var rating: Rating { Rating(rawValue: ratingRaw) ?? .good }
    var stateBefore: CardState { CardState(rawValue: stateBeforeRaw) ?? .new }
}
