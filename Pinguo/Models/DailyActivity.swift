import Foundation
import SwiftData

/// Per-day totals for the Progress tab.
@Model
final class DailyActivity {
    var day: Date = Date.now
    var secondsListened: Double = 0
    var wordsLookedUp: Int = 0
    var knownWordCount: Int = 0

    init(day: Date) {
        self.day = day
    }

    static func today(in context: ModelContext, now: Date = .now) -> DailyActivity {
        let start = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<DailyActivity>(predicate: #Predicate { $0.day == start })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let activity = DailyActivity(day: start)
        context.insert(activity)
        return activity
    }
}
