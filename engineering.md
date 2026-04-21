# Thinknote Engineering Requirements

## 1. Current Project Baseline

The current app is an Xcode SwiftUI starter project:

- UI: SwiftUI
- Local persistence: SwiftData
- App structure: single-scene iOS app
- Testing baseline: Swift Testing and XCUIAutomation targets exist but are still empty

Current code only supports storing timestamped `Item` records. It does not yet implement note capture, AI growth, note linking, web grounding, or background processing.

## 2. Engineering Goal

Based on `product.md`, the MVP should prove this loop:

1. User captures a thought quickly
2. The thought is stored reliably
3. AI expands or connects the thought
4. The app enriches the thought with sourced web knowledge
5. The user returns and sees meaningful evolution

Engineering should therefore optimize for:

- low-friction capture
- reliable local-first note storage
- asynchronous AI workflows
- source-grounded web enrichment
- smooth, premium interaction quality

## 3. Required Core Technologies

### 3.1 App Layer

- SwiftUI
  - Primary UI framework for capture, note detail, AI panels, and transitions
  - Required because interaction quality is a core product requirement
- Swift Concurrency (`async`/`await`, `Task`, actors)
  - Required for AI calls, retrieval, indexing, and background workflows
- Observation / SwiftUI state system
  - Required for reactive view updates and low-complexity state flow

### 3.2 Local Data Layer

- SwiftData
  - Primary persistence for notes, AI artifacts, links, sources, and processing state
  - Fits the current project setup and reduces integration cost
- Structured model design
  - Recommended core entities:
    - `Note`
    - `NoteRevision`
    - `IdeaLink`
    - `SourceReference`
    - `AIJob`
    - `ConversationThread`
    - `ConversationMessage`

### 3.3 AI Layer

- AI provider abstraction
  - A thin service layer is required so the app is not tightly coupled to one model vendor
  - Suggested protocols:
    - note expansion
    - note linking
    - follow-up question generation
    - source-grounded synthesis
    - chat
- FoundationModels
  - Should be evaluated first for on-device and native Apple-platform AI capabilities where applicable
  - Best fit for “native AI” positioning if supported by the target OS and product quality needs
- Cloud LLM integration
  - Likely still required for higher quality reasoning, web-grounded synthesis, and flexible prompting
  - Must support structured outputs, retries, and observability

### 3.3.1 Recommended AI Architecture

Thinknote should use a hybrid AI architecture rather than assuming one model can satisfy every requirement.

Recommended routing:

- On-device first for fast, private, native-feeling tasks
- Cloud fallback for unsupported devices or unavailable local model state
- Cloud-primary for tasks that require web retrieval, stronger reasoning, or stable cross-device behavior

This architecture is necessary because the product requires both:

- native-feeling AI integrated into the note workflow
- source-grounded and retrieval-heavy enrichment that is better handled off device

### 3.3.2 Where FoundationModels Fits

Apple `FoundationModels` is a strong fit for:

- note expansion
- short summarization
- follow-up question generation
- chat-to-note structuring
- light classification or extraction
- guided generation of typed outputs with `@Generable`

It should not be treated as the sole AI platform for the product because:

- availability depends on Apple Intelligence device and user settings
- the on-device model may be unavailable or still downloading
- Thinknote requires web-grounded knowledge and citation workflows
- complex multi-step orchestration is better handled with a controllable remote pipeline

### 3.3.3 Remote LLM Provider Strategy

The app should define a provider-neutral interface, for example:

- `OnDeviceLLMProvider`
- `RemoteLLMProvider`
- `EmbeddingProvider`
- `AIOrchestrator`

The `AIOrchestrator` should choose execution path based on:

- task type
- model availability
- network availability
- latency target
- grounding requirement
- cost controls

Recommended initial routing rules:

- pure note expansion can run on device first
- structured chat-to-note can prefer on device, with cloud fallback
- source-grounded synthesis must run through remote orchestration
- semantic linking can use remote embeddings for MVP quality and speed
- background enrichment should generally run through backend workers

### 3.3.4 Candidate Remote LLM Services

The most relevant service categories for this product are:

- frontier hosted APIs
- fast inference providers for open models
- self-hosted or cloud-hosted open-weight models

Pragmatic candidate providers:

- OpenAI
  - best default choice when quality, tool use, and broad developer support matter most
  - strong fit for orchestration, structured outputs, and grounded synthesis
- Anthropic
  - strong alternative for writing quality, long-context note work, and agent-style reasoning
- Google Gemini
  - strong option for multimodal growth and large-context tasks
  - should be evaluated if search-grounding or broader Google stack alignment becomes important
- Cerebras
  - viable if very low latency is a primary product need
  - especially interesting for fast open-model inference rather than as the only intelligence layer
- Mistral
  - useful if we want more deployment flexibility, open-weight options, or future self-hosting paths
- Groq
  - useful for speed-sensitive open-model inference and potentially voice-related features

### 3.3.5 Recommendation on Cerebras

Yes, Cerebras can be used.

It is best viewed as a fast inference provider for open models, not as the sole product architecture.

For Thinknote, Cerebras is most attractive if we want:

- very low-latency AI responses
- OpenAI-compatible API ergonomics
- access to fast open-model inference for expansion or chat tasks

Cerebras is less ideal as the only backend AI dependency if we also need:

- best-in-class grounded synthesis quality
- strongest tool-use ecosystem
- widest model and feature coverage

The pragmatic conclusion is:

- use `FoundationModels` for native on-device workflows
- use a provider abstraction for remote tasks
- Cerebras is a reasonable remote provider option, especially for speed
- OpenAI or Anthropic remains the safer default primary provider for the first production-quality backend

