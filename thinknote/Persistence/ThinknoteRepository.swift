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
    func requestEnrichment(for note: APINote, triggerSource: String) async throws -> APINote
    func requestChatReply(for note: APINote, message: String) async throws -> RemoteChatResult
}

actor NoopThinknoteRemoteService: ThinknoteRemoteServing {
    func upsert(note: APINote) async throws {}
    func requestEnrichment(for note: APINote, triggerSource: String) async throws -> APINote { note }
    func requestChatReply(for note: APINote, message: String) async throws -> RemoteChatResult {
        RemoteChatResult(chat: APIChat(id: UUID().uuidString, noteId: note.id, message: message, reply: "", provider: "noop", createdAt: .now), note: note, thread: nil, assistantMessage: nil)
    }
}

actor ThinknoteBackendRemoteService: ThinknoteRemoteServing {
    private let client: ThinknoteAPIClient

    init(client: ThinknoteAPIClient = ThinknoteAPIClient()) {
        self.client = client
    }

    func upsert(note: APINote) async throws {
        _ = try await client.upsertRemoteNote(id: note.id, title: note.displayHeadline, text: note.text, scheduleGrowth: false)
    }

    func requestEnrichment(for note: APINote, triggerSource: String) async throws -> APINote {
        try await client.enrich(noteID: note.id, triggerSource: triggerSource, wait: true, priority: triggerSource == "manual" ? "user_initiated" : "background")
    }

    func requestChatReply(for note: APINote, message: String) async throws -> RemoteChatResult {
        try await client.chat(noteID: note.id, message: message)
    }
}

final class ThinknoteRepository: @unchecked Sendable {
    static let shared = ThinknoteRepository(localStore: .shared)

    private let localStore: ThinknoteLocalStore
    private let remoteSync: any ThinknoteRemoteSyncing
    private let remoteService: any ThinknoteRemoteServing

    init(
        localStore: ThinknoteLocalStore,
        remoteSync: any ThinknoteRemoteSyncing = NoopThinknoteRemoteSync(),
        remoteService: any ThinknoteRemoteServing = ThinknoteBackendRemoteService()
    ) {
        self.localStore = localStore
        self.remoteSync = remoteSync
        self.remoteService = remoteService
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
        guard let localNote = try await localStore.fetchNote(noteID: noteID) else {
            throw LocalStoreError.noteNotFound(noteID)
        }

        do {
            try await remoteService.upsert(note: localNote)

            if try await localStore.hasPendingFollowUp(noteID: noteID),
               let thread = try await localStore.fetchThread(noteID: noteID),
               let pendingMessage = thread.messages.last(where: { $0.role == "user" })?.text {
                let reply = try await remoteService.requestChatReply(for: localNote, message: pendingMessage)
                let updated = try await localStore.applyRemoteAssistantReply(
                    noteID: noteID,
                    replyText: reply.assistantMessage?.text ?? reply.chat.reply,
                    provider: reply.assistantMessage?.provider ?? reply.chat.provider,
                    sources: reply.assistantMessage?.sources ?? [],
                    createdAt: reply.assistantMessage?.createdAt ?? reply.chat.createdAt
                )
                await remoteSync.enqueue(.threadUpdated(noteID: noteID, threadID: thread.id))
                return updated
            }

            let remoteNote = try await remoteService.requestEnrichment(for: localNote, triggerSource: triggerSource)
            let merged = try await localStore.mergeRemoteNote(noteID: noteID, remoteNote: remoteNote, triggerSource: triggerSource)
            await remoteSync.enqueue(.aiJobUpdated(noteID: noteID, jobType: .enrichNote))
            return merged
        } catch {
            let note = try await localStore.requestImmediateEnrichment(noteID: noteID, triggerSource: triggerSource)
            await remoteSync.enqueue(.aiJobUpdated(noteID: noteID, jobType: .enrichNote))
            return note
        }
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
        let eligibleNoteIDs = try await localStore.eligibleRemoteGrowthNoteIDs(now: now, limit: limit)
        guard !eligibleNoteIDs.isEmpty else {
            return []
        }

        var updatedNotes: [APINote] = []
        do {
            for noteID in eligibleNoteIDs {
                guard let localNote = try await localStore.fetchNote(noteID: noteID) else { continue }
                try await remoteService.upsert(note: localNote)
                let remoteNote = try await remoteService.requestEnrichment(for: localNote, triggerSource: "background")
                let merged = try await localStore.mergeRemoteNote(noteID: noteID, remoteNote: remoteNote, triggerSource: "background")
                updatedNotes.append(merged)
                await remoteSync.enqueue(.aiJobUpdated(noteID: noteID, jobType: .enrichNote))
            }
        } catch {
            return try await localStore.processEligibleJobs(now: now, limit: limit)
        }
        return updatedNotes
    }
}
