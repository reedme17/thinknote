import Foundation
import SwiftData
import Testing
@testable import thinknote

private actor MockRemoteService: ThinknoteRemoteServing {
    func upsert(note: APINote) async throws {}

    func requestEnrichment(for note: APINote, triggerSource: String, followUpGuidance: String?) async throws -> APINote {
        let now = Date()
        let source = APISource(
            id: "source-\(note.id)",
            title: "Test source",
            url: "https://example.com/\(note.id)",
            snippet: "Remote enrichment source"
        )
        let followUpContext = followUpGuidance.map {
            APIFollowUpContext(
                prefix: "A related question here is ",
                highlight: $0,
                suffix: ", and that changes where the next section goes."
            )
        }
        let enrichment = APIEnrichment(
            id: "enrichment-\(note.id)-\(triggerSource)",
            createdAt: now,
            provider: "test-remote",
            expansion: followUpGuidance == nil ? "Expanded thinking for \(note.title)" : "Continued thinking guided by \(followUpGuidance!)",
            relatedIdeas: ["What assumption is doing the work here?"],
            prompts: ["What would make this claim more concrete?"],
            links: [],
            sources: [source],
            followUpContext: followUpContext
        )

        return APINote(
            id: note.id,
            title: note.displayHeadline,
            text: note.text,
            createdAt: note.createdAt,
            updatedAt: now,
            lastViewedAt: note.lastViewedAt,
            lastEnrichedAt: now,
            sortIndex: note.sortIndex,
            status: "enriched",
            enrichments: [enrichment],
            links: [],
            sources: [source],
            prompts: enrichment.prompts,
            timeline: [
                APITimelineEvent(
                    id: "timeline-\(note.id)-\(triggerSource)",
                    type: TimelineEventKind.noteEnriched.rawValue,
                    createdAt: now,
                    summary: "New growth added",
                    provider: enrichment.provider,
                    isNewSinceLastView: true
                )
            ],
            latestChatReply: nil,
            changesSinceLastViewedCount: 1
        )
    }

    func requestChatReply(for note: APINote, message: String) async throws -> RemoteChatResult {
        let now = Date()
        let assistantMessage = APIConversationMessage(
            id: "assistant-\(note.id)",
            role: MessageRole.assistant.rawValue,
            text: "Remote reply to: \(message)",
            provider: "test-remote",
            createdAt: now,
            sources: []
        )

        return RemoteChatResult(
            chat: APIChat(
                id: "chat-\(note.id)",
                noteId: note.id,
                message: message,
                reply: assistantMessage.text,
                provider: assistantMessage.provider,
                createdAt: now
            ),
            note: note,
            thread: nil,
            assistantMessage: assistantMessage
        )
    }
}

private final class MockHeadlineSummarizer: NoteHeadlineSummarizing {
    let headline: String?

    init(headline: String? = nil) {
        self.headline = headline
    }

    func cardHeadline(for text: String) async throws -> String? {
        headline
    }
}

struct thinknoteTests {
    private func makeRepository(
        container: ModelContainer,
        headlineSummarizer: any NoteHeadlineSummarizing = MockHeadlineSummarizer()
    ) -> ThinknoteRepository {
        ThinknoteRepository(
            localStore: ThinknoteLocalStore(container: container),
            remoteSync: NoopThinknoteRemoteSync(),
            remoteService: MockRemoteService(),
            headlineSummarizer: headlineSummarizer
        )
    }

    @Test
    func runtimeConfigurationUsesExplicitEnvironmentOverride() {
        let resolved = ThinknoteRuntimeConfiguration.resolve(
            environmentOverride: "staging",
            baseURLOverride: nil,
            bundleValues: [
                "ThinknoteLocalAPIBaseURL": "http://127.0.0.1:8787",
                "ThinknoteStagingAPIBaseURL": "https://staging.example.com",
                "ThinknoteProductionAPIBaseURL": "https://prod.example.com"
            ],
            isSimulator: true
        )

        #expect(resolved.environment == .staging)
        #expect(resolved.baseURL.absoluteString == "https://staging.example.com")
    }

    @Test
    func runtimeConfigurationLetsExplicitBaseURLWin() {
        let resolved = ThinknoteRuntimeConfiguration.resolve(
            environmentOverride: "production",
            baseURLOverride: "https://custom.example.com",
            bundleValues: [:],
            isSimulator: false
        )

        #expect(resolved.environment == .production)
        #expect(resolved.baseURL.absoluteString == "https://custom.example.com")
    }

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
    func seedNotesUseInstallDateAndAreNotRecreatedOnBootstrap() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let store = ThinknoteLocalStore(container: container)
        let installDate = Date(timeIntervalSince1970: 1_750_000_000)
        let prototypeDate = installDate.addingTimeInterval(-60 * 60 * 24 * 30)
        let seed = APINote(
            id: "seed-test-note",
            title: "Template thought",
            text: "Template thought",
            createdAt: prototypeDate,
            updatedAt: prototypeDate.addingTimeInterval(900),
            lastViewedAt: prototypeDate,
            lastEnrichedAt: nil,
            sortIndex: 0,
            status: "captured",
            enrichments: [],
            links: [],
            sources: [],
            prompts: [],
            timeline: [
                APITimelineEvent(
                    id: "seed-test-note-created",
                    type: TimelineEventKind.noteCreated.rawValue,
                    createdAt: prototypeDate,
                    summary: "Template created"
                )
            ],
            latestChatReply: nil
        )

        try await store.seedIfNeeded(using: [seed], installedAt: installDate)