### 3.4 Retrieval and Knowledge Layer

- URLSession
  - Required for calling search or retrieval APIs and fetching web content
- Search / web retrieval API
  - Required because the product explicitly needs relevant external knowledge and source attribution
  - Could be implemented through a hosted search API in MVP
- HTML extraction / readability pipeline
  - Required to convert fetched pages into clean text for ranking and synthesis
- Lightweight ranking pipeline
  - Needed to score search results against note intent before sending context to the model

### 3.5 Background Processing

- BackgroundTasks
  - Required for “idea evolved while away” behavior
  - Used to schedule post-capture enrichment and deferred AI work
- Durable job queue in local storage
  - Required because AI work may fail, pause, retry, or be interrupted
  - `AIJob` should track status, trigger source, timestamps, retries, and outputs

### 3.6 Search and Semantic Connection

- Embedding or semantic similarity capability
  - Required to connect notes by meaning rather than keywords
  - Can be implemented via:
    - on-device embeddings if platform support is sufficient
    - server-side embeddings for MVP speed and quality
- Local index or cached similarity store
  - Needed to avoid recomputing note-to-note relationships on every view load

## 4. Recommended Architecture

The app should use a local-first modular architecture:

- `Presentation`
  - SwiftUI views and navigation
- `Application`
  - Use cases such as capture note, enrich note, link note, chat with note
- `Domain`
  - Core entities and business rules
- `Infrastructure`
  - SwiftData, AI providers, retrieval clients, background scheduling, logging

This is enough structure for the MVP without introducing unnecessary architectural weight.

## 5. Data Model Requirements

The current `Item` model is too limited. MVP needs a note-centric schema.

Recommended minimum fields:

- `Note`
  - `id`
  - `createdAt`
  - `updatedAt`
  - `rawText`
  - `title`
  - `status`
  - `lastEnrichedAt`
- `NoteRevision`
  - preserves AI-generated expansions or user edits over time
- `IdeaLink`
  - connects two notes with relationship type and confidence
- `SourceReference`
  - stores title, URL, publisher, snippet, and association to a note
- `AIJob`
  - stores job type, input note, status, retry count, and timestamps
- `ConversationThread` / `ConversationMessage`
  - supports direct AI conversation around a note or note cluster

## 6. MVP Feature Modules

### 6.1 Capture

Required technologies:

- SwiftUI composer optimized for fast input
- SwiftData persistence
- autosave and draft state handling

### 6.2 Idea Growth

Required technologies:

- prompt orchestration layer
- structured AI outputs
- revision storage
- diffable display of original thought vs expanded thought

### 6.3 Note Connection

Required technologies:

- semantic similarity pipeline
- relationship classification
- cached related-note queries

### 6.4 Knowledge Enrichment

Required technologies:

- search API integration
- web fetch and extraction
- citation model
- grounded summarization prompt flow

### 6.5 AI Conversation

Required technologies:

- multi-turn chat state
- note-context injection
- source-aware response rendering

### 6.6 Background Evolution

Required technologies:

- post-capture job scheduling
- retry-safe AI jobs
- UI status surfaces such as processing, completed, failed

## 7. UX-Critical Technical Requirements

Because product quality depends heavily on fluid interaction, these are not optional:

- smooth SwiftUI navigation and transitions
- incremental loading instead of blocking screens
- streaming or staged rendering for AI results when possible
- optimistic local state updates
- animation-safe state management to avoid jank and flashing
- precomputed view models for expensive note-detail sections

If the architecture makes motion quality hard, the architecture is wrong for this product.

## 8. Security and Trust Requirements

- clear separation between user-authored content and AI-generated content
- mandatory source attribution for web-enriched outputs
- secure API key handling
  - do not hardcode secrets in the app bundle
- privacy-aware logging
  - note content should not be dumped into debug logs by default

## 9. Testing Requirements

The existing test targets should be expanded with:

- Swift Testing
  - note creation
  - AI job state transitions
  - retrieval ranking
  - note-link generation logic
- XCUIAutomation
  - fast capture flow
  - note detail rendering
  - manual “grow idea” trigger
  - background-result surfacing after relaunch

## 10. Observability Requirements

Required for debugging AI-native behavior:

- structured logging for AI jobs and retrieval steps
- latency tracking for capture-to-enrichment workflow
- failure classification for network, parsing, model, and persistence errors
- lightweight analytics for feature usefulness, especially:
  - capture frequency
  - manual AI trigger usage
  - source click-through
  - revisit rate after enrichment

## 11. Suggested MVP Implementation Order

1. Replace `Item` with a real `Note` model and note list/detail flows
2. Build fast capture and editing experience
3. Add AI service abstraction and manual “grow idea” action
4. Add source-grounded retrieval and citation display
5. Add related-note linking
6. Add background job scheduling and resurfacing
7. Add note-based AI conversation

## 12. Non-Essential for First MVP

These can wait unless product direction changes:

- complex collaborative features
- multi-platform sync beyond the initial device strategy
- advanced graph visualization
- rich document editing
- large plugin-style extensibility

## 13. Concrete Stack Recommendation

For this repository, the most pragmatic stack is:

- UI: SwiftUI
- State: SwiftUI state + Observation
- Persistence: SwiftData
- Concurrency: Swift Concurrency
- Background work: BackgroundTasks
- Networking: URLSession
- AI orchestration: provider abstraction with FoundationModels evaluation first, cloud fallback likely required
- Semantic linking: embeddings-based similarity service
- Tests: Swift Testing + XCUIAutomation
- Logging: OSLog

This stack aligns with the current codebase, preserves native feel, and is sufficient to build the product loop defined in `product.md`.
