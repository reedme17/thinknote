//
//  ThinknoteAPI.swift
//  thinknote
//

import Combine
import Foundation

struct APINote: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var text: String
    let createdAt: Date
    var updatedAt: Date
    var lastViewedAt: Date?
    var lastEnrichedAt: Date?
    var sortIndex: Double
    var status: String
    var enrichments: [APIEnrichment]
    var links: [APILink]
    var sources: [APISource]
    var prompts: [String]
    var timeline: [APITimelineEvent]
    var latestChatReply: String?
    var changesSinceLastViewedCount: Int

    var hasChangesSinceLastVisit: Bool {
        changesSinceLastViewedCount > 0
    }

    var displayHeadline: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        id: String,
        title: String,
        text: String,
        createdAt: Date,
        updatedAt: Date,
        lastViewedAt: Date? = nil,
        lastEnrichedAt: Date? = nil,
        sortIndex: Double = 0,
        status: String,
        enrichments: [APIEnrichment],
        links: [APILink],
        sources: [APISource],
        prompts: [String],
        timeline: [APITimelineEvent],
        latestChatReply: String?,
        changesSinceLastViewedCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastViewedAt = lastViewedAt
        self.lastEnrichedAt = lastEnrichedAt
        self.sortIndex = sortIndex
        self.status = status
        self.enrichments = enrichments
        self.links = links
        self.sources = sources
        self.prompts = prompts
        self.timeline = timeline
        self.latestChatReply = latestChatReply
        self.changesSinceLastViewedCount = changesSinceLastViewedCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case text
        case createdAt
        case updatedAt
        case lastViewedAt
        case lastEnrichedAt
        case sortIndex
        case status
        case enrichments
        case links
        case sources
        case prompts
        case timeline
        case latestChatReply
        case changesSinceLastViewedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastViewedAt = try container.decodeIfPresent(Date.self, forKey: .lastViewedAt)
        lastEnrichedAt = try container.decodeIfPresent(Date.self, forKey: .lastEnrichedAt)
        sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? 0
        status = try container.decode(String.self, forKey: .status)
        enrichments = try container.decodeIfPresent([APIEnrichment].self, forKey: .enrichments) ?? []
        links = try container.decodeIfPresent([APILink].self, forKey: .links) ?? []
        sources = try container.decodeIfPresent([APISource].self, forKey: .sources) ?? []
        prompts = try container.decodeIfPresent([String].self, forKey: .prompts) ?? []
        timeline = try container.decodeIfPresent([APITimelineEvent].self, forKey: .timeline) ?? []
        latestChatReply = try container.decodeIfPresent(String.self, forKey: .latestChatReply)
        changesSinceLastViewedCount = try container.decodeIfPresent(Int.self, forKey: .changesSinceLastViewedCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastViewedAt, forKey: .lastViewedAt)
        try container.encodeIfPresent(lastEnrichedAt, forKey: .lastEnrichedAt)
        try container.encode(sortIndex, forKey: .sortIndex)
        try container.encode(status, forKey: .status)
        try container.encode(enrichments, forKey: .enrichments)
        try container.encode(links, forKey: .links)
        try container.encode(sources, forKey: .sources)
        try container.encode(prompts, forKey: .prompts)
        try container.encode(timeline, forKey: .timeline)
        try container.encodeIfPresent(latestChatReply, forKey: .latestChatReply)
        try container.encode(changesSinceLastViewedCount, forKey: .changesSinceLastViewedCount)
    }
}

struct APIFollowUpContext: Codable, Hashable, Sendable {
    let prefix: String
    let highlight: String
    let suffix: String
}

struct APIEnrichment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let createdAt: Date
    let provider: String
    let expansion: String
    let relatedIdeas: [String]
    let prompts: [String]
    let links: [APILink]
    let sources: [APISource]
    let followUpContext: APIFollowUpContext?
}

struct APILink: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let relationship: String

    init(id: String = UUID().uuidString, title: String, relationship: String) {
        self.id = id
        self.title = title
        self.relationship = relationship
    }
}

struct APISource: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let url: String
    let snippet: String

    init(id: String = UUID().uuidString, title: String, url: String, snippet: String) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

