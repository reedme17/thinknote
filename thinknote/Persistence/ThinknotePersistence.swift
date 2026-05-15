import Foundation
import SwiftData

enum ThinknotePersistence {
    static let sharedContainer: ModelContainer = {
        do {
            return try makeContainer()
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }()

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ThinknoteStore",
            schema: Schema([
                NoteRecord.self,
                RevisionRecord.self,
                SourceRecord.self,
                LinkRecord.self,
                ThreadRecord.self,
                MessageRecord.self,
                JobRecord.self,
                TimelineEventRecord.self
            ]),
            isStoredInMemoryOnly: inMemory
        )

        return try ModelContainer(
            for: NoteRecord.self,
            RevisionRecord.self,
            SourceRecord.self,
            LinkRecord.self,
            ThreadRecord.self,
            MessageRecord.self,
            JobRecord.self,
            TimelineEventRecord.self,
            configurations: configuration
        )
    }
}
