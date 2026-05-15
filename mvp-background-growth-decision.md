# Thinknote MVP Decision: Deferred Background Growth

## 1. Purpose

This document captures the current MVP product decision for how AI should behave after a user records a note.

It is intended to align product, UX, and engineering around one clear rule:

- capturing a thought should stay lightweight
- AI growth should usually happen later
- direct AI response should remain available on demand

This document narrows MVP scope. It does not redefine the long-term product vision in `product.md`.

## 2. Core Decision

For the MVP:

- the app is `local-first`
- the default capture unit is a short thought or fragment
- recording a note does **not** require immediate AI reply
- a newly captured note may enter a weak `growing` state
- background AI growth should usually happen later, not immediately
- the user can still explicitly press `Request response` to trigger AI now

The intended feeling is:

- capture now
- leave
- come back later
- discover that the thought has matured

Thinknote should feel like an idea garden, not a mandatory chat workflow.

## 3. MVP Product Behavior

### 3.1 Capture

When the user records a note:

- save it locally right away
- preserve the user’s raw text as the anchor
- do not force the user into a chat turn
- do not require AI to answer immediately

This keeps capture fast and cognitively light.

### 3.2 Default AI Timing

After capture:

- the system may create a background growth job
- that job should not run immediately by default
- the earliest intended run time should be at least one day later
- the app may process eligible jobs opportunistically when the user opens the app again

For MVP, “background” does not need to mean fully autonomous cloud scheduling. It is enough that the work happens later and feels deferred.

### 3.3 Manual Trigger

The app must also keep an explicit `Request response` action.

This action means:

- the user wants AI help now
- the system may run the response job immediately
- the result should be appended to the note’s AI artifacts without modifying the user’s original text

### 3.4 Conversation

Conversation is still part of the product, but it is not the default next step after capture.

The intended sequence is:

1. capture a fragment
2. let it grow in the background
3. revisit the note
4. enter a deeper thread only if the user wants to explore further

## 4. Non-Negotiable Rules

### 4.1 User Text Is Sacred

The user’s original note text must remain the anchor.

- AI must not overwrite `rawText`
- AI output must be additive
- AI content belongs in revisions, timeline, sources, jobs, and conversation artifacts

### 4.2 Weak Visibility, Not Loud Interruptions

Background AI activity should be lightly visible.

- show states like `growing` or `changed since last visit`
- avoid noisy loading states as the dominant experience
- avoid forcing the user to wait on AI before they can continue

### 4.3 Revisit Is a Primary Experience

The home screen and note detail should highlight what changed while the user was away.

This includes:

- new AI growth
- new sources
- new timeline events
- conversation updates when relevant

### 4.4 Growth Must Have Rhythm and Limits

Background growth should not run forever.

Each note or job should support:

- an earliest run time
- a bounded number of growth attempts
- a bounded retry policy
- a clear completed or paused state

## 5. UX Implications for MVP

### 5.1 Home

Home should help the user answer:

- what is new
- what changed since last visit
- which notes are still growing

Important status directions:

- `growing`
- `changed since last visit`
- `in conversation`

Home should not auto-reorder notes based on AI activity. Manual ordering remains the rule.

### 5.2 Detail

Detail should show:

- the original thought
- any appended AI growth
- sourced knowledge
- timeline evolution
- conversation entry points

It should still support an explicit `Request response` action.

### 5.3 Assistant

The assistant remains important, but the product should not assume every note immediately becomes a live chat.

Threaded exploration is a deeper mode, not the default capture path.

## 6. Data and Architecture Implications

This decision reinforces the current local-first architecture.

The data model should support:

- `Note` with stable identity, raw text, timestamps, sort order, and view state
- `NoteRevision` for additive growth
- `SourceReference` for grounded knowledge
- `AIJob` for deferred work, retries, and limits
- `TimelineEvent` for revisit and change tracking
- `ConversationThread` and `ConversationMessage` for optional deep exploration

Important implementation consequences:

- creating a note should write local data immediately
- capture should be decoupled from immediate AI generation
- deferred AI work should be represented as durable jobs
- UI should read from local persisted state first
- future backend sync must layer on top of the local model, not replace it

## 7. MVP Scope Guidance

### 7.1 In Scope

- reliable local note capture
- deferred background growth model
- explicit `Request response`
- additive AI revisions and sources
- timeline-based “changed since last visit”
- persistent multi-turn conversation data model

### 7.2 Not Required for This Decision

- related notes UI
- graph visualization
- full multi-device sync
- fully autonomous long-running cloud orchestration
- final citation visual polish

## 8. Recommended MVP Implementation Order

1. Save every new note locally and mark it eligible for deferred growth.
2. Add durable AI job metadata for earliest run time, run count, retry count, and max limits.
3. On app launch or foreground entry, check for eligible growth jobs and process them opportunistically.
4. Append AI results into revisions, sources, and timeline events.
5. Surface `growing` and `changed since last visit` clearly in home and detail.
6. Keep `Request response` as an immediate manual path.
7. Treat thread-based assistant exploration as a follow-on interaction, not the default capture outcome.

## 9. Summary

The MVP should optimize for this loop:

1. capture a fragment quickly
2. save it reliably
3. let it grow later
4. return and notice meaningful change
5. go deeper only when the user chooses to

This is the current product direction and should guide near-term implementation decisions.
