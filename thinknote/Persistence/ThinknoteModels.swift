import Foundation
import SwiftData

enum NoteStatus: String, Codable, CaseIterable, Sendable {
    case captured
    case edited
    case queued
    case enriched
    case failed
}

enum RevisionKind: String, Codable, CaseIterable, Sendable {
    case userCapture = "user_capture"
    case userEdit = "user_edit"
    case aiEnrichment = "ai_enrichment"
}

enum LinkKind: String, Codable, CaseIterable, Sendable {
    case related
    case supports
    case contrasts
    case extendsIdea = "extends"
}

enum MessageRole: String, Codable, CaseIterable, Sendable {
    case system
    case user
    case assistant
}

enum JobType: String, Codable, CaseIterable, Sendable {
    case enrichNote = "enrich_note"
    case chatReply = "chat_reply"
    case linkNotes = "link_notes"
}

enum JobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case retrying
    case completed
    case failed
    case cancelled
}

enum JobPriority: String, Codable, CaseIterable, Sendable {
    case low
    case normal
    case high
}

enum TimelineEventKind: String, Codable, CaseIterable, Sendable {
    case noteCreated = "note_created"
    case noteEdited = "note_edited"
    case noteEnriched = "note_enriched"
    case chatUpdated = "chat_updated"
    case jobQueued = "job_queued"
    case jobRetried = "job_retried"
    case jobCompleted = "job_completed"
    case jobFailed = "job_failed"
}

@Model
final class NoteRecord {
    @Attribute(.unique) var id: String
    var title: String
    var rawText: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var lastViewedAt: Date?
    var lastEnrichedAt: Date?
    var latestChatReply: String?
    var sortIndex: Double?
    @Attribute(.externalStorage) var promptSuggestionsData: Data?

    @Relationship(deleteRule: .cascade, inverse: \RevisionRecord.note) var revisions: [RevisionRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \SourceRecord.note) var sources: [SourceRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \LinkRecord.fromNote) var outgoingLinks: [LinkRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \LinkRecord.toNote) var incomingLinks: [LinkRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \ThreadRecord.primaryNote) var threads: [ThreadRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \JobRecord.note) var jobs: [JobRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \TimelineEventRecord.note) var timelineEvents: [TimelineEventRecord] = []

    init(
        id: String = UUID().uuidString,
        title: String,
        rawText: String,
        status: NoteStatus,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastViewedAt: Date? = nil,
        lastEnrichedAt: Date? = nil,
        latestChatReply: String? = nil,
        sortIndex: Double? = nil,
        promptSuggestions: [String] = []
    ) {
        self.id = id
        self.title = title
        self.rawText = rawText
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastViewedAt = lastViewedAt
        self.lastEnrichedAt = lastEnrichedAt
        self.latestChatReply = latestChatReply
        self.sortIndex = sortIndex
        self.promptSuggestionsData = StoredJSONCodec.encode(promptSuggestions)
    }

    var status: NoteStatus {
        get { NoteStatus(rawValue: statusRaw) ?? .captured }
        set { statusRaw = newValue.rawValue }
    }

    var promptSuggestions: [String] {
        get { StoredJSONCodec.decode([String].self, from: promptSuggestionsData) ?? [] }
        set { promptSuggestionsData = StoredJSONCodec.encode(newValue) }
    }
}

@Model
final class RevisionRecord {
    @Attribute(.unique) var id: String
    var createdAt: Date
    var kindRaw: String
    var summary: String
    var text: String

    var note: NoteRecord?
    var sourceJob: JobRecord?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = .now,
        kind: RevisionKind,
        summary: String,
        text: String,
        note: NoteRecord? = nil,
        sourceJob: JobRecord? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kindRaw = kind.rawValue
        self.summary = summary
        self.text = text
        self.note = note
        self.sourceJob = sourceJob
    }

    var kind: RevisionKind {
        get { RevisionKind(rawValue: kindRaw) ?? .userCapture }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class SourceRecord {
    @Attribute(.unique) var id: String
    var title: String
    var urlString: String
    var snippet: String
    var publisher: String
    var query: String
    var score: Double
    var retrievedAt: Date

    var note: NoteRecord?
    var message: MessageRecord?
    var sourceJob: JobRecord?

    init(
        id: String = UUID().uuidString,
        title: String,
        urlString: String,
        snippet: String,
        publisher: String = "",
        query: String = "",
        score: Double = 0,
        retrievedAt: Date = .now,
        note: NoteRecord? = nil,
        message: MessageRecord? = nil,
        sourceJob: JobRecord? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.snippet = snippet
        self.publisher = publisher
        self.query = query
        self.score = score
        self.retrievedAt = retrievedAt
        self.note = note
        self.message = message
        self.sourceJob = sourceJob
    }
}

@Model
final class LinkRecord {
    @Attribute(.unique) var id: String
    var title: String
    var relationshipRaw: String
    var confidence: Double
    var summary: String
    var createdAt: Date

    var fromNote: NoteRecord?
    var toNote: NoteRecord?

    init(
        id: String = UUID().uuidString,
        title: String,
        relationship: LinkKind,
        confidence: Double = 0,
        summary: String = "",
        createdAt: Date = .now,
        fromNote: NoteRecord? = nil,
        toNote: NoteRecord? = nil
    ) {
        self.id = id
        self.title = title
        self.relationshipRaw = relationship.rawValue
        self.confidence = confidence
        self.summary = summary
        self.createdAt = createdAt
        self.fromNote = fromNote
        self.toNote = toNote
    }

    var relationship: LinkKind {
        get { LinkKind(rawValue: relationshipRaw) ?? .related }
        set { relationshipRaw = newValue.rawValue }
    }
}

@Model
final class ThreadRecord {
    @Attribute(.unique) var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.externalStorage) var relatedNoteIDsData: Data?

    var primaryNote: NoteRecord?
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.thread) var messages: [MessageRecord] = []

    init(
        id: String = UUID().uuidString,
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        primaryNote: NoteRecord? = nil,
        relatedNoteIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.primaryNote = primaryNote
        self.relatedNoteIDsData = StoredJSONCodec.encode(relatedNoteIDs)
    }

    var relatedNoteIDs: [String] {
        get { StoredJSONCodec.decode([String].self, from: relatedNoteIDsData) ?? [] }
        set { relatedNoteIDsData = StoredJSONCodec.encode(newValue) }
    }
}

