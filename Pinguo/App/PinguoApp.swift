import SwiftData
import SwiftUI

@main
struct PinguoApp: App {
    let modelContainer = PinguoStore.makeContainer(inMemory: ProcessInfo.processInfo.arguments.contains("-PinguoInMemoryStore"))

    init() {
        UITabBarItem.appearance().badgeColor = UIColor(named: "Badge")
        ChargingPreparation.registerBackgroundTask(container: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.ink)
        }
        .modelContainer(modelContainer)
    }
}

enum PinguoStore {
    static let schema = Schema([
        Document.self,
        Chapter.self,
        Sentence.self,
        WordState.self,
        AppSettings.self,
        Card.self,
        ReviewLog.self,
        Conversation.self,
        Message.self,
        DailyActivity.self,
    ])

    static let cloudContainer = "iCloud.com.mdawes.pinguo"

    /// Library, word states, cards and logs sync through the private CloudKit database; the audio cache stays
    /// on disk outside the store. Falls back to a local store when CloudKit isn't available.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        let synced = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainer))
        if let container = try? ModelContainer(for: schema, configurations: synced) {
            return container
        }
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        } catch {
            fatalError("Could not open the Pinguo store: \(error)")
        }
    }
}
