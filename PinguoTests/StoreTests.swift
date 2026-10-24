import Foundation
import SwiftData
import Testing
@testable import Pinguo

struct StoreTests {
    /// CloudKit rejects unique constraints, non-optional relationships and attributes without defaults.
    @Test func schemaIsCloudKitCompatible() throws {
        let configuration = ModelConfiguration(
            schema: PinguoStore.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .private(PinguoStore.cloudContainer)
        )
        _ = try ModelContainer(for: PinguoStore.schema, configurations: configuration)
    }

    @Test func wordStateStoreMergesDuplicateRowsFromSync() throws {
        let container = PinguoStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let older = WordState(word: "风景", familiarity: .seen)
        older.updatedAt = .distantPast
        older.lookupCount = 3
        let newer = WordState(word: "风景", familiarity: .familiar)
        context.insert(older)
        context.insert(newer)
        let store = WordStateStore(context: context)
        #expect(store.familiarity(of: "风景") == .familiar)
        #expect(try context.fetch(FetchDescriptor<WordState>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<WordState>()).first?.lookupCount == 3)
    }
}