struct APITimelineEvent: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let type: String
    let createdAt: Date
    let summary: String
    let provider: String?
    let isNewSinceLastView: Bool

    init(id: String, type: String, createdAt: Date, summary: String, provider: String? = nil, isNewSinceLastView: Bool = false) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.summary = summary
        self.provider = provider
        self.isNewSinceLastView = isNewSinceLastView
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case createdAt
        case summary
        case provider
        case isNewSinceLastView
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        summary = try container.decode(String.self, forKey: .summary)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        isNewSinceLastView = try container.decodeIfPresent(Bool.self, forKey: .isNewSinceLastView) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(summary, forKey: .summary)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encode(isNewSinceLastView, forKey: .isNewSinceLastView)
    }
}

struct APIChat: Identifiable, Codable, Sendable {
    let id: String
    let noteId: String?
    let message: String
    let reply: String
    let provider: String
    let createdAt: Date
}

struct APIConversationThread: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let noteID: String?
    let relatedNoteIDs: [String]
    let createdAt: Date
    let updatedAt: Date
    let messages: [APIConversationMessage]
}

struct APIConversationMessage: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let role: String
    let text: String
    let provider: String
    let createdAt: Date
    let sources: [APISource]
}

enum AppScreen: Hashable {
    case home
    case newNote
    case detail(String)
}

enum ErrorRecoveryAction: Equatable {
    case retryEnrichment(noteID: String)
    case retryDeferredGrowth
}

