# Thinknote MVP Note Display Logic

Date: 2026-05-14

## Purpose

This document records the current MVP decision for how a note should appear across three surfaces:

- `A`: home card text
- `B`: full page title / thought line
- `C`: first AI-grown paragraph in note detail

The goal is to keep capture simple, preserve the user's first thought, and make AI growth feel like a second layer rather than a rewrite-heavy note editor.

## Core Rule

The user’s note should behave as a two-stage object:

1. a short visible thought that appears in both home and detail
2. a deeper AI-grown body that appears later as an added layer

In other words:

- `A` and `B` should usually stay aligned
- `C` is where AI starts to elaborate
- AI should not turn the note into a long card headline plus another unrelated title plus another unrelated paragraph

## Stage 1: First Capture

When the user first types a note:

- the user-entered note appears in `A`
- the same text appears in `B`
- `C` does not exist yet

This means:

- home card shows the raw captured thought
- opening the note shows the same short thought as the main line
- there is no AI body yet

The first capture should feel light and direct.

## Stage 2: Deferred AI Growth

When the user comes back later and the note has grown:

- `A` updates into an AI-polished short form
- `B` becomes the same string as `A`
- `C` appears as the first AI-grown paragraph

Important constraints:

- the updated `A` must remain short enough to fully fit in the card without ellipsis
- the updated `A` should stay as close as possible to the original captured thought
- the AI’s main elaboration should move into `C`, not bloat `A`

This creates the intended structure:

- `A`: concise card-ready idea
- `B`: the same concise idea in detail
- `C`: the AI’s first meaningful expansion

## Product Intent

This logic exists to prevent three common failures:

1. the card becoming too long and truncating
2. the detail opening with a different sentence than the card
3. AI rewriting the top line too aggressively instead of growing the body underneath it

The product should feel like:

- the note got slightly sharper at the top
- the real growth happened below

Not like:

- the system replaced the note with a different mini-essay

## Content Model Guidance

For MVP, the intended mapping is:

- `A` uses the display summary for the card
- `B` uses the same display summary in detail
- `C` is the first AI-grown paragraph

Conceptually:

- initial state: `A == B`, no `C`
- grown state: `A == B`, and `C` appears

## Template Guidance

Templates should reflect this logic clearly:

- a `growing` template note should have matching `A` and `B`, with no `C`
- a `grown` template note should have matching `A` and `B`, plus one or more AI-grown paragraphs in `C`

Template notes should avoid:

- a long title in `A`
- a different sentence in `B`
- a card summary that already contains the whole AI body

## Summary

The MVP note reading model is:

- capture produces one short visible thought
- later growth sharpens that thought slightly
- deeper AI content appears below as body paragraphs

The product should preserve one clean top-line idea and let AI growth accumulate underneath it.
