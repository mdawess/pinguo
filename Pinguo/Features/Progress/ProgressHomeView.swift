import Charts
import SwiftData
import SwiftUI

struct ProgressHomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WordStateStore.self) private var wordStates
    @Query(sort: \DailyActivity.day) private var activity: [DailyActivity]
    @Query(sort: \ReviewLog.reviewedAt, order: .reverse) private var logs: [ReviewLog]
    @Query private var cards: [Card]
    @State private var selectedDay: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack {
                        Text("Progress").font(.largeTitle30)
                        Spacer()
                        NavigationLink {
                            SettingsView(settings: settings)
                        } label: {
                            Image(systemName: "gearshape").font(.system(size: 19, weight: .light)).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Settings")
                    }
                    .padding(.top, 12)

                    knownWords
                    tiles
                    listening
                    limits
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(Color.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Words known

    private struct KnownPoint: Identifiable {
        let day: Date
        let count: Int
        var id: Date { day }
    }

    /// One point per day for 30 days, carrying the last known total forward over days without activity.
    private var knownSeries: [KnownPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let byDay = Dictionary(activity.map { ($0.day, $0.knownWordCount) }, uniquingKeysWith: max)
        var last = activity.last { $0.day < calendar.date(byAdding: .day, value: -29, to: today)! }?.knownWordCount ?? 0
        return (0..<30).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            if let count = byDay[day], count > 0 { last = count }
            if offset == 0 { last = wordStates.knownWordCount }
            return KnownPoint(day: day, count: last)
        }
    }

    private var knownWords: some View {
        let series = knownSeries
        let gained = (series.last?.count ?? 0) - (series.first?.count ?? 0)
        let selected = selectedDay.flatMap { day in series.first { Calendar.current.isDate($0.day, inSameDayAs: day) } }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Words known").font(.body15).foregroundStyle(Color.inkSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text((selected?.count ?? wordStates.knownWordCount).formatted())
                        .font(.geist(48, .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(selected.map { $0.day.formatted(.dateTime.month().day()) } ?? (gained > 0 ? "+\(gained) in 30 days" : "last 30 days"))
                        .font(.body15)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            if series.allSatisfy({ $0.count == 0 }) {
                Text("Mark words as Known while you read, or seed your level in Settings, to see this grow.")
                    .font(.body15)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                Chart(series) { point in
                    AreaMark(x: .value("Day", point.day, unit: .day), y: .value("Known", point.count))
                        .foregroundStyle(Color.ink.opacity(0.08))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", point.day, unit: .day), y: .value("Known", point.count))
                        .foregroundStyle(Color.ink)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                    if let selected, selected.day == point.day {
                        RuleMark(x: .value("Day", point.day, unit: .day)).foregroundStyle(Color.hairline)
                        PointMark(x: .value("Day", point.day, unit: .day), y: .value("Known", point.count))
                            .symbolSize(80)
                            .foregroundStyle(Color.ink)
                    }
                }
                .chartXSelection(value: $selectedDay)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 10)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.meta12).foregroundStyle(Color.inkSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Color.hairline)
                        AxisValueLabel().font(.meta12).foregroundStyle(Color.inkSecondary)
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("Words known over the last 30 days")
            }
        }
    }

    // MARK: Tiles

    private var streak: Int {
        let calendar = Calendar.current
        var activeDays = Set(logs.map { calendar.startOfDay(for: $0.reviewedAt) })
        activity.filter { $0.secondsListened > 30 || $0.wordsLookedUp > 0 }.forEach { activeDays.insert($0.day) }
        var day = calendar.startOfDay(for: .now)
        if !activeDays.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while activeDays.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private var tiles: some View {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let reviewedToday = logs.prefix { $0.reviewedAt >= startOfDay }.count
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(value: "\(streak)", label: streak == 1 ? "day streak" : "day streak")
            StatTile(value: "\(reviewedToday)", label: "reviewed today")
            StatTile(value: "\(cards.count)", label: "cards in deck")
            StatTile(value: "\(Int((weekSeconds / 60).rounded()))", label: "minutes listened this week")
        }
    }

    // MARK: Listening

    private struct ListeningDay: Identifiable {
        let day: Date
        let minutes: Double
        var id: Date { day }
    }

    private var listeningSeries: [ListeningDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let byDay = Dictionary(activity.map { ($0.day, $0.secondsListened) }, uniquingKeysWith: +)
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return ListeningDay(day: day, minutes: (byDay[day] ?? 0) / 60)
        }
    }

    private var weekSeconds: Double {
        listeningSeries.reduce(0) { $0 + $1.minutes * 60 }
    }

    private var listening: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Minutes listened")
            Chart(listeningSeries) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", day.minutes), width: .ratio(0.55))
                    .foregroundStyle(Calendar.current.isDateInToday(day.day) ? Color.ink : Color.ink.opacity(0.35))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    .annotation(position: .top, spacing: 4) {
                        if day.minutes >= 1 {
                            Text("\(Int(day.minutes.rounded()))").font(.meta12).foregroundStyle(Color.inkSecondary)
                        }
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true).font(.meta12).foregroundStyle(Color.inkSecondary)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 120)
            .accessibilityLabel("Minutes listened each day this week")
        }
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Daily limits").padding(.bottom, 6)
            @Bindable var settings = settings
            Stepper(value: $settings.dailyNewCards, in: 0...200, step: 5) {
                LimitRow(label: "New cards per day", value: settings.dailyNewCards)
            }
            Hairline()
            Stepper(value: $settings.dailyReviews, in: 10...1000, step: 10) {
                LimitRow(label: "Max reviews per day", value: settings.dailyReviews)
            }
        }
    }
}

private struct LimitRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label).font(.body15)
            Spacer()
            Text("\(value)").font(.geist(15, .medium)).monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.geist(28, .semibold)).monospacedDigit().foregroundStyle(Color.ink)
            Text(label).font(.meta13).foregroundStyle(Color.inkSecondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.surface))
    }
}
