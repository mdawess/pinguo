import BackgroundTasks
import Observation
import SwiftData
import UIKit

/// Renders narration and translations for the next chapters of recently read books while the device
/// is charging, so reading later (on a flight, say) plays from the cache instead of using battery.
/// Runs in the app while it's open and plugged in, and as a background processing task that iOS only
/// starts on external power.
@Observable
final class ChargingPreparation {
    static let shared = ChargingPreparation()
    static let taskIdentifier = "com.mdawes.pinguo.prepare"

    private(set) var isPreparing = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var lastFinished: Date? = UserDefaults.standard.object(forKey: "lastPreparedAt") as? Date

    private var task: Task<Void, Never>?

    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    static var isCharging: Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return [.charging, .full].contains(UIDevice.current.batteryState)
    }

    // MARK: Background task

    static func registerBackgroundTask(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGProcessingTask else { return }
                let work = Task {
                    await shared.prepare(in: ModelContext(container))
                    task.setTaskCompleted(success: !Task.isCancelled)
                }
                task.expirationHandler = { work.cancel() }
                scheduleBackgroundTask()
            }
        }
    }

    static func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: In-app

    func startIfCharging(in context: ModelContext) {
        guard Self.isCharging, task == nil else { return }
        task = Task {
            await prepare(in: context)
            task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: Work

    private struct Job {
        let sentences: [String]
        let chunks: [[String]]
        let voiceID: String?
    }

    func prepare(in context: ModelContext) async {
        let settings = AppSettings.current(in: context)
        guard settings.prepareWhileCharging, !isPreparing else { return }
        let jobs = Self.jobs(in: context, settings: settings)
        isPreparing = true
        completed = 0
        total = jobs.reduce(0) { $0 + $1.chunks.count + 1 }
        defer { isPreparing = false }

        for job in jobs {
            try? await TranslationService.shared.prepare(job.sentences)
            completed += 1
            for chunk in job.chunks {
                guard !Task.isCancelled else { return }
                _ = try? await AudioCache.shared.clip(sentences: chunk, voiceID: job.voiceID)
                completed += 1
            }
        }
        guard !Task.isCancelled else { return }
        lastFinished = .now
        UserDefaults.standard.set(lastFinished, forKey: "lastPreparedAt")
    }

    /// The current and following chapters of the three most recently opened books.
    private static func jobs(in context: ModelContext, settings: AppSettings) -> [Job] {
        let documents = ((try? context.fetch(FetchDescriptor<Document>())) ?? [])
            .filter { $0.status == .ready && $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(3)
        return documents.flatMap { document in
            document.orderedChapters
                .filter { $0.index >= document.lastChapterIndex }
                .prefix(settings.chaptersToPrepare)
                .map { chapter in
                    let sentences = chapter.orderedSentences.map(\.text)
                    return Job(
                        sentences: sentences,
                        chunks: NarrationPlanner.chunks(for: sentences).map { Array(sentences[$0.sentenceRange]) },
                        voiceID: settings.voiceID(for: document)
                    )
                }
        }
    }
}
