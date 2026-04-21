# Thinknote UX Direction

This document defines the initial UX direction for Thinknote. It is not a final design spec. The UX should evolve through implementation and testing, but the core interaction model should stay consistent.

## 1. UX Positioning

Thinknote should not feel like a traditional notes app with a list and an AI button.

It should feel like:

- A living canvas of ideas
- A personal thinking space that becomes richer over time
- A product where AI is quietly present in the background and immediately available when needed

The key UX goal is to make users feel that ideas are alive, connected, and still growing.

## 2. Core UX Principles

- Spatial instead of list-first: the primary home experience is a canvas, not a vertical feed
- Low-friction capture: creating a thought should take almost no effort
- Continuous idea growth: the UI should show that notes can evolve after capture
- AI as collaborator: AI should feel embedded in the workflow, not bolted on
- Calm intelligence: AI should assist without overwhelming the screen
- Visible grounding: sourced knowledge must feel trustworthy and clearly attributed
- Premium motion: animation and transitions are part of the product value, not decoration
- Bio-order: the product should juxtapose a rigid mobile-readable structure with organic, cellular motion and fusion behavior
- Living container: every note card should feel like a cell with surface tension, membrane definition, and internal pressure
- Silent AI: AI presence should often be expressed as an environmental change such as pulsing borders or soft color bleed rather than only as explicit controls

## 2.1 Visual System And Tokens

### Design Vision And Philosophy

- Bio-Order (`生物秩序感`): a juxtaposition of a rigid 2-column grid and organic, cellular micro-interactions
- Living Container: every card is a cell and should feel like it has surface tension and internal pressure
- Silent AI: AI presence is often an environmental change such as pulsing or bleeding color rather than a heavy visible UI block

### Color System And Design Tokens

| Token | Value | Implementation Note |
|---|---|---|
| `Canvas_BG` | `#F7F7F5` | Main background. Apply a fine 2% noise grain texture. |
| `Card_Surface` | `#FFFFFF` | Ceramic white. `box-shadow: 0 4px 20px rgba(0,0,0,0.02)`. |
| `Card_Border` | `#E0E0DB` | `border: 0.5px solid`. Used for defining the cell membrane. |
| `AI_Accent` | `#87A99C` | Sage green. Used for stroke-bleed and fusion effects. |
| `Text_Primary` | `#2C2C2C` | Primary text color. |
| `Text_Secondary` | `#8E8E8A` | Used for timestamps and web citations or footnotes. |

Typography note from the visual guideline:

- Replace the earlier `Inter` placeholder with the agreed product typography:
  - `Alegreya Sans` for headings
  - `David Libre` for body copy
  - target body line-height remains within the visual-guideline range of `1.4 - 1.6`

## 3. Home Experience

### 3.1 Home as Idea Canvas

The home screen should feel like an idea canvas, but on mobile it should use a two-column note layout rather than a fully freeform surface.

The canvas contains:

- Existing note cards
- Empty cards that invite new thought capture
- Small clusters of related notes that suggest emerging themes

This screen should feel more like entering a thinking space than opening a document manager.

The layout should be:

- Two columns
- 2-column masonry or waterfall logic rather than identical locked rows
- Vertically stacked cards in each column
- 16px horizontal and vertical gaps as the default home rhythm
- Comfortable padding and whitespace between cards
- Slightly imperfect card angles so the grid does not feel rigid
- Stable card positions by default, so notes feel anchored in a familiar place over time

The default background of the home canvas should use `Canvas_BG` with a fine noise grain texture plus a grid layer. The grid morphs in areas where the cards develop. The heavier the cards develop, the stronger morphs become.

### 3.2 Card Behavior

Each card should feel light, tactile, and movable.

Users should be able to:

- Tap an existing card to open note detail
- Tap an empty card to create a new note
- Long-press a card to reorder it within the two-column layout
- Notice visual proximity between related notes or grouped themes

