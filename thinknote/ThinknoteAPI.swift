//
//  ThinknoteAPI.swift
//  thinknote
//

import Combine
import Foundation

struct APINote: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var text: String
    let createdAt: Date
    var updatedAt: Date
    var status: String
    var enrichments: [APIEnrichment]
    var links: [APILink]
    var sources: [APISource]
    var prompts: [String]
    var timeline: [APITimelineEvent]
    var latestChatReply: String?
}

struct APIEnrichment: Identifiable, Codable, Hashable {
    let id: String
    let createdAt: Date
    let provider: String
    let expansion: String
    let relatedIdeas: [String]
    let prompts: [String]
    let links: [APILink]
    let sources: [APISource]
}

struct APILink: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let relationship: String

    init(id: String = UUID().uuidString, title: String, relationship: String) {
        self.id = id
        self.title = title
        self.relationship = relationship
    }
}

struct APISource: Identifiable, Codable, Hashable {
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

struct APITimelineEvent: Identifiable, Codable, Hashable {
    let id: String
    let type: String
    let createdAt: Date
    let summary: String
}

struct APIChat: Identifiable, Codable {
    let id: String
    let noteId: String?
    let message: String
    let reply: String
    let provider: String
    let createdAt: Date
}

enum AppScreen: Hashable {
    case home
    case newNote
    case detail(String)
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var notes: [APINote] = []
    @Published var screen: AppScreen = .home
    @Published var errorMessage: String?
    @Published var showAssistant = false

    @Published var selectedNoteID: String?
    @Published var showTimeline = false
    @Published var followUpDraft = ""
    @Published var assistantDraft = ""

    @Published var draftNoteID: String?
    @Published var draftText = ""
    @Published var lastSavedDraftText = ""
    @Published var isDraftSaving = false
    @Published var didAutosaveDraft = false
    @Published var isDraftResponding = false

    @Published var isEnriching = false
    @Published var isSendingFollowUp = false
    @Published var reorderSourceID: String?

    private let client = ThinknoteAPIClient()
    private var isUsingLocalFallback = false

    var currentNote: APINote? {
        guard let selectedNoteID else { return nil }
        return note(for: selectedNoteID)
    }

    var trimmedDraftText: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func bootstrap() async {
        await loadNotes()
    }

    func loadNotes() async {
        do {
            let loaded = try await client.fetchNotes()
            notes = loaded.isEmpty ? Self.demoNotes : loaded
            isUsingLocalFallback = false
            errorMessage = nil
        } catch {
            if notes.isEmpty {
                notes = Self.demoNotes
            }
            isUsingLocalFallback = true
            errorMessage = "Backend unavailable. Running in local MVP mode."
        }

        if case .detail(let noteID) = screen, note(for: noteID) == nil {
            screen = .home
        }
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
        selectedNoteID = noteID
        followUpDraft = ""
        showTimeline = false
        reorderSourceID = nil
        screen = .detail(noteID)
    }

    func returnHome() {
        reorderSourceID = nil
        showTimeline = false
        followUpDraft = ""
        screen = .home
    }

