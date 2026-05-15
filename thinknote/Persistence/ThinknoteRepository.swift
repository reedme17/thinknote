import Foundation

enum PendingRemoteMutation: Sendable {
    case noteUpsert(noteID: String)
    case noteViewed(noteID: String, viewedAt: Date)
    case noteReordered(noteIDs: [String])
    case threadUpdated(noteID: String, threadID: String)
    case aiJobUpdated(noteID: String, jobType: JobType)
}

protocol ThinknoteRemoteSyncing: Sendable {
    func enqueue(_ mutation: PendingRemoteMutation) async
}

actor NoopThinknoteRemoteSync: ThinknoteRemoteSyncing {
    func enqueue(_ mutation: PendingRemoteMutation) async {}
}

final class ThinknoteRepository: @unchecked Sendable {
    static let shared = ThinknoteRepository(localStore: .shared)

    private let localStore: ThinknoteLocalStore
    private let remoteSync: any ThinknoteRemoteSyncing

    init(
        localStore: ThinknoteLocalStore,
        remoteSync: any ThinknoteRemoteSyncing = NoopThinknoteRemoteSync()
    ) {
        self.localStore = localStore
        self.remoteSync = remoteSync
    }

    func bootstrap(seedNotes: [APINote]) async throws -> [APINote] {
        try await localStore.seedIfNeeded(using: seedNotes)
        return try await localStore.fetchNotes()
    }

    func loadNotes() async throws -> [APINote] {
        try await localStore.fetchNotes()
    }

    func loadNote(noteID: String) async throws -> APINote? {
        try await localStore.fetchNote(noteID: noteID)
    }

    func saveDraft(noteID: String?, text: String) async throws -> APINote {
        let note = try await localStore.upsertDraft(noteID: noteID, text: text)
        await remoteSync.enqueue(.noteUpsert(noteID: note.id))
        return note
    }

    func reorderNotes(noteIDs: [String]) async throws -> [APINote] {
        let reordered = try await localStore.reorderNotes(noteIDs: noteIDs)
        await remoteSync.enqueue(.noteReordered(noteIDs: noteIDs))
        return reordered
    }

    func markNoteViewed(noteID: String, viewedAt: Date = .now) async throws -> APINote? {
        let note = try await localStore.markNoteViewed(noteID: noteID, viewedAt: viewedAt)
        await remoteSync.enqueue(.noteViewed(noteID: noteID, viewedAt: viewedAt))
        return note
    }

    func requestEnrichment(noteID: String, triggerSource: String = "manual") async throws -> APINote {
        let note = try await localStore.requestImmediateEnrichment(noteID: noteID, triggerSource: triggerSource)
        await remoteSync.enqueue(.aiJobUpdated(noteID: noteID, jobType: .enrichNote))
        return note
    }

    func sendFollowUp(noteID: String, message: String) async throws -> APINote {
        let note = try await localStore.appendMockChat(noteID: noteID, message: message)
        if let thread = try await localStore.fetchThread(noteID: noteID) {
            await remoteSync.enqueue(.threadUpdated(noteID: noteID, threadID: thread.id))
        }
        return note
    }

    func fetchConversationThread(noteID: String) async throws -> APIConversationThread? {
        try await localStore.fetchThread(noteID: noteID)
    }

    func processEligibleJobs(now: Date = .now, limit: Int = 3) async throws -> [APINote] {
        let updatedNotes = try await localStore.processEligibleJobs(now: now, limit: limit)
        for note in updatedNotes {
            await remoteSync.enqueue(.aiJobUpdated(noteID: note.id, jobType: .enrichNote))
        }
        return updatedNotes
    }
}
