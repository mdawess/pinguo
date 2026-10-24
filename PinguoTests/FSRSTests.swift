import Foundation
import Testing
@testable import Pinguo

struct FSRSTests {
    let fsrs = FSRS()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func newCardIntervalsFollowLearningSteps() {
        let outcomes = fsrs.preview(SchedulingState(), now: now)
        #expect(IntervalFormatter.label(from: now, to: outcomes[.again]!.due) == "1m")
        #expect(IntervalFormatter.label(from: now, to: outcomes[.hard]!.due) == "6m")
        #expect(IntervalFormatter.label(from: now, to: outcomes[.good]!.due) == "10m")
        #expect(outcomes[.easy]!.state == .review)
        #expect(outcomes[.easy]!.due.timeIntervalSince(now) >= 86_400 * 4)
    }

    @Test func graduatesAfterLearningSteps() {
        var card = fsrs.schedule(SchedulingState(), rating: .good, now: now)
        card = fsrs.schedule(card, rating: .good, now: now.addingTimeInterval(600))
        #expect(card.state == .review)
        #expect(card.due.timeIntervalSince(now) > 86_400)
    }

    @Test func reviewIntervalsAreOrderedAndGrow() {
        var card = fsrs.schedule(SchedulingState(), rating: .easy, now: now)
        let reviewDay = card.due
        let outcomes = fsrs.preview(card, now: reviewDay)
        let days = [Rating.hard, .good, .easy].map { outcomes[$0]!.due.timeIntervalSince(reviewDay) / 86_400 }
        #expect(days[0] < days[1] && days[1] < days[2])
        card = outcomes[.good]!
        #expect(card.stability > fsrs.schedule(SchedulingState(), rating: .easy, now: now).stability)
    }

    @Test func lapseMovesToRelearning() {
        let card = fsrs.schedule(SchedulingState(), rating: .easy, now: now)
        let lapsed = fsrs.schedule(card, rating: .again, now: card.due)
        #expect(lapsed.state == .relearning)
        #expect(lapsed.lapses == 1)
        #expect(lapsed.stability < card.stability)
    }

    @Test func retrievabilityIsNinetyPercentAtOneStability() {
        #expect(abs(fsrs.retrievability(elapsedDays: 10, stability: 10) - 0.9) < 0.0001)
        #expect(fsrs.interval(for: 10) == 10)
    }
}
