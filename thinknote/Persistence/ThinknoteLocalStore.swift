import Foundation
import SwiftData

actor ThinknoteLocalStore {
    static let shared: ThinknoteLocalStore = {
        let container: ModelContainer
        do {
            container = try ThinknotePersistence.makeContainer()
        } catch {
            fatalError("Failed to create local SwiftData container: \(error)")
        }
        return ThinknoteLocalStore(container: container)
    }()

    private let container: ModelContainer
    private let sortSpacing: Double = 1_024
    private let deferredGrowthDelay: TimeInterval = 60 * 60 * 12

    init(container: ModelContainer) {
        self.container = container
    }

    func seedIfNeeded(using notes: [APINote], installedAt: Date = ThinknoteInstallationDate.current()) throws {
        let context = ModelContext(container)
        for (index, note) in notes.enumerated() {
            upsertSeed(note, installedAt: installedAt, sortIndex: Double(index) * sortSpacing, into: context)
        }

        try context.save()
    }

    func fetchNotes() throws -> [APINote] {
        let context = ModelContext(container)
        let records = try orderedNotes(in: context)
        return records.map { makeAPINote(from: $0) }
    }

    func fetchNote(noteID: String) throws -> APINote? {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            return nil
        }

        try ensureSortIndex(for: note, in: context)
        return makeAPINote(from: note)
    }

    func upsertDraft(noteID: String?, text: String, displayTitle: String? = nil) throws -> APINote {
        let context = ModelContext(container)
        let now = Date()
        let title = displayHeadline(from: displayTitle ?? text)
        let note: NoteRecord

        if let noteID, let existing = try fetchNoteRecord(noteID: noteID, in: context) {
            existing.rawText = text
            existing.title = title
            existing.updatedAt = now
            existing.status = hasPendingEnrichmentJob(for: existing) ? .queued : .edited

            let revision = RevisionRecord(
                createdAt: now,
                kind: .userEdit,
                summary: "Note updated by user",
                text: text,
                provider: "user",
                note: existing
            )
            context.insert(revision)

            appendTimelineEvent(
                type: .noteEdited,
                summary: "Note updated by user",
                note: existing,
                createdAt: now,
                in: context
            )

            if let pendingJob = activeEnrichmentJob(for: existing) {
                reschedule(
                    pendingJob,
                    priority: .low,
                    triggerSource: "user_edit",
                    earliestRunAt: now.addingTimeInterval(deferredGrowthDelay),
                    updatedAt: now
                )
            }

            note = existing
        } else {
            let created = NoteRecord(
                title: title,
                rawText: text,
                status: .queued,
                createdAt: now,
                updatedAt: now,
                lastViewedAt: now,
                sortIndex: nextSortIndex(in: context)
            )
            context.insert(created)

            let revision = RevisionRecord(
                createdAt: now,
                kind: .userCapture,
                summary: "Initial thought capture",
                text: text,
                provider: "user",
                note: created
            )
            context.insert(revision)

            appendTimelineEvent(
                type: .noteCreated,
                summary: "Thought created",
                note: created,
                createdAt: now,
                in: context
            )

            let job = scheduleEnrichmentJob(
                for: created,
                priority: .low,
                triggerSource: "auto_capture",
                earliestRunAt: now.addingTimeInterval(deferredGrowthDelay),
                maxRunCount: 3,
                createdAt: now,
                in: context
            )

            appendTimelineEvent(
                type: .jobQueued,
                summary: "Background growth scheduled",
                note: created,
                createdAt: now,
                payload: ["jobId": job.id, "triggerSource": job.triggerSource],
                in: context
            )

            note = created
        }

        try context.save()
        return makeAPINote(from: note)
    }

    func reorderNotes(noteIDs: [String]) throws -> [APINote] {
        let context = ModelContext(container)
        let allNotes = try context.fetch(FetchDescriptor<NoteRecord>())
        let byID = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })

        var ordered = noteIDs.compactMap { byID[$0] }
        let seen = Set(ordered.map(\.id))
        ordered.append(contentsOf: allNotes.filter { !seen.contains($0.id) }.sorted(by: sortComparator))

        for (index, note) in ordered.enumerated() {
            note.sortIndex = Double(index) * sortSpacing
        }

        try context.save()
        return ordered.map { makeAPINote(from: $0) }
    }

    func deleteNote(noteID: String) throws -> [APINote] {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }

        context.delete(note)
        try context.save()
        return try orderedNotes(in: context).map { makeAPINote(from: $0) }
    }

    func markNoteViewed(noteID: String, viewedAt: Date = .now) throws -> APINote? {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            return nil
        }

        note.lastViewedAt = max(note.lastViewedAt ?? .distantPast, viewedAt)
        try context.save()
        return makeAPINote(from: note)
    }

    func appendMockChat(noteID: String, message: String) throws -> APINote {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }

        let now = Date()
        let thread = try fetchThread(for: noteID, in: context) ?? {
            let created = ThreadRecord(
                title: "Conversation",
                createdAt: now,
                updatedAt: now,
                primaryNote: note,
                relatedNoteIDs: [noteID]
            )
            context.insert(created)
            return created
        }()

        let userMessage = MessageRecord(
            role: .user,
            text: message,
            provider: "user",
            createdAt: now,
            thread: thread
        )
        context.insert(userMessage)

        thread.updatedAt = now
        note.updatedAt = now

        try context.save()
        return makeAPINote(from: note)
    }

    func fetchThread(noteID: String) throws -> APIConversationThread? {
        let context = ModelContext(container)
        guard let thread = try fetchThread(for: noteID, in: context) else {
            return nil
        }

        return makeThread(from: thread)
    }

    func hasPendingFollowUp(noteID: String) throws -> Bool {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }
        return hasPendingUserFollowUp(for: note)
    }

    func eligibleRemoteGrowthNoteIDs(now: Date = .now, limit: Int = 3) throws -> [String] {
        let context = ModelContext(container)
        return try eligibleEnrichmentJobs(in: context, now: now, noteID: nil, limit: limit).compactMap { $0.note?.id }
    }

    func nextEligibleRemoteGrowthDate(now: Date = .now) throws -> Date? {
        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<JobRecord>())
        return jobs
            .filter { job in
                job.type == .enrichNote &&
                    [.queued, .retrying].contains(job.status) &&
                    job.runCount < job.maxRunCount &&
                    job.note != nil
            }
            .map { max($0.scheduledRunAt, $0.nextRunAt) }
            .min()
    }

    func mergeRemoteNote(noteID: String, remoteNote: APINote, triggerSource: String) throws -> APINote {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }

        let now = max(remoteNote.updatedAt, Date())
        let insertedRevisionIDs = mergeRemoteEnrichments(into: note, remoteNote: remoteNote, in: context)
        replaceNoteSources(for: note, remoteSources: remoteNote.sources, retrievedAt: remoteNote.lastEnrichedAt ?? remoteNote.updatedAt, in: context)

        note.updatedAt = max(note.updatedAt, remoteNote.updatedAt)
        note.lastEnrichedAt = remoteNote.lastEnrichedAt ?? note.lastEnrichedAt ?? remoteNote.updatedAt
        if remoteNote.latestChatReply != nil || remoteNote.enrichments.contains(where: { $0.followUpContext != nil }) {
            note.latestChatReply = remoteNote.latestChatReply
        }
        note.promptSuggestions = remoteNote.prompts
        if remoteNote.enrichments.isEmpty {
            note.status = NoteStatus(rawValue: remoteNote.status) ?? note.status
        } else {
            note.status = .enriched
        }

        if !insertedRevisionIDs.isEmpty {
            let summary = remoteNote.timeline.first(where: { $0.type == TimelineEventKind.noteEnriched.rawValue })?.summary ?? "New growth added"
            appendTimelineEvent(
                type: .noteEnriched,
                summary: summary,
                note: note,
                createdAt: now,
                payload: [
                    "triggerSource": triggerSource,
                    "provider": remoteNote.enrichments.first?.provider ?? "remote"
                ],
                in: context
            )
        }

        if !insertedRevisionIDs.isEmpty {
            completeActiveEnrichmentJobs(for: note, completedAt: now, triggerSource: triggerSource, in: context)
        }
        try context.save()
        return makeAPINote(from: note)
    }

    func applyRemoteAssistantReply(
        noteID: String,
        replyText: String,
        provider: String,
        sources: [APISource],
        createdAt: Date = .now
    ) throws -> APINote {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }
        guard let thread = try fetchThread(for: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }

        let orderedMessages = thread.messages.sorted { $0.createdAt < $1.createdAt }
        if let latestMessage = orderedMessages.last,
           latestMessage.role == .assistant,
           latestMessage.text == replyText {
            return makeAPINote(from: note)
        }

        let assistantMessage = MessageRecord(
            role: .assistant,
            text: replyText,
            provider: provider,
            createdAt: createdAt,
            thread: thread
        )
        context.insert(assistantMessage)

        for source in sources {
            let sourceRecord = SourceRecord(
                id: source.id,
                title: source.title,
                urlString: source.url,
                snippet: source.snippet,
                retrievedAt: createdAt,
                message: assistantMessage
            )
            context.insert(sourceRecord)
        }

        thread.updatedAt = createdAt
        note.latestChatReply = replyText
        note.updatedAt = max(note.updatedAt, createdAt)

        appendTimelineEvent(
            type: .chatUpdated,
            summary: "AI conversation advanced",
            note: note,
            createdAt: createdAt,
            payload: ["threadId": thread.id, "provider": provider],
            in: context
        )

        completeActiveEnrichmentJobs(for: note, completedAt: createdAt, triggerSource: "manual", in: context)
        try context.save()
        return makeAPINote(from: note)
    }

    func resolvePendingFollowUpWithEnrichment(
        noteID: String,
        replyText: String,
        provider: String,
        sources: [APISource],
        createdAt: Date = .now
    ) throws -> APINote {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }
        guard let thread = try fetchThread(for: noteID, in: context) else {
            return makeAPINote(from: note)
        }

        let orderedMessages = thread.messages.sorted { $0.createdAt < $1.createdAt }
        guard orderedMessages.last?.role == .user else {
            return makeAPINote(from: note)
        }

        let assistantMessage = MessageRecord(
            role: .assistant,
            text: replyText,
            provider: provider,
            createdAt: createdAt,
            thread: thread
        )
        context.insert(assistantMessage)

        for source in sources {
            let sourceRecord = SourceRecord(
                id: source.id,
                title: source.title,
                urlString: source.url,
                snippet: source.snippet,
                retrievedAt: createdAt,
                message: assistantMessage
            )
            context.insert(sourceRecord)
        }

        thread.updatedAt = createdAt
        note.updatedAt = max(note.updatedAt, createdAt)
        note.latestChatReply = nil
        try context.save()
        return makeAPINote(from: note)
    }

    func deleteBaseEnrichment(noteID: String) throws -> APINote {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }
        let baseRevisions = note.revisions.filter { $0.kind == .aiEnrichment && $0.followUpContext == nil }
        for revision in baseRevisions {
            context.delete(revision)
        }
        for source in note.sources {
            context.delete(source)
        }
        let stillHasFollowUp = note.revisions.contains { $0.kind == .aiEnrichment && $0.followUpContext != nil && !baseRevisions.contains($0) }
        note.status = stillHasFollowUp ? .enriched : .edited
        note.lastEnrichedAt = stillHasFollowUp ? note.lastEnrichedAt : nil
        note.promptSuggestions = []
        note.updatedAt = .now
        try context.save()
        return makeAPINote(from: note)
    }

    func deleteFollowUpEnrichment(noteID: String, enrichmentID: String, keepUserMessage: Bool) throws -> APINote {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }
        let target = note.revisions.first { $0.id == enrichmentID }
        let enrichmentCreatedAt = target?.createdAt
        if let target {
            context.delete(target)
        }
        if let thread = try fetchThread(for: noteID, in: context), let enrichmentCreatedAt {
            let ordered = thread.messages.sorted { $0.createdAt < $1.createdAt }
            if let assistantMsg = ordered
                .filter({ $0.role == .assistant })
                .min(by: { abs($0.createdAt.timeIntervalSince(enrichmentCreatedAt)) < abs($1.createdAt.timeIntervalSince(enrichmentCreatedAt)) }) {
                context.delete(assistantMsg)
            }
            if !keepUserMessage,
               let userMsg = ordered
                   .filter({ $0.role == .user && $0.createdAt <= enrichmentCreatedAt })
                   .last {
                context.delete(userMsg)
            }
            thread.updatedAt = .now
        }
        let remaining = note.revisions
            .filter { $0.kind == .aiEnrichment && $0.id != enrichmentID }
        let hasAny = !remaining.isEmpty
        if !hasAny {
            note.status = .edited
            note.lastEnrichedAt = nil
        }
        note.latestChatReply = nil
        note.promptSuggestions = []
        for source in note.sources {
            context.delete(source)
        }
        note.updatedAt = .now
        try context.save()
        return makeAPINote(from: note)
    }

    func deletePendingFollowUpMessage(noteID: String) throws -> APINote {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }
        if let thread = try fetchThread(for: noteID, in: context) {
            let ordered = thread.messages.sorted { $0.createdAt < $1.createdAt }
            if let last = ordered.last, last.role == .user {
                context.delete(last)
                thread.updatedAt = .now
            }
        }
        note.updatedAt = .now
        try context.save()
        return makeAPINote(from: note)
    }

    private func importSeed(_ note: APINote, installedAt: Date, sortIndex: Double, into context: ModelContext) {
        let record = NoteRecord(
            id: note.id,
            title: note.title,
            rawText: note.text,
            status: NoteStatus(rawValue: note.status) ?? .captured,
            createdAt: installedAt,
            updatedAt: note.updatedAt,
            lastViewedAt: note.lastViewedAt,
            lastEnrichedAt: note.enrichments.isEmpty ? nil : note.updatedAt,
            latestChatReply: note.latestChatReply,
            sortIndex: sortIndex,
            promptSuggestions: note.prompts
        )
        context.insert(record)

        let initialRevision = RevisionRecord(
            id: "\(note.id)-seed-user",
            createdAt: installedAt,
            kind: .userCapture,
            summary: "Initial thought capture",
            text: note.text,
            provider: "user",
            note: record
        )
        context.insert(initialRevision)

        for enrichment in note.enrichments {
            let revision = RevisionRecord(
                id: enrichment.id,
                createdAt: installedAt,
                kind: .aiEnrichment,
                summary: "AI interpretation refreshed",
                text: enrichment.expansion,
                provider: enrichment.provider,
                followUpContext: enrichment.followUpContext,
                note: record
            )
            context.insert(revision)
        }

        for source in note.sources {
            let sourceRecord = SourceRecord(
                id: source.id,
                title: source.title,
                urlString: source.url,
                snippet: source.snippet,
                retrievedAt: installedAt,
                note: record
            )
            context.insert(sourceRecord)
        }

        if note.timeline.isEmpty {
            appendTimelineEvent(
                type: note.enrichments.isEmpty ? .noteCreated : .noteEnriched,
                summary: note.enrichments.isEmpty ? "Note created" : "AI interpretation refreshed",
                note: record,
                createdAt: installedAt,
                in: context
            )
        } else {
            for event in note.timeline {
                let mappedType = TimelineEventKind(rawValue: event.type) ?? .noteCreated
                appendTimelineEvent(
                    id: event.id,
                    type: mappedType,
                    summary: event.summary,
                    note: record,
                    createdAt: installedAt,
                    in: context
                )
            }
        }
    }

    private func upsertSeed(_ note: APINote, installedAt: Date, sortIndex: Double, into context: ModelContext) {
        if let existing = try? fetchNoteRecord(noteID: note.id, in: context) {
            normalizeExistingSeed(existing, installedAt: installedAt, sortIndex: sortIndex)
            return
        }
        importSeed(note, installedAt: installedAt, sortIndex: sortIndex, into: context)
    }

    private func normalizeExistingSeed(_ note: NoteRecord, installedAt: Date, sortIndex: Double) {
        let seedCreatedAt = installedAt
        note.createdAt = seedCreatedAt
        note.sortIndex = note.sortIndex ?? sortIndex

        for revision in note.revisions where revision.kind == .userCapture {
            revision.createdAt = seedCreatedAt
        }

        for event in note.timelineEvents where event.type == .noteCreated {
            event.createdAt = seedCreatedAt
        }
    }

    private func orderedNotes(in context: ModelContext) throws -> [NoteRecord] {
        let fetched = try context.fetch(FetchDescriptor<NoteRecord>())
        if ensureSortIndexes(for: fetched, in: context) {
            try context.save()
        }
        return fetched.sorted(by: sortComparator)
    }

    @discardableResult
    private func ensureSortIndexes(for notes: [NoteRecord], in context: ModelContext) -> Bool {
        let missing = notes.contains { $0.sortIndex == nil }
        guard missing else { return false }

        let sorted = notes.sorted {
            switch ($0.sortIndex, $1.sortIndex) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if $0.createdAt == $1.createdAt {
                    return $0.id < $1.id
                }
                return $0.createdAt < $1.createdAt
            }
        }

        for (index, note) in sorted.enumerated() where note.sortIndex == nil {
            note.sortIndex = Double(index) * sortSpacing
        }
        return true
    }

    private func ensureSortIndex(for note: NoteRecord, in context: ModelContext) throws {
        guard note.sortIndex == nil else { return }
        let allNotes = try context.fetch(FetchDescriptor<NoteRecord>())
        if ensureSortIndexes(for: allNotes, in: context) {
            try context.save()
        }
    }

    private func nextSortIndex(in context: ModelContext) -> Double {
        let notes = (try? context.fetch(FetchDescriptor<NoteRecord>())) ?? []
        let maxIndex = notes.compactMap(\.sortIndex).max() ?? -sortSpacing
        return maxIndex + sortSpacing
    }

    private func fetchNoteRecord(noteID: String, in context: ModelContext) throws -> NoteRecord? {
        let descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate<NoteRecord> { record in
                record.id == noteID
            }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchThread(for noteID: String, in context: ModelContext) throws -> ThreadRecord? {
        let descriptor = FetchDescriptor<ThreadRecord>()
        return try context.fetch(descriptor).first { thread in
            thread.primaryNote?.id == noteID || thread.relatedNoteIDs.contains(noteID)
        }
    }

    private func hasPendingUserFollowUp(for note: NoteRecord) -> Bool {
        guard let thread = note.threads.sorted(by: { $0.updatedAt > $1.updatedAt }).first else {
            return false
        }
        guard let latestMessage = thread.messages.sorted(by: { $0.createdAt < $1.createdAt }).last else {
            return false
        }
        return latestMessage.role == .user
    }

    private func activeEnrichmentJob(for note: NoteRecord) -> JobRecord? {
        note.jobs.first { job in
            job.type == .enrichNote && [.queued, .retrying, .running].contains(job.status)
        }
    }

    private func hasPendingEnrichmentJob(for note: NoteRecord) -> Bool {
        activeEnrichmentJob(for: note) != nil
    }

    private func scheduleEnrichmentJob(
        for note: NoteRecord,
        priority: JobPriority,
        triggerSource: String,
        earliestRunAt: Date,
        maxRunCount: Int,
        createdAt: Date,
        in context: ModelContext
    ) -> JobRecord {
        let job = JobRecord(
            type: .enrichNote,
            status: .queued,
            priority: priority,
            triggerSource: triggerSource,
            payloadData: StoredJSONCodec.encode(["noteId": note.id]),
            dedupeKey: "enrich:\(note.id)",
            retryCount: 0,
            maxRetries: 3,
            runCount: 0,
            maxRunCount: maxRunCount,
            createdAt: createdAt,
            updatedAt: createdAt,
            earliestRunAt: earliestRunAt,
            nextRunAt: earliestRunAt,
            note: note
        )
        context.insert(job)
        return job
    }

    private func reschedule(
        _ job: JobRecord,
        priority: JobPriority,
        triggerSource: String,
        earliestRunAt: Date,
        updatedAt: Date
    ) {
        job.status = .queued
        job.priority = priority
        job.triggerSource = triggerSource
        job.updatedAt = updatedAt
        job.earliestRunAt = earliestRunAt
        job.nextRunAt = earliestRunAt
        job.lastError = nil
        if job.startedAt == nil {
            job.completedAt = nil
        }
    }

    private func eligibleEnrichmentJobs(
        in context: ModelContext,
        now: Date,
        noteID: String?,
        limit: Int
    ) throws -> [JobRecord] {
        let jobs = try context.fetch(FetchDescriptor<JobRecord>())
        return jobs
            .filter { job in
                guard job.type == .enrichNote else { return false }
                guard [.queued, .retrying].contains(job.status) else { return false }
                guard job.runCount < job.maxRunCount else { return false }
                guard let note = job.note else { return false }
                if let noteID, note.id != noteID { return false }
                return job.scheduledRunAt <= now && job.nextRunAt <= now
            }
            .sorted(by: eligibleJobComparator)
            .prefix(limit)
            .map { $0 }
    }

    @discardableResult
    private func mergeRemoteEnrichments(into note: NoteRecord, remoteNote: APINote, in context: ModelContext) -> [String] {
        let existingByID = Dictionary(
            uniqueKeysWithValues: note.revisions
                .filter { $0.kind == .aiEnrichment }
                .map { ($0.id, $0) }
        )

        var insertedIDs: [String] = []
        for enrichment in remoteNote.enrichments.sorted(by: { $0.createdAt > $1.createdAt }) {
            if let existing = existingByID[enrichment.id] {
                existing.createdAt = enrichment.createdAt
                existing.text = enrichment.expansion
                existing.provider = enrichment.provider
                existing.followUpContext = enrichment.followUpContext
                continue
            }
            let revision = RevisionRecord(
                id: enrichment.id,
                createdAt: enrichment.createdAt,
                kind: .aiEnrichment,
                summary: "AI interpretation refreshed",
                text: enrichment.expansion,
                provider: enrichment.provider,
                followUpContext: enrichment.followUpContext,
                note: note
            )
            context.insert(revision)
            insertedIDs.append(revision.id)
        }
        return insertedIDs
    }

    private func replaceNoteSources(
        for note: NoteRecord,
        remoteSources: [APISource],
        retrievedAt: Date,
        in context: ModelContext
    ) {
        for source in note.sources {
            context.delete(source)
        }

        for source in remoteSources {
            let sourceRecord = SourceRecord(
                id: source.id,
                title: source.title,
                urlString: source.url,
                snippet: source.snippet,
                retrievedAt: retrievedAt,
                note: note
            )
            context.insert(sourceRecord)
        }
    }

    private func completeActiveEnrichmentJobs(
        for note: NoteRecord,
        completedAt: Date,
        triggerSource: String,
        in context: ModelContext
    ) {
        var completedAny = false
        for job in note.jobs where job.type == .enrichNote && [.queued, .retrying, .running].contains(job.status) {
            job.status = .completed
            job.updatedAt = completedAt
            job.completedAt = completedAt
            job.lastAttemptAt = completedAt
            if job.runCount == 0 {
                job.runCount = 1
            }
            job.outputData = StoredJSONCodec.encode([
                "triggerSource": triggerSource,
                "completedAt": ISO8601DateFormatter().string(from: completedAt)
            ])
            completedAny = true
        }

        if completedAny {
            appendTimelineEvent(
                type: .jobCompleted,
                summary: "Background growth completed",
                note: note,
                createdAt: completedAt,
                in: context
            )
        }
    }

    private func eligibleJobComparator(_ lhs: JobRecord, _ rhs: JobRecord) -> Bool {
        if lhs.priority != rhs.priority {
            return priorityRank(lhs.priority) > priorityRank(rhs.priority)
        }
        if lhs.scheduledRunAt != rhs.scheduledRunAt {
            return lhs.scheduledRunAt < rhs.scheduledRunAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }

    private func priorityRank(_ priority: JobPriority) -> Int {
        switch priority {
        case .low:
            return 0
        case .normal:
            return 1
        case .high:
            return 2
        }
    }

    private func makeAPINote(from note: NoteRecord) -> APINote {
        let sources = note.sources
            .sorted { $0.retrievedAt > $1.retrievedAt }
            .map { source in
                APISource(
                    id: source.id,
                    title: source.title,
                    url: source.urlString,
                    snippet: source.snippet
                )
            }

        let links = note.outgoingLinks
            .sorted { $0.createdAt > $1.createdAt }
            .map { link in
                APILink(
                    id: link.id,
                    title: link.toNote?.title ?? link.title,
                    relationship: link.relationship.rawValue
                )
            }

        let enrichments = note.revisions
            .filter { $0.kind == .aiEnrichment }
            .sorted { $0.createdAt > $1.createdAt }
            .map { revision in
                APIEnrichment(
                    id: revision.id,
                    createdAt: revision.createdAt,
                    provider: revision.provider,
                    expansion: revision.text,
                    relatedIdeas: [],
                    prompts: note.promptSuggestions,
                    links: links,
                    sources: sources,
                    followUpContext: revision.followUpContext
                )
            }

        let timeline = makeTimeline(from: note)
        let unreadCount = timeline.filter(\.isNewSinceLastView).count

        return APINote(
            id: note.id,
            title: note.title,
            text: note.rawText,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            lastViewedAt: note.lastViewedAt,
            lastEnrichedAt: note.lastEnrichedAt,
            sortIndex: note.sortIndex ?? 0,
            status: note.status.rawValue,
            enrichments: enrichments,
            links: links,
            sources: sources,
            prompts: note.promptSuggestions,
            timeline: timeline,
            latestChatReply: note.latestChatReply,
            changesSinceLastViewedCount: unreadCount
        )
    }

    private func makeTimeline(from note: NoteRecord) -> [APITimelineEvent] {
        let explicitEvents = note.timelineEvents.sorted { $0.createdAt > $1.createdAt }
        if !explicitEvents.isEmpty {
            return explicitEvents.map { record in
                APITimelineEvent(
                    id: record.id,
                    type: record.type.rawValue,
                    createdAt: record.createdAt,
                    summary: record.summary,
                    provider: timelineProvider(from: record),
                    isNewSinceLastView: isEventUnread(type: record.type, createdAt: record.createdAt, lastViewedAt: note.lastViewedAt)
                )
            }
        }

        var derived: [APITimelineEvent] = []
        for revision in note.revisions {
            let eventType: TimelineEventKind
            switch revision.kind {
            case .userCapture:
                eventType = .noteCreated
            case .userEdit:
                eventType = .noteEdited
            case .aiEnrichment:
                eventType = .noteEnriched
            }

            derived.append(
                APITimelineEvent(
                    id: revision.id,
                    type: eventType.rawValue,
                    createdAt: revision.createdAt,
                    summary: revision.summary,
                    isNewSinceLastView: isEventUnread(type: eventType, createdAt: revision.createdAt, lastViewedAt: note.lastViewedAt)
                )
            )
        }

        let assistantMessages = note.threads
            .flatMap(\.messages)
            .filter { $0.role == .assistant }

        for message in assistantMessages {
            derived.append(
                APITimelineEvent(
                    id: message.id,
                    type: TimelineEventKind.chatUpdated.rawValue,
                    createdAt: message.createdAt,
                    summary: "AI conversation advanced",
                    isNewSinceLastView: isEventUnread(type: .chatUpdated, createdAt: message.createdAt, lastViewedAt: note.lastViewedAt)
                )
            )
        }

        return derived.sorted { $0.createdAt > $1.createdAt }
    }

    private func makeThread(from thread: ThreadRecord) -> APIConversationThread {
        let messages = thread.messages
            .sorted { $0.createdAt < $1.createdAt }
            .map { message in
                APIConversationMessage(
                    id: message.id,
                    role: message.role.rawValue,
                    text: message.text,
                    provider: message.provider,
                    createdAt: message.createdAt,
                    sources: message.sources.sorted { $0.retrievedAt > $1.retrievedAt }.map { source in
                        APISource(
                            id: source.id,
                            title: source.title,
                            url: source.urlString,
                            snippet: source.snippet
                        )
                    }
                )
            }

        return APIConversationThread(
            id: thread.id,
            title: thread.title,
            noteID: thread.primaryNote?.id,
            relatedNoteIDs: thread.relatedNoteIDs,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt,
            messages: messages
        )
    }

    private func appendTimelineEvent(
        id: String = UUID().uuidString,
        type: TimelineEventKind,
        summary: String,
        note: NoteRecord,
        createdAt: Date,
        payload: [String: String]? = nil,
        in context: ModelContext
    ) {
        let event = TimelineEventRecord(
            id: id,
            type: type,
            createdAt: createdAt,
            summary: summary,
            payloadData: StoredJSONCodec.encode(payload),
            note: note
        )
        context.insert(event)
    }

    private func timelineProvider(from record: TimelineEventRecord) -> String? {
        guard let payload = StoredJSONCodec.decode([String: String].self, from: record.payloadData) else {
            return nil
        }

        let provider = payload["provider"]?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        return provider.isEmpty ? nil : provider
    }

    private func isEventUnread(type: TimelineEventKind, createdAt: Date, lastViewedAt: Date?) -> Bool {
        if let lastViewedAt {
            return createdAt > lastViewedAt
        }

        switch type {
        case .noteCreated:
            return false
        case .noteEdited, .noteEnriched, .chatUpdated, .jobQueued, .jobRetried, .jobCompleted, .jobFailed:
            return true
        }
    }

    private func displayHeadline(from text: String) -> String {
        let normalized = NoteCardHeadlinePolicy.normalizedHeadlineSource(text)
        return normalized.isEmpty ? "Untitled" : normalized
    }

    private func sortComparator(_ lhs: NoteRecord, _ rhs: NoteRecord) -> Bool {
        let left = lhs.sortIndex ?? .greatestFiniteMagnitude
        let right = rhs.sortIndex ?? .greatestFiniteMagnitude
        if left == right {
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
        return left < right
    }
}

enum LocalStoreError: LocalizedError {
    case noteNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noteNotFound(let noteID):
            return "Could not find thought \(noteID)."
        }
    }
}

enum ThinknoteInstallationDate {
    private static let defaultsKey = "thinknote.installationDate"

    static func current(defaults: UserDefaults = .standard, now: Date = .now) -> Date {
        if let stored = defaults.object(forKey: defaultsKey) as? Date {
            return stored
        }

        defaults.set(now, forKey: defaultsKey)
        return now
    }
}