The layout does not need to be perfectly manual or perfectly system-generated. It should be a hybrid:

- The system maintains the overall two-column structure for readability on mobile
- Users can influence local arrangement through long-press reordering
- The system can still express higher-level grouping through nearby placement, subtle angle variation, and background affinity clustering

Cross-note movement does not need to be exposed as a dedicated related-notes section inside the full-page note view.

In later iterations, users may switch between nearby or linked notes through horizontal swipe gestures on cards. The UI hint treatment for this interaction is still undefined and can be explored later.

Card surface and membrane rules:

- Card face should use `Card_Surface`
- Card edge should use a `0.5px` `Card_Border`
- The card should feel like a membrane, not a hard tile
- A subtle ceramic shadow is preferred over a heavy floating shadow
- Card height should be content-responsive within the masonry system
- If a card summary exceeds 3 lines, apply a vertical alpha mask at the bottom so the text softly fades rather than hard-clips

### 3.3 Empty-State Design

An empty card is not a blank white document. It is an invitation to think.

It should communicate:

- Start a thought
- Save a question
- Capture an observation
- Begin from a fragment

The emotional tone should reduce pressure. The app should make partial thinking feel valid.

The entry card should also behave as a `New Seed` slot:

- It is always the last item in the home array
- Visual treatment: transparent background with `1px dashed #D1D1CB`
- Clicking or tapping should expand it into a full-screen input modal through a shared-element transition

## 4. New Note Capture

Creating a note from the home canvas should feel immediate.

The flow should be:

1. User taps an empty card
2. The seed slot expands through a shared-element transition into a full-screen input modal
3. The user writes a short thought, fragment, or draft
4. The note is saved with minimal interruption
5. The user returns naturally to the canvas

The capture UI should avoid heavy form structure. Early thoughts are often incomplete and should not require categorization before saving.

The transition should be specific rather than optional:

- The tapped home seed slot expands through a shared-element transition
- The destination is a full-screen input modal
- The transition should preserve the feeling that the new note is still the same growing cell, not a different product surface

## 5. Note Detail Experience

Opening a note should feel like entering the thinking context around that idea, not just viewing static text.

### 5.1 Main Detail Areas

The detail view should include:

- The original note content
- Expanded idea development generated by AI
- Relevant web knowledge with citations
- Prompts that trigger further thinking
- A timeline showing how the note evolved over time

Related notes do not need to appear as a visible content section in the full-page note view for the MVP.

Instead, note-to-note exploration can later be expressed through horizontal card-to-card switching interactions. The UI hint treatment for that interaction is still to be designed.

### 5.2 Information Hierarchy

The original note should remain the anchor.

AI enrichments should feel attached to the user’s thought, not like they replaced it.

The likely order of emphasis is:

1. Original thought
2. Most relevant AI expansion or interpretation
3. Web knowledge and citations attached to the AI response
4. Reflection prompts or response entry
5. Evolution history

### 5.3 Timeline / Evolution

The note should show that growth happened over time.

This timeline can include:

- User edits
- AI-generated expansions
- Newly surfaced source-backed knowledge

The timeline should help users answer one question quickly: what changed since I last looked at this idea?

## 6. Background AI Experience

One of the most important UX qualities is that ideas feel alive even when the user is away.

After a note is created, the system may process it before the next app open.

Possible results include:

- Better structured interpretation of the note
- Related note grouping
- New semantic links
- Source-backed knowledge retrieval
- New prompts for deeper thinking

The UX should communicate background work subtly.

It should not feel like:

- Surprise rewriting of the user’s note
- Aggressive notifications
- Large unexplained blocks of AI text

It should feel like the idea matured quietly and is now more useful.

## 7. AI Assistant Experience

### 7.1 Floating Assistant

The home screen should include a lightweight floating AI assistant entry point.

This assistant should be:

- Always reachable
- Visually present but not dominant
- Consistent across the main thinking flow

### 7.2 Assistant Capabilities

The assistant should help users:

- Start from zero when they do not know what to write
- Explore a developing idea through conversation
- Ask for alternative angles or questions
- Summarize a conversation into a note worth saving

### 7.3 Relationship Between Chat and Notes

Chat should not be a separate universe.

The UX should make it easy to move from:

- Canvas to chat
- Chat to note
- Note to focused AI discussion

The assistant is valuable because it turns conversation into durable thinking artifacts.

## 8. Motion and Interaction

Motion is a core product differentiator.

The UX should emphasize:

- Smooth card movement
- Natural expansion from card to detail
- Fluid transitions between canvas, note, and chat
- Subtle status changes when background updates appear
- A sense that the interface is responsive and alive

Animation should support orientation and delight. It should never make the app feel slow or ornamental.

### 8.1 Ambient Breathing

Cards should have a subtle non-linear breathing behavior so they feel biologically alive rather than static.

Effect:

- Subtle non-linear distortion of the card boundary

Implementation direction:

- Use an SVG `feDisplacementMap` filter or a `clip-path` driven by a low-frequency noise function

Parameters:

- Idle: frequency `0.2Hz`, amplitude `0.8px`
- AI processing: frequency `1.2Hz`, amplitude `2px`
- During AI processing, gradually transition border color toward `AI_Accent`

### 8.2 Affinity Grouping

Affinity grouping should read like cellular fusion rather than simple z-stack overlap.

Trigger:

- Long-press to activate reorder
- Drag Card A over Card B

Fusion specs:

- Reorder should remain the default interpretation for ordinary vertical repositioning within a column
- Affinity should only trigger when overlap is intentional and sustained
- The overlap threshold for affinity should be greater than `35%`
- The card must remain in that overlap state for at least `500ms` before affinity is confirmed
- When affinity is confirmed, remove the internal borders between the two cards
- In the overlap zone, render a dynamic moire pattern of fine `0.5px` lines that shifts slightly based on drag offset
- Apply a `mix-blend-mode: multiply` sage-green gradient within the overlap zone to simulate fluid mixing
- Trigger a light haptic when cards begin to fuse

### 8.3 Deletion / Apoptosis

Deletion should not feel abrupt. It should feel like an inward biological collapse.

Visual:

- Implosion toward the card's geometric center

Curve:

- `cubic-bezier(0.4, 0, 1, 1)`

Timeline:

- `0ms`: border starts pulsing rapidly
- `100ms`: scale `1.0 -> 0.1`, opacity `1.0 -> 0.4`
- `400ms`: card removed from DOM and surrounding grid items re-flow with a spring animation

Haptics:

- Trigger a medium haptic on deletion completion

### 8.4 Performance And Gesture Notes

- Use GPU-accelerated properties such as `transform` and `opacity` for breathing and transition animations
- Home view should support `PanGesture` for reordering and `LongPress` for grouping
- Long press should require `2s` before entering reorder mode
- Once reorder mode begins, cards should enter a subtle jiggle state to communicate editability

## 9. Trust and Knowledge Display

When AI brings in knowledge from the web, the source must be visible.

The UX should make citations feel:

- Easy to notice
- Easy to inspect
- Clearly tied to the generated insight

Users should be able to distinguish between:

- Their original thought
- AI interpretation
- Retrieved external knowledge

This separation is important for trust.

Additional grounding treatment:

- Web knowledge remains conceptually attached to the AI response
- In the detail-view layout, grounding references should be rendered as lightweight footnote capsules fixed at the bottom of the scroll view
- Capsule structure: `[Favicon] | [Domain Name]`
- `Text_Secondary` should be used for timestamps and footnotes

## 9.1 Full Page Detail As Evolution View

The detail page should feel like mantle expansion from the original cell.

Transition:

- Shared element transition
- The card membrane inflates to become the detail-view background
- Timing target: `500ms`
- Spring target: `stiffness 120`, `damping 20`

Layout anatomy from top to bottom:

- Original Thought: `18px`, medium weight
- Growth Block: `16px`, triggered by block expansion
- Footnotes or grounding references: fixed at the bottom of the scroll view when using the capsule treatment

Expansion animation:

- If AI adds content while the user is watching, the existing footer is pushed down by the height of the new content
- The new content should fade in with a `10px` vertical offset

## 10. Desired User Feeling

The user should feel:

- I can capture a thought before it disappears
- My unfinished ideas are still valuable here
- The app helps me think, not just store text
- My notes are gradually becoming a connected system
- AI is helping me move forward without taking control away from me

## 11. Open UX Questions

- How dense should the home canvas become before navigation support is needed? 
    - Design for about 15 cards before navigation is needed.
- Should note clusters be explicitly labeled or remain visually inferred?
    - Inferred until 15 cards.
- How much of note evolution should appear directly on cards versus inside detail view?
- Should the AI assistant stay docked in one place or adapt to user behavior?
- What is the best visual treatment for citations so they feel credible but lightweight?
- How should we show that background AI processing is happening without adding noise?

## 12. Key Page ASCII Mocks

The following mockups are not visual design specs. They are structural references aligned to the current Figma MVP layouts.

They intentionally preserve the existing sparse page composition:

- scattered rectangular cards on home
- open long-form page for new note
- open long-form page for full note

Additional product features should be layered into these layouts rather than replacing them with heavier containers.

All mocks assume a mobile-first product.

### 12.1 Home Canvas

Goals:

- Match the current Figma home layout as the base composition
- Keep the page feeling open, sparse, and non-document-like
- Use a mobile-friendly two-column structure rather than a fully freeform scatter
- Add product depth through card states and lightweight relationship cues

```text
+--------------------------------------------------+
|                                              [] |
|                                                  |
|   /------------------\    /------------------\  |
|  / 我发现老鼠真的会  /   / Start a thought.../  |
|  \ 打鼾             \   \ tap to capture   \   |
|   \        expanded  \   \                /    |
|    --------------------    ----------------     |
|                                                  |
|   /------------------\    /------------------\  |
|  / 以后或许人类最有  /   / 一个想法不一定对 /   |
|  \ 价值的工作是...  \   \ ：也许以后...    \   |
|   \         2 links  \   \        new src /    |
|    --------------------    ----------------     |
|                                                  |
|   /------------------\                           |
|  / 人类的工作类型将  /                           |
|  \ 会大变...        \                           |
|   \      responded   \                          |
|    --------------------                          |
|                                                  |
|                               (AI)               |
+--------------------------------------------------+
```

Notes:

- Preserve the existing Figma rhythm of generous whitespace, but organize notes into two readable columns
- Cards should feel anchored to approximate positions over time rather than drifting freely around the screen
- Reordering should be done via long-press and drag within the two-column system
- Slight card rotation should make the layout feel alive, but the structure should still read clearly as two vertical stacks
- The home canvas can still use grid morphing, but it should sit behind the layout and remain subtle
- Empty-card behavior should be expressed within the same rectangle language already used in Figma
- Background AI work should surface as tiny states on cards such as `expanded`, `2 links`, `new src`, not as bulky badges or panels
- The floating AI assistant remains a small persistent entry point in the lower-right zone
- Silent AI states may also appear as membrane pulsing, sage-green border bleed, or overlap fusion rather than explicit badges alone

### 12.2 New Note Page

Goals:

- Match the current Figma `new note` page structure
- Keep capture minimal and pressure-free
- Add save and AI behaviors without changing the open-page composition

```text
+--------------------------------------------------+
|                                            home |
|                                                  |
|  I might actually become a piano technician      |
|  in the future...                                |
|                                                  |
|                                                  |
|                                                  |
|                                                  |
|                                   auto-saving... |
|                                                  |
|                                                  |
|                                                  |
|  Delete                           Request        |
|                                   response       |
+--------------------------------------------------+
```

Notes:

- This should feel like an expanded card on an open sheet, not a separate compose product
- Keep the text anchored near the upper-left like the Figma layout
- `Request response` remains the explicit AI trigger in this MVP layout
- Save state, hint text, and future lightweight metadata should live in whitespace rather than inside extra modules
- The top-right icon is the return-to-home control
- It should not be represented as a back arrow or `x`, because the user is conceptually jumping back to the home canvas rather than stepping back in a stack
- The preferred motion is a shared-element transition from the home seed slot into this view

### 12.3 Note Full Page

Goals:

- Match the current Figma `full page` layout
- Keep the original note at the top as the anchor
- Layer in AI interpretation, attached knowledge, prompts, and growth status as simple text sections

```text
+--------------------------------------------------+
|                                            home |
|                                                  |
|  我发现老鼠真的会打鼾                            |
|                                                  |
|  updated since last visit: AI expanded          |
|  1 source added                                 |
|                                                  |
|  AI interpretation                               |
|  你的发现不无道理，1963年科学家发现了这个现象，  |
|  你可以把这个现象用来逗你家猫玩。                |
|                                                  |
|  Recent evolution                                |
|  AI responded yesterday                          |
|  source retrieved 2h ago                         |
|                                                  |
|                                                  |
|  Responses                                       |
|  1. 你为什么这么说                               |
|  2. 可我没有养老鼠                               |
|                                                  |
|  [ Ask a follow-up...                        ]   |
|                                                  |
|  [favicon|domain] [favicon|domain]              |
|                                                  |
|  ...                              Request        |
|                                   response       |
+--------------------------------------------------+
```

Notes:

- Keep the open vertical flow from the current Figma screen instead of introducing heavy cards
- Product richness should come from section order and micro-labels, not from a dashboard-like layout
- `updated since last visit` is the MVP-compatible version of the growth summary
- Source grounding should use lightweight fixed footnote capsules at the bottom of the scroll view
- These footnotes remain semantically attached to the AI response even if they are not rendered inline
- `Responses` should sit near the bottom of the page in the current layout
- The lower-left `...` button replaces `Delete` and can reveal additional note actions
- The top-right icon is a home action, not a dismiss or back control
- The full-page expansion should ideally feel like the card membrane inflating into the page background

### 12.4 Evolution Within The Same Layout

Goals:

- Show note growth without inventing a new page structure
- Let evolution appear as either a compact section lower on the note page or a utility-panel reveal
- Keep system and user changes visible but quiet

```text
+--------------------------------------------------+
|  Recent evolution                                |
|                                                  |
|  Today                                           |
|  - user edited original note                     |
|  - AI interpretation refreshed                   |
|                                                  |
|  Yesterday                                       |
|  - 2 related notes linked                        |
|  - 1 source retrieved                            |
|                                                  |
|  3 days ago                                      |
|  - note created from home canvas                 |
+--------------------------------------------------+
```

Notes:

- This is not a separate product mode for MVP; it is an extension of the existing note page
- Timeline entries should be compact and documentary
- Only the latest few events need to be shown initially

### 12.5 AI Assistant Overlay

Goals:

- Keep the assistant connected to the same sparse visual language
- Let it launch from the home floating button or the note page action flow
- Preserve the feeling that chat supports notes rather than replacing them

```text
+--------------------------------------------------+
| AI Assistant                                 x   |
|                                                  |
| You                                              |
| I think unfinished notes might be more useful    |
| than polished notes early on.                    |
|                                                  |
| Thinknote AI                                     |
| That may be because unfinished notes preserve    |
| generative ambiguity. Want 3 alternative angles? |
|                                                  |
| [Alternative angles] [Find sources] [Save note]  |
|                                                  |
| > Ask about this idea...                         |
+--------------------------------------------------+
```

Notes:

- The overlay should feel like a lightweight extension of the note system
- When opened from a note page, the current note should be the default context
- `Save note` or `Attach to note` should return outputs back into the same sparse layouts already defined above
