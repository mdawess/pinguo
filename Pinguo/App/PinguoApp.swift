import SwiftData
import SwiftUI

@main
struct PinguoApp: App {
    let modelContainer = PinguoStore.makeContainer(inMemory: ProcessInfo.processInfo.arguments.contains("-PinguoInMemoryStore"))

    init() {
        UITabBarItem.appearance().badgeColor = UIColor(named: "Badge")
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
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the Pinguo store: \(error)")
        }
    }
}