struct ErrorBannerState: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String?
    let action: ErrorRecoveryAction?
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var notes: [APINote] = []
    @Published var screen: AppScreen = .home
    @Published var activeError: ErrorBannerState?

    @Published var selectedNoteID: String?
    @Published var showTimeline = false

    @Published var draftNoteID: String?
    @Published var draftText = ""
    @Published var lastSavedDraftText = ""
    @Published var isDraftSaving = false
    @Published var didAutosaveDraft = false
    @Published var isDraftResponding = false

    @Published var reorderSourceID: String?
    @Published var addMorphTargetNoteID: String?

    private let repository: ThinknoteRepository
    private var hasBootstrapped = false
    private var isProcessingDeferredGrowth = false
    private var deferredGrowthWakeTask: Task<Void, Never>?

    init(notes: [APINote] = [], repository: ThinknoteRepository? = nil) {
        self.notes = notes
        self.repository = repository ?? .shared
    }

    var currentNote: APINote? {
        guard let selectedNoteID else { return nil }
        return note(for: selectedNoteID)
    }

    var trimmedDraftText: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dismissError() {
        activeError = nil
    }

    func performErrorAction() async {
        guard let action = activeError?.action else { return }
        activeError = nil

        switch action {
        case .retryEnrichment(let noteID):
            await requestResponse(for: noteID)
        case .retryDeferredGrowth:
            await processDeferredGrowthIfNeeded()
        }
    }

    func bootstrap() async {
        do {
            notes = try await repository.bootstrap(seedNotes: Self.demoNotes)
            hasBootstrapped = true
            await processDeferredGrowthIfNeeded()
            scheduleDeferredGrowthWake()
            activeError = nil
        } catch {
            if notes.isEmpty {
                notes = Self.demoNotes
            }
            presentStorageError()
        }
    }

    func loadNotes() async {
        do {
            notes = try await repository.loadNotes()
            scheduleDeferredGrowthWake()
            activeError = nil
        } catch {
            if notes.isEmpty {
                notes = Self.demoNotes
            }
            presentStorageError()
        }

        if case .detail(let noteID) = screen, note(for: noteID) == nil {
            screen = .home
        }
    }

    func refreshForForeground() async {
        guard hasBootstrapped else { return }
        await processDeferredGrowthIfNeeded()
    }

    func openNewNote() {
        draftNoteID = nil
        draftText = ""
        lastSavedDraftText = ""
        didAutosaveDraft = false
        isDraftSaving = false
        isDraftResponding = false
        screen = .newNote
    }

    func discardDraft() {
        draftNoteID = nil
        draftText = ""
        lastSavedDraftText = ""
        didAutosaveDraft = false
        isDraftSaving = false
        isDraftResponding = false
        screen = .home
    }

    func openNote(noteID: String) {
        debugNoteLog("openNote", "before", screen, "noteID:", noteID)
        selectedNoteID = noteID
        showTimeline = false
        reorderSourceID = nil
        screen = .detail(noteID)
        debugNoteLog("openNote", "after", screen, "selectedNoteID:", selectedNoteID ?? "nil")

        Task {
            if let viewedNote = try? await repository.markNoteViewed(noteID: noteID) {
                replace(note: viewedNote)
            }
        }
    }

    func returnHome() {
        let noteID = selectedNoteID
        reorderSourceID = nil
        showTimeline = false
        screen = .home
        if let noteID {
            Task {
                _ = try? await repository.markNoteViewed(noteID: noteID)
                await loadNotes()
            }
        }
    }

    func returnHomeFromDraft() async {
        await autosaveDraftIfNeeded()

        if let draftNoteID {
            selectedNoteID = draftNoteID
        }
        screen = .home
    }

    func addDraftToHome() async {
        await autosaveDraftIfNeeded()
        screen = .home
    }

    func autosaveDraftIfNeeded() async {
        let text = trimmedDraftText
        guard !text.isEmpty else { return }
        guard text != lastSavedDraftText else { return }

        isDraftSaving = true
        defer { isDraftSaving = false }

        do {
            let note: APINote
            if let draftNoteID {
                note = try await saveExistingDraft(noteID: draftNoteID, text: text)
            } else {
                note = try await createDraft(text: text)
            }

            await loadNotes()
            draftNoteID = note.id
            selectedNoteID = note.id
            lastSavedDraftText = text
            didAutosaveDraft = true
            activeError = nil
        } catch {
            presentError(
                title: "Couldn’t save thought",
                message: "Your draft stayed local, but it couldn’t be saved right now."
            )
        }
    }

    func requestResponseForDraft() async {
        await autosaveDraftIfNeeded()

        guard let draftNoteID else { return }

        isDraftResponding = true
        defer { isDraftResponding = false }

        await requestResponse(for: draftNoteID)
        openNote(noteID: draftNoteID)
    }

    @discardableResult
    func requestResponse(for noteID: String) async -> Bool {
        do {
            let updated = try await repository.requestEnrichment(noteID: noteID)
            replace(note: updated)
            activeError = nil
            return true
        } catch {
            presentResponseError(for: noteID, error: error)
            return false
        }
    }

    @discardableResult
    func sendFollowUp(noteID: String, message: String) async -> Bool {
        guard !message.isEmpty else { return false }

        do {
            let updated = try await repository.sendFollowUp(noteID: noteID, message: message)
            replace(note: updated)
            activeError = nil
            return true
        } catch {
            presentError(
                title: "Message not sent",
                message: "Your follow-up didn’t go through. Try again."
            )
            return false
        }
    }

    @discardableResult
    func deleteBaseEnrichment(noteID: String) async -> Bool {
        do {
            let updated = try await repository.deleteBaseEnrichment(noteID: noteID)
            replace(note: updated)
            activeError = nil
            return true
        } catch {
            presentError(title: "Couldn’t remove growth", message: "Try again in a moment.")
            return false
        }
    }

    @discardableResult
    func redoBaseEnrichment(noteID: String) async -> Bool {
        guard await deleteBaseEnrichment(noteID: noteID) else { return false }
        return await requestResponse(for: noteID)
    }

    @discardableResult
    func deleteFollowUpEnrichment(noteID: String, enrichmentID: String, keepUserMessage: Bool = false) async -> Bool {
        do {
            let updated = try await repository.deleteFollowUpEnrichment(noteID: noteID, enrichmentID: enrichmentID, keepUserMessage: keepUserMessage)
            replace(note: updated)
            activeError = nil
            return true
        } catch {
            presentError(title: "Couldn’t remove growth", message: "Try again in a moment.")
            return false
        }
    }

    @discardableResult
    func redoFollowUpEnrichment(noteID: String, enrichmentID: String, question: String) async -> Bool {
        guard await deleteFollowUpEnrichment(noteID: noteID, enrichmentID: enrichmentID, keepUserMessage: false) else { return false }
        guard await sendFollowUp(noteID: noteID, message: question) else { return false }
        return await requestResponse(for: noteID)
    }

    @discardableResult
    func revertFollowUpEnrichment(noteID: String, enrichmentID: String) async -> Bool {
        await deleteFollowUpEnrichment(noteID: noteID, enrichmentID: enrichmentID, keepUserMessage: true)
    }

    @discardableResult
    func deletePendingFollowUp(noteID: String) async -> Bool {
        do {
            let updated = try await repository.deletePendingFollowUp(noteID: noteID)
            replace(note: updated)
            activeError = nil
            return true
        } catch {
            presentError(title: "Couldn’t remove follow-up", message: "Try again in a moment.")
            return false
        }
    }

    func refreshCurrentNote() async {
        guard let selectedNoteID else { return }

        do {
            if let refreshed = try await repository.loadNote(noteID: selectedNoteID) {
                replace(note: refreshed)
            }
            activeError = nil
        } catch {
            presentError(
                title: "Couldn’t refresh thought",
                message: "MOSSLOG couldn’t load the latest version of this thought."
            )
        }
    }

    func toggleTimeline() {
        showTimeline.toggle()
    }

    func startReordering(noteID: String) {
        reorderSourceID = noteID
    }

    func cancelReordering() {
        reorderSourceID = nil
    }

    func moveReorderedNote(before targetNoteID: String) {
        guard let reorderSourceID else { return }
        guard reorderSourceID != targetNoteID else {
            self.reorderSourceID = nil
            return
        }

        guard let sourceIndex = notes.firstIndex(where: { $0.id == reorderSourceID }),
              let targetIndex = notes.firstIndex(where: { $0.id == targetNoteID }) else {
            self.reorderSourceID = nil
            return
        }

        let note = notes.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? max(0, targetIndex - 1) : targetIndex
        notes.insert(note, at: adjustedTarget)
        self.reorderSourceID = nil
        Task {
            _ = try? await repository.reorderNotes(noteIDs: notes.map(\.id))
        }
    }

    func persistManualOrder(_ noteIDs: [String]) async {
        do {
            notes = try await repository.reorderNotes(noteIDs: noteIDs)
            activeError = nil
        } catch {
            presentError(
                title: "Couldn’t reorder thoughts",
                message: "The new order wasn’t saved. Try again."
            )
        }
    }

    @discardableResult
    func deleteNote(noteID: String) async -> Bool {
        do {
            notes = try await repository.deleteNote(noteID: noteID)
            reorderSourceID = nil
            if selectedNoteID == noteID {
                selectedNoteID = nil
                showTimeline = false
                screen = .home
            }
            activeError = nil
            return true
        } catch {
            presentError(
                title: "Couldn’t trash thought",
                message: "That thought is still here. Try again."
            )
            return false
        }
    }

    @discardableResult
    func createNoteFromAssistant(text: String) async -> Bool {
        guard !text.isEmpty else { return false }

        draftText = text
        draftNoteID = nil
        lastSavedDraftText = ""
        await autosaveDraftIfNeeded()

        if let draftNoteID {
            openNote(noteID: draftNoteID)
            return true
        }
        return false
    }

    func note(for noteID: String) -> APINote? {
        notes.first(where: { $0.id == noteID })
    }

    func fetchConversationThread(noteID: String) async -> APIConversationThread? {
        try? await repository.fetchConversationThread(noteID: noteID)
    }

    private func createDraft(text: String) async throws -> APINote {
        try await repository.saveDraft(noteID: nil, text: text)
    }

    private func saveExistingDraft(noteID: String, text: String) async throws -> APINote {
        try await repository.saveDraft(noteID: noteID, text: text)
    }

    private func replace(note: APINote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
        notes.sort { $0.sortIndex < $1.sortIndex }
    }

    private func processDeferredGrowthIfNeeded() async {
        guard !isProcessingDeferredGrowth else { return }

        isProcessingDeferredGrowth = true
        defer { isProcessingDeferredGrowth = false }

        do {
            _ = try await repository.processEligibleJobs()
            await loadNotes()
            scheduleDeferredGrowthWake()
        } catch {
            presentError(
                title: "Background growth paused",
                message: friendlyMessage(for: error, fallback: "MOSSLOG couldn’t reach its AI service in the background."),
                actionTitle: "retry",
                action: .retryDeferredGrowth
            )
        }
    }

    private func scheduleDeferredGrowthWake() {
        deferredGrowthWakeTask?.cancel()
        deferredGrowthWakeTask = Task { [weak self] in
            guard let self else { return }
            guard let wakeDate = try? await self.repository.nextDeferredGrowthDate() else { return }

            let delay = max(wakeDate.timeIntervalSinceNow, 0)
            if delay > 0 {
                let cappedDelay = min(delay, 60 * 60 * 24 * 30)
                let nanoseconds = UInt64(cappedDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }
            await self.processDeferredGrowthIfNeeded()
        }
    }

    private func presentStorageError() {
        presentError(
            title: "Storage unavailable",
            message: "MOSSLOG couldn’t open its local store right now."
        )
    }

    private func presentResponseError(for noteID: String, error: Error) {
        presentError(
            title: friendlyTitle(for: error),
            message: friendlyMessage(for: error, fallback: "MOSSLOG couldn’t get a response right now."),
            actionTitle: "retry",
            action: .retryEnrichment(noteID: noteID)
        )
    }

    private func presentError(
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: ErrorRecoveryAction? = nil
    ) {
        activeError = ErrorBannerState(title: title, message: message, actionTitle: actionTitle, action: action)
    }

    private func friendlyTitle(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("timed out") {
            return "AI took too long"
        }
        if message.contains("offline") || message.contains("internet") || message.contains("network") || message.contains("connect") {
            return "Network issue"
        }
        return "AI unavailable"
    }

    private func friendlyMessage(for error: Error, fallback: String) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("timed out") {
            return "The response didn’t finish in time. Try again."
        }
        if message.contains("offline") || message.contains("internet") || message.contains("network") || message.contains("connect") {
            return "Check your connection and try again."
        }
        return fallback
    }

    static let demoNotes: [APINote] = [
        seededPrototypeNote(
            id: "seed-reading-compression",
            title: "Writing reveals whether reading became understanding.",
            text: "Writing reveals whether reading became understanding.",
            status: "enriched",
            updatedAt: seedDate(hour: 14, minute: 32),
            grownCount: 3,
            lastViewedAt: seedDate(hour: 9, minute: 12),
            growthParagraphs: [
                "Reading lets you borrow compressed thinking. Writing forces you to re-expand it and discover whether the structure still holds once the original scaffolding is gone.",
                "If the thought collapses when you try to restate it plainly, you may have remembered the conclusion without really owning the path that leads to it."
            ],
            prompts: [
                "Does writing make future reading faster because the structure is now internal?",
                "What is the equivalent of this test in conversation?",
                "How would this idea change the way we judge summaries?"
            ],
            sources: [
                APISource(
                    title: "Writing and Speaking",
                    url: "https://paulgraham.com/writing44.html",
                    snippet: "Having good ideas is most of writing well. If you know what you're talking about, you can say it in the plainest words."
                ),
                APISource(
                    title: "The Noncentral Fallacy",
                    url: "https://www.lesswrong.com/posts/2J6iHq8x7P8N6L9XK/the-noncentral-fallacy-the-worst-argument-in-the-world",
                    snippet: "Compression loses information; the question is which information you can afford to lose."
                )
            ]
        ),
        seededPrototypeNote(
            id: "seed-tool-worldview",
            title: "Every tool teaches you how to think.",
            text: "Every tool teaches you how to think.",
            status: "queued",
            updatedAt: seedDate(hour: 13, minute: 18),
            grownCount: 2,
            growthParagraphs: []
        ),
        seededPrototypeNote(
            id: "seed-taste-pattern-recognition",
            title: "Taste is memory for structure.",
            text: "Taste is memory for structure.",
            status: "enriched",
            updatedAt: seedDate(hour: 11, minute: 47),
            grownCount: 1,
            lastViewedAt: seedDate(hour: 8, minute: 50),
            growthParagraphs: [
                "What later feels like instinct is often stored comparison. Attention becomes taste when it remembers why one form held together better than another."
            ]
        ),
        seededPrototypeNote(
            id: "seed-productivity-anxiety",
            title: "Productivity systems often manage anxiety more than output.",
            text: "Productivity systems often manage anxiety more than output.",
            status: "enriched",
            updatedAt: seedDate(hour: 10, minute: 3),
            grownCount: 2,
            growthParagraphs: [
                "Many systems feel effective because they reduce uncertainty, not because they increase meaningful output. The ritual creates relief first, progress second.",
                "That is why a day can feel organized without actually moving the hard thing forward: the system calmed the operator, and the calm got mistaken for progress."
            ]
        )
    ]

    static func previewModel() -> ContentViewModel {
        ContentViewModel(notes: demoNotes)
    }
}