@Model
final class MessageRecord {
    @Attribute(.unique) var id: String
    var roleRaw: String
    var text: String
    var provider: String
    var createdAt: Date

    var thread: ThreadRecord?
    @Relationship(deleteRule: .cascade, inverse: \SourceRecord.message) var sources: [SourceRecord] = []

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        text: String,
        provider: String,
        createdAt: Date = .now,
        thread: ThreadRecord? = nil
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.text = text
        self.provider = provider
        self.createdAt = createdAt
        self.thread = thread
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }
}

@Model
final class JobRecord {
    @Attribute(.unique) var id: String
    var typeRaw: String
    var statusRaw: String
    var priorityRaw: String?
    var triggerSource: String
    @Attribute(.externalStorage) var payloadData: Data?
    @Attribute(.externalStorage) var outputData: Data?
    var dedupeKey: String?
    var retryCount: Int
    var maxRetries: Int
    var runCount: Int
    var maxRunCount: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var lastAttemptAt: Date?
    var completedAt: Date?
    var earliestRunAt: Date?
    var nextRunAt: Date

    var note: NoteRecord?
    @Relationship(deleteRule: .nullify, inverse: \RevisionRecord.sourceJob) var generatedRevisions: [RevisionRecord] = []
    @Relationship(deleteRule: .nullify, inverse: \SourceRecord.sourceJob) var generatedSources: [SourceRecord] = []

    init(
        id: String = UUID().uuidString,
        type: JobType,
        status: JobStatus,
        priority: JobPriority = .normal,
        triggerSource: String,
        payloadData: Data? = nil,
        outputData: Data? = nil,
        dedupeKey: String? = nil,
        retryCount: Int = 0,
        maxRetries: Int = 3,
        runCount: Int = 0,
        maxRunCount: Int = 1,
        lastError: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        startedAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        completedAt: Date? = nil,
        earliestRunAt: Date? = nil,
        nextRunAt: Date = .now,
        note: NoteRecord? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.triggerSource = triggerSource
        self.payloadData = payloadData
        self.outputData = outputData
        self.dedupeKey = dedupeKey
        self.retryCount = retryCount
        self.maxRetries = maxRetries
        self.runCount = runCount
        self.maxRunCount = maxRunCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.lastAttemptAt = lastAttemptAt
        self.completedAt = completedAt
        self.earliestRunAt = earliestRunAt
        self.nextRunAt = nextRunAt
        self.note = note
    }

    var type: JobType {
        get { JobType(rawValue: typeRaw) ?? .enrichNote }
        set { typeRaw = newValue.rawValue }
    }

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    var priority: JobPriority {
        get { JobPriority(rawValue: priorityRaw ?? "") ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var scheduledRunAt: Date {
        get { earliestRunAt ?? nextRunAt }
        set { earliestRunAt = newValue }
    }
}

@Model
final class TimelineEventRecord {
    @Attribute(.unique) var id: String
    var typeRaw: String
    var createdAt: Date
    var summary: String
    @Attribute(.externalStorage) var payloadData: Data?

    var note: NoteRecord?

    init(
        id: String = UUID().uuidString,
        type: TimelineEventKind,
        createdAt: Date = .now,
        summary: String,
        payloadData: Data? = nil,
        note: NoteRecord? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.createdAt = createdAt
        self.summary = summary
        self.payloadData = payloadData
        self.note = note
    }

    var type: TimelineEventKind {
        get { TimelineEventKind(rawValue: typeRaw) ?? .noteCreated }
        set { typeRaw = newValue.rawValue }
    }
}

enum StoredJSONCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
