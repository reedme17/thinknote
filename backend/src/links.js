import { randomUUID } from "node:crypto";

const stopwords = new Set([
    "about",
    "after",
    "before",
    "their",
    "there",
    "would",
    "could",
    "should",
    "because",
    "through",
    "think",
    "idea",
    "note",
    "notes"
]);

export function buildRelatedLinks(targetNote, allNotes, limit = 4) {
    const targetTerms = tokens(targetNote.rawText || targetNote.text);

    return allNotes
        .filter((note) => note.id !== targetNote.id)
        .map((note) => {
            const otherTerms = tokens(note.rawText || note.text);
            const overlap = intersect(targetTerms, otherTerms);
            const unionSize = new Set([...targetTerms, ...otherTerms]).size || 1;
            const confidence = Number((overlap.size / unionSize).toFixed(2));
            return {
                id: randomUUID(),
                noteId: note.id,
                title: note.title,
                relationship: classifyRelationship(targetTerms, otherTerms, overlap),
                confidence,
                summary: overlap.size > 0 ? `Shared themes: ${Array.from(overlap).slice(0, 4).join(", ")}` : "Potential conceptual connection"
            };
        })
        .filter((link) => link.confidence > 0)
        .sort((left, right) => right.confidence - left.confidence)
        .slice(0, limit);
}

function classifyRelationship(targetTerms, otherTerms, overlap) {
    const tensionMarkers = ["not", "never", "against", "oppose", "tension", "conflict"];
    const targetHasTension = tensionMarkers.some((term) => targetTerms.has(term));
    const otherHasTension = tensionMarkers.some((term) => otherTerms.has(term));

    if (targetHasTension !== otherHasTension && overlap.size > 0) {
        return "tension";
    }

    return overlap.size >= 3 ? "shared theme" : "complementary";
}

function tokens(text) {
    return new Set(
        String(text || "")
            .toLowerCase()
            .split(/[^a-z0-9]+/)
            .filter((part) => part.length >= 3 && !stopwords.has(part))
    );
}

function intersect(left, right) {
    const result = new Set();
    for (const item of left) {
        if (right.has(item)) {
            result.add(item);
        }
    }
    return result;
}