private func seededPrototypeNote(
    id: String,
    title: String,
    text: String,
    status: String,
    updatedAt: Date,
    grownCount: Int,
    lastViewedAt: Date? = nil,
    growthParagraphs: [String],
    prompts: [String] = [],
    sources: [APISource] = []
) -> APINote {
    let timelineType = status == "queued" ? "note_growing" : "note_enriched"
    let createdAt = updatedAt.addingTimeInterval(-900)
    let enrichment = APIEnrichment(
        id: "\(id)-enrichment",
        createdAt: updatedAt,
        provider: "prototype",
        expansion: growthParagraphs.joined(separator: "\n\n"),
        relatedIdeas: [],
        prompts: prompts,
        links: [],
        sources: sources,
        followUpContext: nil
    )

    return APINote(
        id: id,
        title: title,
        text: text,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastViewedAt: lastViewedAt ?? updatedAt,
        lastEnrichedAt: growthParagraphs.isEmpty ? nil : updatedAt,
        sortIndex: 0,
        status: status,
        enrichments: growthParagraphs.isEmpty ? [] : [enrichment],
        links: [],
        sources: sources,
        prompts: prompts,
        timeline: [
            APITimelineEvent(
                id: "\(id)-timeline",
                type: timelineType,
                createdAt: updatedAt,
                summary: "Growth \(grownCount)x",
                isNewSinceLastView: false
            )
        ],
        latestChatReply: nil,
        changesSinceLastViewedCount: 0
    )
}