        let firstBootstrap = try #require(try await store.fetchNote(noteID: seed.id))
        #expect(firstBootstrap.createdAt == installDate)
        #expect(firstBootstrap.timeline.first?.createdAt == installDate)
        #expect(firstBootstrap.updatedAt == prototypeDate.addingTimeInterval(900))
        #expect(firstBootstrap.lastViewedAt == prototypeDate)

        try await store.seedIfNeeded(using: [seed], installedAt: installDate)

        let secondBootstrap = try #require(try await store.fetchNote(noteID: seed.id))
        #expect(secondBootstrap.createdAt == installDate)
        #expect(secondBootstrap.updatedAt == prototypeDate.addingTimeInterval(900))
        #expect(secondBootstrap.lastViewedAt == prototypeDate)

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<NoteRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<RevisionRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TimelineEventRecord>()).count == 1)
    }

    @Test
    func initialCaptureKeepsHeadlineEqualToUserInput() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = makeRepository(container: container)

        let text = "every tool teaches you a worldview"
        let note = try await repository.saveDraft(noteID: nil, text: text)

        #expect(note.title == text)
        #expect(note.displayHeadline == text)
        #expect(note.text == text)
        #expect(note.enrichments.isEmpty)
    }

    @Test
    func longDraftUsesLocalSummaryForCardWithoutReplacingFullText() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = makeRepository(
            container: container,
            headlineSummarizer: MockHeadlineSummarizer(headline: "A short local card summary")
        )

        let text = """
        This is a deliberately long thought about how the home card should stay readable even when the captured note is much longer than the available card surface, while the full detail page should preserve every word the user originally wrote.
        """
        let note = try await repository.saveDraft(noteID: nil, text: text)

        #expect(note.title == "A short local card summary")
        #expect(note.displayHeadline == "A short local card summary")
        #expect(note.text == text)
    }

    @Test
    func deferredEnrichmentRunsOnlyAfterScheduledTime() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = makeRepository(container: container)
        let note = try await repository.saveDraft(noteID: nil, text: "taste = pattern recognition at scale")

        let createdAt = note.createdAt
        let scheduledGrowth = try #require(try await repository.nextDeferredGrowthDate(now: createdAt))
        #expect(scheduledGrowth == createdAt.addingTimeInterval(60 * 60 * 12))

        let notYetDue = createdAt.addingTimeInterval(60 * 60 * 12)
        let dueLater = createdAt.addingTimeInterval(60 * 60 * 30)

        let earlyRun = try await repository.processEligibleJobs(now: notYetDue)
        #expect(earlyRun.isEmpty)

        let beforeDue = try #require(try await repository.loadNote(noteID: note.id))
        #expect(beforeDue.status == "queued")
        #expect(beforeDue.enrichments.isEmpty)

        let processed = try await repository.processEligibleJobs(now: dueLater)
        #expect(processed.count == 1)
        #expect(try await repository.nextDeferredGrowthDate(now: dueLater) == nil)

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
        let repository = makeRepository(container: container)

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
    func remoteGrowthDoesNotReplaceCardHeadline() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let store = ThinknoteLocalStore(container: container)
        let note = try await store.upsertDraft(
            noteID: nil,
            text: "A long captured note that already has a local card summary.",
            displayTitle: "Local card summary"
        )
        let now = Date()
        let enrichment = APIEnrichment(
            id: "remote-enrichment",
            createdAt: now,
            provider: "test-remote",
            expansion: "Remote growth should live below the original note.",
            relatedIdeas: [],
            prompts: [],
            links: [],
            sources: [],
            followUpContext: nil
        )
        let remoteNote = APINote(
            id: note.id,
            title: "Remote AI headline should not win",
            text: note.text,
            createdAt: note.createdAt,
            updatedAt: now,
            lastViewedAt: note.lastViewedAt,
            lastEnrichedAt: now,
            sortIndex: note.sortIndex,
            status: "enriched",
            enrichments: [enrichment],
            links: [],
            sources: [],
            prompts: [],
            timeline: [],
            latestChatReply: nil
        )

        let merged = try await store.mergeRemoteNote(noteID: note.id, remoteNote: remoteNote, triggerSource: "manual")

        #expect(merged.title == "Local card summary")
        #expect(merged.displayHeadline == "Local card summary")
        #expect(merged.text == note.text)
        #expect(merged.enrichments.count == 1)
    }

    @Test
    func markingNoteViewedClearsUnreadAiChanges() async throws {
        let container = try ThinknotePersistence.makeContainer(inMemory: true)
        let repository = makeRepository(container: container)

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
        let repository = makeRepository(container: container)

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
        let repository = makeRepository(container: container)

        let note = try await repository.saveDraft(noteID: nil, text: "every tool teaches you a worldview")

        let waiting = try await repository.sendFollowUp(noteID: note.id, message: "What is the strongest version of this?")
        #expect(waiting.latestChatReply == nil)
        #expect(waiting.prompts.isEmpty)

        let pendingThread = try await repository.fetchConversationThread(noteID: note.id)
        #expect(pendingThread != nil)
        #expect(pendingThread?.messages.count == 1)
        #expect(pendingThread?.messages.last?.role == MessageRole.user.rawValue)

        let updated = try await repository.requestEnrichment(noteID: note.id)
        #expect(updated.latestChatReply == nil)
        #expect(updated.enrichments.first?.followUpContext?.highlight == "What is the strongest version of this?")
        #expect(updated.prompts.isEmpty)

        let thread = try await repository.fetchConversationThread(noteID: note.id)
        #expect(thread != nil)
        #expect(thread?.messages.count == 2)
        #expect(thread?.messages.first?.role == MessageRole.user.rawValue)
        #expect(thread?.messages.last?.role == MessageRole.assistant.rawValue)
    }
}
