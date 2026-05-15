import Foundation
import SwiftData

actor ThinknoteLocalStore {
    static let shared = ThinknoteLocalStore(container: ThinknotePersistence.sharedContainer)

    private let container: ModelContainer
    private let sortSpacing: Double = 1_024
    private let deferredGrowthDelay: TimeInterval = 60 * 60 * 24

    init(container: ModelContainer) {
        self.container = container
    }

    func seedIfNeeded(using notes: [APINote]) throws {
        let context = ModelContext(container)
        for (index, note) in notes.enumerated() {
            upsertSeed(note, sortIndex: Double(index) * sortSpacing, into: context)
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

    func upsertDraft(noteID: String?, text: String) throws -> APINote {
        let context = ModelContext(container)
        let now = Date()
        let note: NoteRecord

        if let noteID, let existing = try fetchNoteRecord(noteID: noteID, in: context) {
            existing.rawText = text
            existing.title = displayHeadline(from: text)
            existing.updatedAt = now
            existing.status = hasPendingEnrichmentJob(for: existing) ? .queued : .edited

            let revision = RevisionRecord(
                createdAt: now,
                kind: .userEdit,
                summary: "Note updated by user",
                text: text,
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
                title: displayHeadline(from: text),
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
                summary: "Initial note capture",
                text: text,
                note: created
            )
            context.insert(revision)

            appendTimelineEvent(
                type: .noteCreated,
                summary: "Note created",
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

    func markNoteViewed(noteID: String, viewedAt: Date = .now) throws -> APINote? {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            return nil
        }

        note.lastViewedAt = max(note.lastViewedAt ?? .distantPast, viewedAt)
        try context.save()
        return makeAPINote(from: note)
    }

    func requestImmediateEnrichment(noteID: String, triggerSource: String = "manual") throws -> APINote {
        let context = ModelContext(container)
        guard let note = try fetchNoteRecord(noteID: noteID, in: context) else {
            throw LocalStoreError.noteNotFound(noteID)
        }

        if hasPendingUserFollowUp(for: note) {
            try answerPendingFollowUp(for: note, in: context)
            try context.save()
            return makeAPINote(from: note)
        }

        let now = Date()
        let job = activeEnrichmentJob(for: note) ?? scheduleEnrichmentJob(
            for: note,
            priority: .high,
            triggerSource: triggerSource,
            earliestRunAt: now,
            maxRunCount: 1,
            createdAt: now,
            in: context
        )

        if job.runCount == 0 {
            appendTimelineEvent(
                type: .jobQueued,
                summary: "Response requested",
                note: note,
                createdAt: now,
                payload: ["jobId": job.id, "triggerSource": triggerSource],
                in: context
            )
        }

        reschedule(
            job,
            priority: .high,
            triggerSource: triggerSource,
            earliestRunAt: now,
            updatedAt: now
        )

        _ = try processEligibleJobs(in: context, now: now, noteID: noteID, limit: 1)

        try context.save()
        return makeAPINote(from: note)
    }

    func processEligibleJobs(now: Date = .now, limit: Int = 3) throws -> [APINote] {
        let context = ModelContext(container)
        let updatedNotes = try processEligibleJobs(in: context, now: now, noteID: nil, limit: limit)
        if !updatedNotes.isEmpty {
            try context.save()
        }
        return updatedNotes.map { makeAPINote(from: $0) }
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

    private func importSeed(_ note: APINote, sortIndex: Double, into context: ModelContext) {
        let record = NoteRecord(
            id: note.id,
            title: note.title,
            rawText: note.text,
            status: NoteStatus(rawValue: note.status) ?? .captured,
            createdAt: note.createdAt,
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
            createdAt: note.createdAt,
            kind: .userCapture,
            summary: "Initial note capture",
            text: note.text,
            note: record
        )
        context.insert(initialRevision)

        for enrichment in note.enrichments {
            let revision = RevisionRecord(
                id: enrichment.id,
                createdAt: enrichment.createdAt,
                kind: .aiEnrichment,
                summary: "AI interpretation refreshed",
                text: enrichment.expansion,
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
                retrievedAt: note.updatedAt,
                note: record
            )
            context.insert(sourceRecord)
        }

        if note.timeline.isEmpty {
            appendTimelineEvent(
                type: note.enrichments.isEmpty ? .noteCreated : .noteEnriched,
                summary: note.enrichments.isEmpty ? "Note created" : "AI interpretation refreshed",
                note: record,
                createdAt: note.updatedAt,
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
                    createdAt: event.createdAt,
                    in: context
                )
            }
        }
    }

    private func upsertSeed(_ note: APINote, sortIndex: Double, into context: ModelContext) {
        if let existing = try? fetchNoteRecord(noteID: note.id, in: context) {
            context.delete(existing)
        }
        importSeed(note, sortIndex: sortIndex, into: context)
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

    private func processEligibleJobs(
        in context: ModelContext,
        now: Date,
        noteID: String?,
        limit: Int
    ) throws -> [NoteRecord] {
        let jobs = try context.fetch(FetchDescriptor<JobRecord>())
        let eligibleJobs = jobs
            .filter { job in
                guard job.type == .enrichNote else { return false }
                guard [.queued, .retrying].contains(job.status) else { return false }
                guard job.runCount < job.maxRunCount else { return false }
                guard let note = job.note else { return false }
                if let noteID, note.id != noteID { return false }
                return job.scheduledRunAt <= now && job.nextRunAt <= now
            }
            .sorted(by: eligibleJobComparator)

        var updatedNotes: [NoteRecord] = []
        for job in eligibleJobs.prefix(limit) {
            guard let note = job.note else { continue }
            executeMockEnrichment(job: job, note: note, now: now, in: context)
            updatedNotes.append(note)
        }
        return updatedNotes
    }

    private func executeMockEnrichment(
        job: JobRecord,
        note: NoteRecord,
        now: Date,
        in context: ModelContext
    ) {
        job.status = .running
        job.updatedAt = now
        job.startedAt = job.startedAt ?? now
        job.lastAttemptAt = now
        job.runCount += 1

        note.status = .queued
        note.updatedAt = now

        let source = SourceRecord(
            title: "Public article",
            urlString: "https://example.com/idea",
            snippet: "Background research attached to the current AI interpretation.",
            publisher: "example.com",
            query: "product thinking",
            score: 0.72,
            retrievedAt: now,
            note: note,
            sourceJob: job
        )
        context.insert(source)

        let revision = RevisionRecord(
            createdAt: now,
            kind: .aiEnrichment,
            summary: "AI interpretation refreshed",
            text: "This thought can be developed further by turning the fragment into a clearer argument and checking it against outside knowledge.",
            note: note,
            sourceJob: job
        )
        context.insert(revision)

        note.status = .enriched
        note.title = polishedDisplayHeadline(from: note.rawText)
        note.updatedAt = now
        note.lastEnrichedAt = now
        note.promptSuggestions = [
            "What is the strongest version of this idea?",
            "What evidence would make this more believable?"
        ]

        job.status = .completed
        job.updatedAt = now
        job.completedAt = now
        job.outputData = StoredJSONCodec.encode([
            "revisionId": revision.id,
            "sourceId": source.id
        ])

        appendTimelineEvent(
            type: .noteEnriched,
            summary: "AI interpretation refreshed",
            note: note,
            createdAt: now,
            payload: ["revisionId": revision.id, "jobId": job.id],
            in: context
        )

        appendTimelineEvent(
            type: .jobCompleted,
            summary: "Background growth completed",
            note: note,
            createdAt: now,
            payload: ["jobId": job.id],
            in: context
        )
    }

    private func answerPendingFollowUp(for note: NoteRecord, in context: ModelContext) throws {
        let now = Date()
        guard let thread = try fetchThread(for: note.id, in: context) else {
            return
        }

        let orderedMessages = thread.messages.sorted { $0.createdAt < $1.createdAt }
        guard let latestMessage = orderedMessages.last, latestMessage.role == .user else {
            return
        }

        let assistantMessage = MessageRecord(
            role: .assistant,
            text: "A useful next step is to turn that follow-up into a sharper question, then compare it against the note's current interpretation.",
            provider: "local",
            createdAt: now,
            thread: thread
        )
        context.insert(assistantMessage)

        thread.updatedAt = now
        note.latestChatReply = assistantMessage.text
        note.updatedAt = now

        appendTimelineEvent(
            type: .chatUpdated,
            summary: "AI conversation advanced",
            note: note,
            createdAt: now,
            payload: ["threadId": thread.id, "messageId": assistantMessage.id],
            in: context
        )
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
                    provider: revision.sourceJob?.type.rawValue ?? "local",
                    expansion: revision.text,
                    relatedIdeas: [],
                    prompts: note.promptSuggestions,
                    links: links,
                    sources: sources
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
        let normalized = normalizeHeadlineSource(text)
        return normalized.isEmpty ? "Untitled" : normalized
    }

    private func polishedDisplayHeadline(from text: String) -> String {
        let normalized = normalizeHeadlineSource(text)
        guard !normalized.isEmpty else { return "Untitled" }

        let sentenceCased = sentenceCase(normalized)
        return shortenHeadline(sentenceCased, maxLength: 72)
    }

    private func normalizeHeadlineSource(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private func shortenHeadline(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }

        var candidate = ""
        for word in text.split(separator: " ") {
            let next = candidate.isEmpty ? String(word) : candidate + " " + word
            if next.count > maxLength {
                break
            }
            candidate = next
        }

        if !candidate.isEmpty {
            return candidate
        }

        return String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
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
            return "Could not find note \(noteID)."
        }
    }
}