private func seedDate(hour: Int, minute: Int) -> Date {
    let calendar = Calendar.current
    let now = Date()
    return calendar.date(
        bySettingHour: hour,
        minute: minute,
        second: 0,
        of: now
    ) ?? now
}

enum ThinknoteEnvironment: String, Equatable {
    case local
    case staging
    case production
    case custom
}

struct ThinknoteRuntimeConfiguration: Equatable {
    static let environmentVariableKey = "THINKNOTE_ENVIRONMENT"
    static let baseURLVariableKey = "THINKNOTE_API_BASE_URL"

    private static let defaultLocalBaseURL = URL(string: "http://127.0.0.1:8787")!
    private static let defaultStagingBaseURL = URL(string: "https://thinknote-8zt0.onrender.com")!
    private static let defaultProductionBaseURL = URL(string: "https://thinknote-8zt0.onrender.com")!

    let environment: ThinknoteEnvironment
    let baseURL: URL

    static var current: ThinknoteRuntimeConfiguration {
        let bundleValues = Bundle.main.infoDictionary ?? [:]
        let processValues = ProcessInfo.processInfo.environment
        return resolve(
            environmentOverride: processValues[environmentVariableKey],
            baseURLOverride: processValues[baseURLVariableKey],
            bundleValues: bundleValues,
            isSimulator: isRunningOnSimulator
        )
    }