    func returnHomeFromDraft() async {
        await autosaveDraftIfNeeded()

        if let draftNoteID {
            selectedNoteID = draftNoteID
        }
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

            replace(note: note)
            draftNoteID = note.id
            selectedNoteID = note.id
            lastSavedDraftText = text
            didAutosaveDraft = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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

    func requestResponse(for noteID: String) async {
        guard !isEnriching else { return }

        isEnriching = true
        defer { isEnriching = false }

        do {
            let updated: APINote
            if isUsingLocalFallback {
                updated = enrichLocalNote(noteID: noteID)
            } else {
                updated = try await client.enrich(noteID: noteID)
            }

            replace(note: updated)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendFollowUp() async {
        guard let selectedNoteID else { return }

        let message = followUpDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        isSendingFollowUp = true
        defer { isSendingFollowUp = false }

        do {
            let updated: APINote
            if isUsingLocalFallback {
                updated = chatLocalNote(noteID: selectedNoteID, message: message)
            } else {
                let chat = try await client.chat(noteID: selectedNoteID, message: message)
                guard var note = note(for: selectedNoteID) else { return }
                note.latestChatReply = chat.reply
                note.timeline.insert(
                    APITimelineEvent(
                        id: UUID().uuidString,
                        type: "chat_updated",
                        createdAt: Date(),
                        summary: "AI conversation advanced"
                    ),
                    at: 0
                )
                updated = note
            }

            replace(note: updated)
            followUpDraft = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCurrentNote() async {
        guard let selectedNoteID else { return }

        if isUsingLocalFallback {
            errorMessage = "Local MVP mode does not need a network refresh."
            return
        }

        do {
            let refreshed = try await client.fetchNote(noteID: selectedNoteID)
            replace(note: refreshed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
    }

    func createNoteFromAssistant() async {
        let text = assistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        draftText = text
        draftNoteID = nil
        lastSavedDraftText = ""
        await autosaveDraftIfNeeded()

        assistantDraft = ""
        showAssistant = false

        if let draftNoteID {
            openNote(noteID: draftNoteID)
        }
    }

    func note(for noteID: String) -> APINote? {
        notes.first(where: { $0.id == noteID })
    }

    private func createDraft(text: String) async throws -> APINote {
        if isUsingLocalFallback {
            return createLocalDraft(text: text)
        }

        return try await client.createNote(title: "", text: text)
    }

    private func saveExistingDraft(noteID: String, text: String) async throws -> APINote {
        if isUsingLocalFallback {
            return updateLocalDraft(noteID: noteID, text: text)
        }

        return try await client.updateNote(noteID: noteID, title: nil, text: text)
    }

    private func replace(note: APINote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }
    }

    private func createLocalDraft(text: String) -> APINote {
        let now = Date()
        let note = APINote(
            id: UUID().uuidString,
            title: String(text.prefix(28)),
            text: text,
            createdAt: now,
            updatedAt: now,
            status: "captured",
            enrichments: [],
            links: [],
            sources: [],
            prompts: [],
            timeline: [
                APITimelineEvent(
                    id: UUID().uuidString,
                    type: "note_created",
                    createdAt: now,
                    summary: "Note created"
                )
            ],
            latestChatReply: nil
        )
        notes.insert(note, at: 0)
        return note
    }

    private func updateLocalDraft(noteID: String, text: String) -> APINote {
        guard var note = note(for: noteID) else {
            return createLocalDraft(text: text)
        }

        note.text = text
        note.title = String(text.prefix(28))
        note.updatedAt = Date()
        note.status = "edited"
        note.timeline.insert(
            APITimelineEvent(
                id: UUID().uuidString,
                type: "note_edited",
                createdAt: Date(),
                summary: "Note updated by user"
            ),
            at: 0
        )
        return note
    }

    private func enrichLocalNote(noteID: String) -> APINote {
        guard var note = note(for: noteID) else {
            return Self.demoNotes[0]
        }

        let now = Date()
        let source = APISource(
            title: "Public article",
            url: "https://example.com/idea",
            snippet: "Background research attached to the current AI interpretation."
        )
        let enrichment = APIEnrichment(
            id: UUID().uuidString,
            createdAt: now,
            provider: "local",
            expansion: "This thought can be developed further by turning the fragment into a clearer argument and checking it against outside knowledge.",
            relatedIdeas: [],
            prompts: [
                "What is the strongest version of this idea?",
                "What evidence would make this more believable?"
            ],
            links: [],
            sources: [source]
        )

        note.status = "enriched"
        note.updatedAt = now
        note.enrichments.insert(enrichment, at: 0)
        note.sources = [source]
        note.prompts = enrichment.prompts
        note.timeline.insert(
            APITimelineEvent(
                id: UUID().uuidString,
                type: "note_enriched",
                createdAt: now,
                summary: "AI interpretation refreshed"
            ),
            at: 0
        )
        return note
    }

    private func chatLocalNote(noteID: String, message: String) -> APINote {
        guard var note = note(for: noteID) else {
            return Self.demoNotes[0]
        }

        note.latestChatReply = "A useful next step is to turn that follow-up into a sharper question, then compare it against the note's current interpretation."
        note.updatedAt = Date()
        note.timeline.insert(
            APITimelineEvent(
                id: UUID().uuidString,
                type: "chat_updated",
                createdAt: Date(),
                summary: "AI conversation advanced"
            ),
            at: 0
        )
        note.prompts = [message] + note.prompts
        return note
    }

    static let demoNotes: [APINote] = [
        APINote(
            id: UUID().uuidString,
            title: "Mouse snoring",
            text: "我发现老鼠真的会打鼾",
            createdAt: Date().addingTimeInterval(-8600),
            updatedAt: Date().addingTimeInterval(-1800),
            status: "enriched",
            enrichments: [
                APIEnrichment(
                    id: UUID().uuidString,
                    createdAt: Date().addingTimeInterval(-1800),
                    provider: "local",
                    expansion: "The observation may be interesting because it turns a tiny animal behavior into something unexpectedly human and memorable.",
                    relatedIdeas: [],
                    prompts: ["你为什么这么说", "可我没有养老鼠"],
                    links: [],
                    sources: [
                        APISource(
                            title: "Research link",
                            url: "https://example.com/mice",
                            snippet: "Some mice vocalize during sleep-like states, which makes the observation plausible."
                        )
                    ]
                )
            ],
            links: [],
            sources: [
                APISource(
                    title: "Research link",
                    url: "https://example.com/mice",
                    snippet: "Some mice vocalize during sleep-like states, which makes the observation plausible."
                )
            ],
            prompts: ["你为什么这么说", "可我没有养老鼠"],
            timeline: [
                APITimelineEvent(
                    id: UUID().uuidString,
                    type: "note_enriched",
                    createdAt: Date().addingTimeInterval(-1800),
                    summary: "AI responded yesterday"
                )
            ],
            latestChatReply: nil
        ),
        APINote(
            id: UUID().uuidString,
            title: "Work and hugs",
            text: "以后或许人类最有价值的工作是提供拥抱服务",
            createdAt: Date().addingTimeInterval(-5400),
            updatedAt: Date().addingTimeInterval(-3600),
            status: "captured",
            enrichments: [],
            links: [],
            sources: [],
            prompts: ["What would make this feel more concrete?"],
            timeline: [
                APITimelineEvent(
                    id: UUID().uuidString,
                    type: "note_created",
                    createdAt: Date().addingTimeInterval(-5400),
                    summary: "Note created"
                )
            ],
            latestChatReply: nil
        ),
        APINote(
            id: UUID().uuidString,
            title: "Work type change",
            text: "人类的工作类型将会大变...",
            createdAt: Date().addingTimeInterval(-3200),
            updatedAt: Date().addingTimeInterval(-2200),
            status: "captured",
            enrichments: [],
            links: [],
            sources: [],
            prompts: [],
            timeline: [
                APITimelineEvent(
                    id: UUID().uuidString,
                    type: "note_created",
                    createdAt: Date().addingTimeInterval(-3200),
                    summary: "Note created"
                )
            ],
            latestChatReply: nil
        ),
        APINote(
            id: UUID().uuidString,
            title: "Cats and humans",
            text: "一个想法不一定对：也许以后人类真的不需要养宠物了，因为猫咪会把人当宠物",
            createdAt: Date().addingTimeInterval(-2500),
            updatedAt: Date().addingTimeInterval(-1200),
            status: "captured",
            enrichments: [],
            links: [],
            sources: [],
            prompts: [],
            timeline: [
                APITimelineEvent(
                    id: UUID().uuidString,
                    type: "note_created",
                    createdAt: Date().addingTimeInterval(-2500),
                    summary: "Note created"
                )
            ],
            latestChatReply: nil
        )
    ]
}

struct ThinknoteAPIClient {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:8787")!) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        self.baseURL = baseURL
    }

    func fetchNotes() async throws -> [APINote] {
        let response: NotesResponse = try await request(path: "api/notes", method: "GET", body: Optional<String>.none)
        return response.notes
    }

    func fetchNote(noteID: String) async throws -> APINote {
        let response: NoteResponse = try await request(path: "api/notes/\(noteID)", method: "GET", body: Optional<String>.none)
        return response.note
    }

    func createNote(title: String, text: String) async throws -> APINote {
        let body = CreateNoteRequest(title: title, text: text)
        let response: NoteResponse = try await request(path: "api/notes", method: "POST", body: body)
        return response.note
    }

    func updateNote(noteID: String, title: String?, text: String) async throws -> APINote {
        let body = UpdateNoteRequest(title: title, text: text)
        let response: NoteResponse = try await request(path: "api/notes/\(noteID)", method: "PATCH", body: body)
        return response.note
    }

    func enrich(noteID: String) async throws -> APINote {
        let body = EnrichNoteRequest(focus: "product thinking", includeWeb: true)
        let response: EnrichResponse = try await request(path: "api/notes/\(noteID)/enrich", method: "POST", body: body)
        return response.note
    }

    func chat(noteID: String, message: String) async throws -> APIChat {
        let body = ChatRequest(noteID: noteID, message: message)
        let response: ChatResponse = try await request(path: "api/chat", method: "POST", body: body)
        return response.chat
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

private struct EnrichResponse: Decodable {
    let note: APINote
}

private struct ChatResponse: Decodable {
    let chat: APIChat
}

private struct CreateNoteRequest: Encodable {
    let title: String
    let text: String
}

private struct UpdateNoteRequest: Encodable {
    let title: String?
    let text: String
}

private struct EnrichNoteRequest: Encodable {
    let focus: String
    let includeWeb: Bool
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
