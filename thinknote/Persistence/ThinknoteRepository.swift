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

protocol ThinknoteRemoteServing: Sendable {
    func upsert(note: APINote) async throws
    func requestEnrichment(for note: APINote, triggerSource: String, followUpGuidance: String?) async throws -> APINote
    func requestChatReply(for note: APINote, message: String) async throws -> RemoteChatResult
}

actor NoopThinknoteRemoteService: ThinknoteRemoteServing {
    func upsert(note: APINote) async throws {}
    func requestEnrichment(for note: APINote, triggerSource: String, followUpGuidance: String?) async throws -> APINote { note }
    func requestChatReply(for note: APINote, message: String) async throws -> RemoteChatResult {
        RemoteChatResult(chat: APIChat(id: UUID().uuidString, noteId: note.id, message: message, reply: "", provider: "noop", createdAt: .now), note: note, thread: nil, assistantMessage: nil)
    }
}

actor ThinknoteBackendRemoteService: ThinknoteRemoteServing {
    private let client: ThinknoteAPIClient

    init(client: ThinknoteAPIClient? = nil) {
        self.client = client ?? ThinknoteAPIClient()
    }

    func upsert(note: APINote) async throws {
        _ = try await client.upsertRemoteNote(id: note.id, title: note.displayHeadline, text: note.text, scheduleGrowth: false)
    }

    func requestEnrichment(for note: APINote, triggerSource: String, followUpGuidance: String?) async throws -> APINote {
        try await client.enrich(
            noteID: note.id,
            triggerSource: triggerSource,
            wait: true,
            priority: triggerSource == "manual" ? "user_initiated" : "background",
            followUpGuidance: followUpGuidance
        )
    }

    func requestChatReply(for note: APINote, message: String) async throws -> RemoteChatResult {
        try await client.chat(noteID: note.id, message: message)
    }
}

enum ThinknoteRepositoryError: LocalizedError {
    case missingFollowUpContinuation

    var errorDescription: String? {
        switch self {
        case .missingFollowUpContinuation:
            return "AI growth finished, but it did not include the follow-up continuation."
        }
    }
}

final class ThinknoteRepository: @unchecked Sendable {
    static let shared = ThinknoteRepository(localStore: .shared)

    private let localStore: ThinknoteLocalStore
    private let remoteSync: any ThinknoteRemoteSyncing
    private let remoteService: any ThinknoteRemoteServing
    private let headlineSummarizer: any NoteHeadlineSummarizing

    init(
        localStore: ThinknoteLocalStore,
        remoteSync: any ThinknoteRemoteSyncing = NoopThinknoteRemoteSync(),
        remoteService: any ThinknoteRemoteServing = ThinknoteBackendRemoteService(),
        headlineSummarizer: any NoteHeadlineSummarizing = LocalFoundationModelHeadlineSummarizer()
    ) {
        self.localStore = localStore
        self.remoteSync = remoteSync
        self.remoteService = remoteService
        self.headlineSummarizer = headlineSummarizer
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
        let displayTitle = try await headlineSummarizer.cardHeadline(for: text)
        let note = try await localStore.upsertDraft(noteID: noteID, text: text, displayTitle: displayTitle)
        await remoteSync.enqueue(.noteUpsert(noteID: note.id))
        return note
    }

    func reorderNotes(noteIDs: [String]) async throws -> [APINote] {
        let reordered = try await localStore.reorderNotes(noteIDs: noteIDs)
        await remoteSync.enqueue(.noteReordered(noteIDs: noteIDs))
        return reordered
    }

    func deleteNote(noteID: String) async throws -> [APINote] {
        try await localStore.deleteNote(noteID: noteID)
    }

    func markNoteViewed(noteID: String, viewedAt: Date = .now) async throws -> APINote? {
        let note = try await localStore.markNoteViewed(noteID: noteID, viewedAt: viewedAt)
        await remoteSync.enqueue(.noteViewed(noteID: noteID, viewedAt: viewedAt))
        return note
    }

    func requestEnrichment(noteID: String, triggerSource: String = "manual") async throws -> APINote {
        guard let localNote = try await localStore.fetchNote(noteID: noteID) else {
            throw LocalStoreError.noteNotFound(noteID)
        }

        try await remoteService.upsert(note: localNote)

        if try await localStore.hasPendingFollowUp(noteID: noteID),
           let thread = try await localStore.fetchThread(noteID: noteID),
           let pendingMessage = thread.messages.last(where: { $0.role == "user" })?.text {
            let remoteNote = try await remoteService.requestEnrichment(
                for: localNote,
                triggerSource: triggerSource,
                followUpGuidance: pendingMessage
            )
            let remoteFollowUp = remoteNote.enrichments
                .filter { $0.followUpContext != nil }
                .sorted { $0.createdAt > $1.createdAt }
                .first
            guard let remoteFollowUp else {
                throw ThinknoteRepositoryError.missingFollowUpContinuation
            }

            _ = try await localStore.mergeRemoteNote(noteID: noteID, remoteNote: remoteNote, triggerSource: triggerSource)
            let updated = try await localStore.resolvePendingFollowUpWithEnrichment(
                noteID: noteID,
                replyText: remoteFollowUp.expansion,
                provider: remoteFollowUp.provider,
                sources: remoteFollowUp.sources,
                createdAt: remoteFollowUp.createdAt
            )
            await remoteSync.enqueue(.aiJobUpdated(noteID: noteID, jobType: .enrichNote))
            await remoteSync.enqueue(.threadUpdated(noteID: noteID, threadID: thread.id))
            return updated
        }

        let remoteNote = try await remoteService.requestEnrichment(for: localNote, triggerSource: triggerSource, followUpGuidance: nil)
        let merged = try await localStore.mergeRemoteNote(noteID: noteID, remoteNote: remoteNote, triggerSource: triggerSource)
        await remoteSync.enqueue(.aiJobUpdated(noteID: noteID, jobType: .enrichNote))
        return merged
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

    func nextDeferredGrowthDate(now: Date = .now) async throws -> Date? {
        try await localStore.nextEligibleRemoteGrowthDate(now: now)
    }

    func processEligibleJobs(now: Date = .now, limit: Int = 3) async throws -> [APINote] {
        let eligibleNoteIDs = try await localStore.eligibleRemoteGrowthNoteIDs(now: now, limit: limit)
        guard !eligibleNoteIDs.isEmpty else {
            return []
        }

        var updatedNotes: [APINote] = []
        for noteID in eligibleNoteIDs {
            guard let localNote = try await localStore.fetchNote(noteID: noteID) else { continue }
            try await remoteService.upsert(note: localNote)
            let remoteNote = try await remoteService.requestEnrichment(for: localNote, triggerSource: "background", followUpGuidance: nil)
            let merged = try await localStore.mergeRemoteNote(noteID: noteID, remoteNote: remoteNote, triggerSource: "background")
            await remoteSync.enqueue(.aiJobUpdated(noteID: noteID, jobType: .enrichNote))
            updatedNotes.append(merged)
        }
        return updatedNotes
    }
}