    static func resolve(
        environmentOverride: String?,
        baseURLOverride: String?,
        bundleValues: [String: Any],
        isSimulator: Bool
    ) -> ThinknoteRuntimeConfiguration {
        if let baseURL = normalizedURL(from: baseURLOverride) {
            let environment = normalizedEnvironment(from: environmentOverride) ?? .custom
            return ThinknoteRuntimeConfiguration(environment: environment, baseURL: baseURL)
        }

        let environment =
            normalizedEnvironment(from: environmentOverride) ??
            normalizedEnvironment(from: bundleValues["ThinknoteDefaultEnvironment"] as? String) ??
            (isSimulator ? .local : .production)

        let baseURL: URL
        switch environment {
        case .local:
            baseURL = normalizedURL(from: bundleValues["ThinknoteLocalAPIBaseURL"] as? String) ?? defaultLocalBaseURL
        case .staging:
            baseURL = normalizedURL(from: bundleValues["ThinknoteStagingAPIBaseURL"] as? String) ?? defaultStagingBaseURL
        case .production:
            baseURL = normalizedURL(from: bundleValues["ThinknoteProductionAPIBaseURL"] as? String) ?? defaultProductionBaseURL
        case .custom:
            baseURL = normalizedURL(from: bundleValues["ThinknoteProductionAPIBaseURL"] as? String) ?? defaultProductionBaseURL
        }

        return ThinknoteRuntimeConfiguration(environment: environment, baseURL: baseURL)
    }

