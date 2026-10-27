import Foundation

nonisolated enum Rating: Int, CaseIterable, Codable, Sendable {
    case again = 1, hard, good, easy

    var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

nonisolated enum CardState: Int, Codable, Sendable {
    case new = 0, learning, review, relearning
}

nonisolated struct SchedulingState: Equatable, Sendable {
    var state: CardState = .new
    var step = 0
    var stability: Double = 0
    var difficulty: Double = 0
    var due: Date = .now
    var lastReview: Date?
    var lapses = 0
    var reps = 0
}

/// FSRS-5 scheduler (open-spaced-repetition), with Anki-style learning and relearning steps.
nonisolated struct FSRS: Sendable {
    var weights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
    ]
    var desiredRetention = 0.9
    var learningSteps: [TimeInterval] = [60, 600]
    var relearningSteps: [TimeInterval] = [600]
    var maximumInterval = 36_500

    private let decay = -0.5
    private var factor: Double { pow(0.9, 1 / decay) - 1 }

    func schedule(_ card: SchedulingState, rating: Rating, now: Date = .now) -> SchedulingState {
        var next = card
        next.reps += 1
        next.lastReview = now
        let elapsedDays = card.lastReview.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? 0

        if card.state == .new {
            next.stability = initialStability(rating)
            next.difficulty = initialDifficulty(rating)
        } else {
            let retrievability = self.retrievability(elapsedDays: elapsedDays, stability: card.stability)
            next.difficulty = nextDifficulty(card.difficulty, rating: rating)
            if elapsedDays < 1 {
                next.stability = shortTermStability(card.stability, rating: rating)
            } else if rating == .again {
                next.stability = forgetStability(card.difficulty, card.stability, retrievability)
            } else {
                next.stability = recallStability(card.difficulty, card.stability, retrievability, rating: rating)
            }
        }

        switch card.state {
        case .new, .learning:
            applySteps(learningSteps, to: &next, rating: rating, now: now, from: card)
        case .relearning:
            applySteps(relearningSteps, to: &next, rating: rating, now: now, from: card)
        case .review:
            if rating == .again {
                next.lapses += 1
                if relearningSteps.isEmpty {
                    next.due = now.addingTimeInterval(Double(interval(for: next.stability)) * 86_400)
                } else {
                    next.state = .relearning
                    next.step = 0
                    next.due = now.addingTimeInterval(relearningSteps[0])
                }
            } else {
                next.state = .review
                next.due = now.addingTimeInterval(Double(reviewInterval(for: rating, card: card, next: next, elapsedDays: elapsedDays)) * 86_400)
            }
        }
        return next
    }

    /// All four outcomes, for showing the next interval under each rating button.
    func preview(_ card: SchedulingState, now: Date = .now) -> [Rating: SchedulingState] {
        Dictionary(uniqueKeysWithValues: Rating.allCases.map { ($0, schedule(card, rating: $0, now: now)) })
    }

    func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + factor * elapsedDays / stability, decay)
    }

    func interval(for stability: Double) -> Int {
        let days = stability / factor * (pow(desiredRetention, 1 / decay) - 1)
        return min(maximumInterval, max(1, Int(days.rounded())))
    }

    private func applySteps(_ steps: [TimeInterval], to next: inout SchedulingState, rating: Rating, now: Date, from card: SchedulingState) {
        let currentStep = card.state == .new ? 0 : card.step
        let learningState: CardState = card.state == .relearning ? .relearning : .learning

        func graduate(_ days: Int) {
            next.state = .review
            next.step = 0
            next.due = now.addingTimeInterval(Double(days) * 86_400)
        }

        guard !steps.isEmpty else {
            graduate(interval(for: next.stability))
            return
        }
        switch rating {
        case .again:
            next.state = learningState
            next.step = 0
            next.due = now.addingTimeInterval(steps[0])
        case .hard:
            next.state = learningState
            next.step = currentStep
            let delay = currentStep == 0 && steps.count > 1 ? (steps[0] + steps[1]) / 2 : steps[min(currentStep, steps.count - 1)]
            next.due = now.addingTimeInterval(delay)
        case .good:
            if currentStep + 1 < steps.count {
                next.state = learningState
                next.step = currentStep + 1
                next.due = now.addingTimeInterval(steps[currentStep + 1])
            } else {
                graduate(interval(for: next.stability))
            }
        case .easy:
            let goodStability = card.state == .new ? initialStability(.good) : next.stability
            graduate(max(interval(for: next.stability), interval(for: goodStability) + 1))
        }
    }

    private func reviewInterval(for rating: Rating, card: SchedulingState, next: SchedulingState, elapsedDays: Double) -> Int {
        let retrievability = self.retrievability(elapsedDays: elapsedDays, stability: card.stability)
        let stabilities = Dictionary(uniqueKeysWithValues: [Rating.hard, .good, .easy].map {
            ($0, recallStability(card.difficulty, card.stability, retrievability, rating: $0))
        })
        var hard = interval(for: stabilities[.hard]!)
        var good = interval(for: stabilities[.good]!)
        hard = min(hard, good)
        good = max(good, hard + 1)
        let easy = max(interval(for: stabilities[.easy]!), good + 1)
        switch rating {
        case .hard: return hard
        case .good: return good
        case .easy: return easy
        case .again: return 1
        }
    }

    private func initialStability(_ rating: Rating) -> Double {
        max(weights[rating.rawValue - 1], 0.1)
    }

    private func initialDifficulty(_ rating: Rating) -> Double {
        clampDifficulty(weights[4] - exp(weights[5] * Double(rating.rawValue - 1)) + 1)
    }

    private func nextDifficulty(_ difficulty: Double, rating: Rating) -> Double {
        let delta = -weights[6] * Double(rating.rawValue - 3)
        let damped = difficulty + delta * (10 - difficulty) / 9
        let reverted = weights[7] * initialDifficulty(.easy) + (1 - weights[7]) * damped
        return clampDifficulty(reverted)
    }

    private func recallStability(_ difficulty: Double, _ stability: Double, _ retrievability: Double, rating: Rating) -> Double {
        let hardPenalty = rating == .hard ? weights[15] : 1
        let easyBonus = rating == .easy ? weights[16] : 1
        return stability * (exp(weights[8]) * (11 - difficulty) * pow(stability, -weights[9])
            * (exp(weights[10] * (1 - retrievability)) - 1) * hardPenalty * easyBonus + 1)
    }

    private func forgetStability(_ difficulty: Double, _ stability: Double, _ retrievability: Double) -> Double {
        let forgotten = weights[11] * pow(difficulty, -weights[12]) * (pow(stability + 1, weights[13]) - 1)
            * exp(weights[14] * (1 - retrievability))
        return min(forgotten, stability)
    }

    private func shortTermStability(_ stability: Double, rating: Rating) -> Double {
        stability * exp(weights[17] * (Double(rating.rawValue) - 3 + weights[18]))
    }

    private func clampDifficulty(_ value: Double) -> Double {
        min(10, max(1, value))
    }
}

nonisolated enum IntervalFormatter {
    static func label(from now: Date, to due: Date) -> String {
        let seconds = max(0, due.timeIntervalSince(now))
        switch seconds {
        case ..<3_600: return "\(max(1, Int((seconds / 60).rounded())))m"
        case ..<86_400: return "\(Int((seconds / 3_600).rounded()))h"
        case ..<(86_400 * 30): return "\(Int((seconds / 86_400).rounded()))d"
        case ..<(86_400 * 365): return "\(Int((seconds / (86_400 * 30)).rounded()))mo"
        default: return (seconds / (86_400 * 365)).formatted(.number.precision(.fractionLength(1))) + "y"
        }
    }
}
