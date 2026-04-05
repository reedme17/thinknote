# Thinknote App Product Requirements

## 1. Product Overview

Thinknote is a mobile app for capturing and growing ideas with native AI built into the core experience.

It is not just a note-taking app. It is a personal thinking assistant that helps users record thoughts, expand them, connect them to other ideas, and enrich them with relevant knowledge from the web.

The product should feel like an intelligent companion for thinking, not a passive storage tool.

## 2. Product Vision

Thinknote helps users turn raw thoughts into a living idea and knowledge garden.

After a user captures an idea, the app can use LLM capabilities to:

- Expand the idea into more complete thoughts
- Suggest related questions, angles, or interpretations
- Connect the idea to existing notes and past thoughts
- Retrieve relevant external knowledge and sources from the web
- Surface insights that may trigger new ideas

The long-term goal is to help users build a personal network of thoughts and knowledge over time.

## 3. Product Type

- Platform: mobile app
- Core experience: native AI product
- Primary role: personal assistant for thinking and idea development

## 4. Target User

Primary users are individuals who frequently capture thoughts, questions, observations, and early-stage ideas, and want help developing them further.

Likely user motivations:

- Capture ideas before they disappear
- Revisit thoughts and see them evolve
- Discover connections between notes
- Learn related knowledge without leaving the app
- Maintain a personal system for thinking, not just storing content

## 5. Core Value Proposition

Thinknote provides value in four layers:

### 5.1 Capture

Users can quickly record a thought, note, or fragment of an idea.

### 5.2 Expansion

AI helps the thought become more complete by elaborating, questioning, reframing, or structuring it.

### 5.3 Connection

AI links the thought to other notes, themes, and prior ideas to reveal patterns and relationships.

### 5.4 Enrichment

AI retrieves relevant external knowledge and sources, then uses them to deepen the note and inspire additional thinking.

## 6. Core Product Principles

- AI-native, not AI-added: AI is part of the default product behavior, not a side feature
- Thought growth over note storage: the goal is to develop ideas, not merely archive them
- Background intelligence: useful AI work should happen with minimal user effort
- User agency: background automation should be complemented by explicit manual triggers and direct AI conversation
- Fluid interaction quality: the UI must feel exceptionally smooth, natural, and alive
- Trustworthy assistance: sourced knowledge should be attributable and clearly grounded

## 7. Primary Use Cases

### 7.1 Quick Idea Capture

The user opens the app and records a thought quickly with minimal friction.

### 7.2 Background Idea Development

After the user records a thought, the system processes it in the background before the user next opens the app.

Possible outcomes include:

- Idea expansion
- Related idea suggestions
- Links to existing notes
- Relevant web knowledge and citations
- Prompts that trigger further thinking

The experience should feel like the idea has quietly evolved while the user was away.

### 7.3 Manual AI Trigger

The user can explicitly ask the system to grow, connect, or research an idea on demand.

### 7.4 Direct AI Conversation

The user can actively chat with the AI about a note, a cluster of notes, or a developing idea.

## 8. Functional Requirements

### 8.1 Note and Thought Capture

The app must allow users to:

- Create a new thought or note quickly
- Edit and revisit captured content
- Preserve a history of personal ideas over time

### 8.2 AI-Powered Idea Growth

The app must support AI workflows that can:

- Expand incomplete thoughts into fuller drafts
- Identify missing angles, assumptions, and follow-up questions
- Suggest directions for continued exploration
- Help an idea mature over time

### 8.3 Note-to-Note Connection

The app must support semantic linking between user notes, including:

- Similar ideas
- Complementary ideas
- Contradictory or tension-based ideas
- Shared themes or concepts

### 8.4 Knowledge Retrieval and Grounding

The app must be able to retrieve relevant web knowledge related to a note or idea.

Retrieved knowledge should:

- Be relevant to the user’s thought
- Include source attribution
- Help deepen or challenge the existing idea
- Potentially trigger additional related thoughts

### 8.5 Background Processing

By default, AI enrichment should happen after a user records an idea and before the next time the user opens the app.

This should create the feeling that idea development happened in the background, even if the user did not manually initiate it.

### 8.6 Manual Control

The app must also provide user-controlled ways to:

- Manually trigger AI processing
- Ask the AI to focus on a specific note
- Start an intentional conversation with the AI

## 9. User Experience Requirements

The most important product highlight is UI interaction quality.

The app must deliver:

- Extremely smooth and natural animations
- Highly fluid transitions between states and views
- A feeling of intelligence and responsiveness in motion
- Minimal friction between capture, review, and AI interaction

Animation and interaction are not cosmetic. They are a core part of the product’s differentiation.

Detailed UX specifications will be defined in separate design documents, but engineering and product decisions should preserve this requirement from the start.

## 10. Experience Goals

The user should feel that:

- Capturing a thought is effortless
- The app helps their ideas grow even when they are not actively using it
- Their notes are becoming part of a larger thinking system
- AI responses are helpful, relevant, and well connected to their existing context
- The interface feels premium, fluid, and deeply intentional

## 11. Product Differentiation

Thinknote is differentiated by the combination of:

- Personal idea capture
- Native AI thinking support
- Background idea expansion
- Cross-note connection
- Knowledge sourcing from the web
- Exceptional interaction and animation quality

It should not position itself as a generic notes app with a chatbot attached.

## 12. Non-Goals

The first product definition should avoid drifting toward:

- Generic note storage with no intelligence
- Enterprise collaboration workflows
- Complex document editing tools
- Feature-heavy workspace management
- AI output without grounding or sources when knowledge retrieval is involved

## 13. Open Product Questions

These areas still need explicit decisions in future product and design documents:

- What is the default unit of capture: short thought, note, voice input, or all of them?
- How visible should background AI processing be to the user?
- What level of autonomy should the AI have when editing, augmenting, or linking notes?
- How should sourced knowledge be displayed and cited in the UI?
- How should the idea graph or knowledge garden be represented visually?
- What kinds of manual AI actions should be first-class in the MVP?
- Which parts of the AI experience must feel on-device or native versus cloud-assisted?

## 14. MVP Direction

An initial MVP should prove the core loop:

1. User captures a thought
2. The app preserves it reliably
3. AI expands or connects that thought
4. The app surfaces related knowledge and sources
5. The user returns and discovers meaningful evolution in the idea

The MVP should only include enough functionality to validate that this loop is genuinely useful and delightful.

## 15. Steering Guidance

When evaluating future features, the product team should ask:

1. Does this help users grow ideas, not just store them?
2. Does this strengthen the feeling of a personal thinking assistant?
3. Does this improve the background-to-discovery loop?
4. Does this preserve or improve interaction fluidity?
5. Does this make the product feel more like a knowledge garden over time?

If a feature does not support these goals, it should be deprioritized.