    private static func normalizedEnvironment(from value: String?) -> ThinknoteEnvironment? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "local", "dev", "development":
            return .local
        case "staging", "stage":
            return .staging
        case "production", "prod":
            return .production
        case "custom":
            return .custom
        default:
            return nil
        }
    }

    private static func normalizedURL(from value: String?) -> URL? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    #if targetEnvironment(simulator)
    private static let isRunningOnSimulator = true
    #else
    private static let isRunningOnSimulator = false
    #endif
}

struct ThinknoteAPIClient {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let baseURL: URL

    init(baseURL: URL? = nil) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        self.baseURL = baseURL ?? ThinknoteRuntimeConfiguration.current.baseURL
    }

    func fetchNotes() async throws -> [APINote] {
        let response: NotesResponse = try await request(path: "api/notes", method: "GET", body: Optional<String>.none)
        return response.notes
    }

    func fetchNote(noteID: String) async throws -> APINote {
        let response: NoteResponse = try await request(path: "api/notes/\(noteID)", method: "GET", body: Optional<String>.none)
        return response.note
    }

    func upsertRemoteNote(id: String, title: String, text: String, scheduleGrowth: Bool = false) async throws -> APINote {
        let body = CreateNoteRequest(id: id, title: title, text: text, scheduleGrowth: scheduleGrowth)
        let response: CreateNoteResponse = try await request(path: "api/notes", method: "POST", body: body)
        return response.note
    }

    func updateNote(noteID: String, title: String?, text: String) async throws -> APINote {
        let body = UpdateNoteRequest(title: title, text: text)
        let response: NoteResponse = try await request(path: "api/notes/\(noteID)", method: "PATCH", body: body)
        return response.note
    }

    func enrich(
        noteID: String,
        triggerSource: String = "manual",
        wait: Bool = true,
        priority: String? = nil,
        earliestRunAt: Date? = nil,
        followUpGuidance: String? = nil
    ) async throws -> APINote {
        let body = EnrichNoteRequest(
            focus: "product thinking",
            includeWeb: true,
            wait: wait,
            triggerSource: triggerSource,
            priority: priority,
            earliestRunAt: earliestRunAt,
            followUpGuidance: followUpGuidance
        )
        let response: EnrichResponse = try await request(path: "api/notes/\(noteID)/enrich", method: "POST", body: body)
        return response.note
    }

    func chat(noteID: String, message: String) async throws -> RemoteChatResult {
        let body = ChatRequest(noteID: noteID, message: message)
        let response: ChatResponse = try await request(path: "api/chat", method: "POST", body: body)
        let assistantMessage = response.messages.last { $0.role == "assistant" }
        return RemoteChatResult(chat: response.chat, note: response.note, thread: response.thread, assistantMessage: assistantMessage)
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(ErrorResponse.self, from: data)
            throw APIError.server(apiError?.detail ?? apiError?.error ?? "Request failed with status \(httpResponse.statusCode)")
        }

        return try decoder.decode(Response.self, from: data)
    }
}

private struct NotesResponse: Decodable {
    let notes: [APINote]
}

private struct NoteResponse: Decodable {
    let note: APINote
}

private struct CreateNoteResponse: Decodable {
    let note: APINote
}

private struct EnrichResponse: Decodable {
    let note: APINote
}

private struct ChatResponse: Decodable {
    let chat: APIChat
    let note: APINote?
    let thread: APIConversationThread?
    let messages: [APIConversationMessage]
}

private struct CreateNoteRequest: Encodable {
    let id: String?
    let title: String
    let text: String
    let scheduleGrowth: Bool?

    init(id: String? = nil, title: String, text: String, scheduleGrowth: Bool? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.scheduleGrowth = scheduleGrowth
    }
}

private struct UpdateNoteRequest: Encodable {
    let title: String?
    let text: String
}

private struct EnrichNoteRequest: Encodable {
    let focus: String
    let includeWeb: Bool
    let wait: Bool
    let triggerSource: String
    let priority: String?
    let earliestRunAt: Date?
    let followUpGuidance: String?
}

private struct ChatRequest: Encodable {
    let noteID: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case noteID = "noteId"
        case message
    }
}

private struct ErrorResponse: Decodable {
    let error: String?
    let detail: String?
}

enum APIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .server(let message):
            return message
        }
    }
}

struct RemoteChatResult: Sendable {
    let chat: APIChat
    let note: APINote?
    let thread: APIConversationThread?
    let assistantMessage: APIConversationMessage?
}
