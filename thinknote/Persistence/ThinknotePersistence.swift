import Foundation
import SwiftData

enum ThinknotePersistence {
    static let sharedContainer: ModelContainer = {
        do {
            return try makeContainer()
        } catch {
            do {
                try resetStoreFilesForDevelopment()
                return try makeContainer()
            } catch {
                fatalError("Failed to create SwiftData container: \(error)")
            }
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

    private static func resetStoreFilesForDevelopment() throws {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")

        for url in storeFileURLs() {
            guard fileManager.fileExists(atPath: url.path) else { continue }

            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).backup-\(timestamp)")

            try? fileManager.removeItem(at: backupURL)
            try fileManager.moveItem(at: url, to: backupURL)
        }
    }

    private static func storeFileURLs() -> [URL] {
        let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeURL = applicationSupportURL.appendingPathComponent("ThinknoteStore.store")
        let walURL = applicationSupportURL.appendingPathComponent("ThinknoteStore.store-wal")
        let shmURL = applicationSupportURL.appendingPathComponent("ThinknoteStore.store-shm")
        return [storeURL, walURL, shmURL]
    }
}
