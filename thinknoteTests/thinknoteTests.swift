import Foundation
import SwiftData
import Testing
@testable import thinknote

struct thinknoteTests {

    @Test
    func draftRoundTripPersistsRevisionTimelineAndViewState() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let store = ThinknoteLocalStore(container: container)

        let saved = try await store.upsertDraft(noteID: nil, text: "reading is compression, writing is decompression")

        #expect(saved.status == "queued")
        #expect(saved.title == "reading is compression, writing is decompression")
        #expect(saved.lastViewedAt != nil)
        #expect(saved.sortIndex == 0)
        #expect(saved.timeline.contains(where: { $0.type == TimelineEventKind.noteCreated.rawValue }))
        #expect(saved.timeline.contains(where: { $0.type == TimelineEventKind.jobQueued.rawValue }))

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<NoteRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<RevisionRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TimelineEventRecord>()).count == 2)

        let jobs = try context.fetch(FetchDescriptor<JobRecord>())
        #expect(jobs.count == 1)
        #expect(jobs.first?.status == .queued)
        #expect(jobs.first?.priority == .low)
        #expect(jobs.first?.scheduledRunAt != nil)
    }

    @Test
    func initialCaptureKeepsHeadlineEqualToUserInput() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = ThinknoteRepository(
            localStore: ThinknoteLocalStore(container: container),
            remoteSync: NoopThinknoteRemoteSync()
        )

        let text = "every tool teaches you a worldview"
        let note = try await repository.saveDraft(noteID: nil, text: text)

        #expect(note.title == text)
        #expect(note.displayHeadline == text)
        #expect(note.enrichments.isEmpty)
    }

    @Test
    func deferredEnrichmentRunsOnlyAfterScheduledTime() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = ThinknoteRepository(
            localStore: ThinknoteLocalStore(container: container),
            remoteSync: NoopThinknoteRemoteSync()
        )
        let note = try await repository.saveDraft(noteID: nil, text: "taste = pattern recognition at scale")

        let createdAt = note.createdAt
        let notYetDue = createdAt.addingTimeInterval(60 * 60 * 12)
        let dueLater = createdAt.addingTimeInterval(60 * 60 * 30)

        let earlyRun = try await repository.processEligibleJobs(now: notYetDue)
        #expect(earlyRun.isEmpty)

        let beforeDue = try #require(try await repository.loadNote(noteID: note.id))
        #expect(beforeDue.status == "queued")
        #expect(beforeDue.enrichments.isEmpty)

        let processed = try await repository.processEligibleJobs(now: dueLater)
        #expect(processed.count == 1)

        let enriched = try #require(try await repository.loadNote(noteID: note.id))
        #expect(enriched.status == "enriched")
        #expect(enriched.enrichments.count == 1)
        #expect(enriched.sources.count == 1)
        #expect(enriched.timeline.contains(where: { $0.type == TimelineEventKind.noteEnriched.rawValue }))
        #expect(enriched.timeline.contains(where: { $0.type == TimelineEventKind.jobCompleted.rawValue }))

        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<JobRecord>())
        #expect(jobs.count == 1)
        #expect(jobs.first?.status == .completed)
        #expect(jobs.first?.runCount == 1)
        #expect(jobs.first?.lastAttemptAt == dueLater)
        #expect(try context.fetch(FetchDescriptor<SourceRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<RevisionRecord>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<TimelineEventRecord>()).count == 4)
    }

    @Test
    func manualRequestPromotesDeferredJobAndRunsImmediately() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = ThinknoteRepository(
            localStore: ThinknoteLocalStore(container: container),
            remoteSync: NoopThinknoteRemoteSync()
        )

        let note = try await repository.saveDraft(noteID: nil, text: "every product needs a memory layer")
        let enriched = try await repository.requestEnrichment(noteID: note.id)

        #expect(enriched.status == "enriched")
        #expect(enriched.enrichments.count == 1)
        #expect(enriched.displayHeadline == enriched.title)
        #expect(!enriched.displayHeadline.isEmpty)
        #expect(enriched.displayHeadline.count <= 72)

        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<JobRecord>())
        #expect(jobs.count == 1)
        #expect(jobs.first?.status == .completed)
        #expect(jobs.first?.priority == .high)
        #expect(jobs.first?.triggerSource == "manual")
    }

    @Test
    func markingNoteViewedClearsUnreadAiChanges() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = ThinknoteRepository(
            localStore: ThinknoteLocalStore(container: container),
            remoteSync: NoopThinknoteRemoteSync()
        )

        let note = try await repository.saveDraft(noteID: nil, text: "a note can age into a better question")
        _ = try await repository.markNoteViewed(noteID: note.id, viewedAt: note.createdAt)
        let enriched = try await repository.requestEnrichment(noteID: note.id)

        #expect(enriched.hasChangesSinceLastVisit)
        #expect(enriched.timeline.contains(where: {
            $0.isNewSinceLastView && $0.type == TimelineEventKind.noteEnriched.rawValue
        }))

        let viewed = try #require(try await repository.markNoteViewed(noteID: note.id, viewedAt: enriched.updatedAt))
        #expect(!viewed.hasChangesSinceLastVisit)
        #expect(viewed.changesSinceLastViewedCount == 0)
    }

    @Test
    func reorderPersistsSortIndexAndChangedSinceLastVisitUsesTimeline() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = ThinknoteRepository(
            localStore: ThinknoteLocalStore(container: container),
            remoteSync: NoopThinknoteRemoteSync()
        )

        let first = try await repository.saveDraft(noteID: nil, text: "first fragment")
        let second = try await repository.saveDraft(noteID: nil, text: "second fragment")

        let reordered = try await repository.reorderNotes(noteIDs: [second.id, first.id])
        #expect(reordered.map(\.id) == [second.id, first.id])
        #expect(reordered[0].sortIndex < reordered[1].sortIndex)

        _ = try await repository.markNoteViewed(noteID: second.id, viewedAt: Date())
        let enriched = try await repository.requestEnrichment(noteID: second.id)
        #expect(enriched.hasChangesSinceLastVisit)
        #expect(enriched.changesSinceLastViewedCount >= 1)
    }

    @Test
    func followUpWaitsForExplicitResponseBeforeAssistantReplies() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = ThinknoteRepository(
            localStore: ThinknoteLocalStore(container: container),
            remoteSync: NoopThinknoteRemoteSync()
        )

        let note = try await repository.saveDraft(noteID: nil, text: "every tool teaches you a worldview")

        let waiting = try await repository.sendFollowUp(noteID: note.id, message: "What is the strongest version of this?")
        #expect(waiting.latestChatReply == nil)
        #expect(waiting.prompts.isEmpty)

        let pendingThread = try await repository.fetchConversationThread(noteID: note.id)
        #expect(pendingThread != nil)
        #expect(pendingThread?.messages.count == 1)
        #expect(pendingThread?.messages.last?.role == MessageRole.user.rawValue)

        let updated = try await repository.requestEnrichment(noteID: note.id)
        #expect(updated.latestChatReply != nil)
        #expect(updated.prompts.isEmpty)

        let thread = try await repository.fetchConversationThread(noteID: note.id)
        #expect(thread != nil)
        #expect(thread?.messages.count == 2)
        #expect(thread?.messages.first?.role == MessageRole.user.rawValue)
        #expect(thread?.messages.last?.role == MessageRole.assistant.rawValue)
    }
}
