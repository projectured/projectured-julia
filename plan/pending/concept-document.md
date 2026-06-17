# Concept Document — Structured Semantic Knowledge Layer

An AI-native knowledge layer where architectural intent, design decisions, lessons, and reasoning are captured as small, atomic `Concept` documents — independent from executable artifacts and optimized for machine retrieval and reasoning.

## Context

Large documentation files (guides, architecture docs) work for human readers but are inefficient for AI reasoning. An AI solving a specific problem rarely needs an entire design document — it benefits from retrieving many small, focused knowledge units that can be dynamically combined.

A `Concept` is a specialized `Document`. It inherits every capability of the document system: versioned, linkable, projectable, searchable, editable, traceable. Concepts participate in the same projection system as every other document.

The full knowledge-layer stack:

| Layer | What it is | Examples |
|-------|-----------|----------|
| Executable artifact | Source code, projections, tests | `JsonToSyntax.jl`, `Reactive.jl` |
| Guide | Human-readable documentation | `guide/concepts.md`, `guide/architecture.md` |
| Concept | Atomic semantic knowledge unit | Purpose, Invariant, DesignDecision, Lesson |
| Plan | Implementation-oriented task description | `plan/pending/*.md` |

Concepts fill the gap between guides (written for humans, organized by page) and code (which captures *what* but not *why*). A Concept answers exactly one semantic question:

- Why does this exist?
- What invariant does this guarantee?
- When should this be used / not used?
- Why was this design chosen over alternatives?
- What tradeoff does this represent?
- What lesson was learned?

If a Concept answers multiple independent questions, it should be decomposed.

## Design Decisions

### Concept is a Document subtype

Concept inherits from `Document`, gaining cells, projections, selections, and the full editor pipeline for free. No new plumbing needed.

### Flat start — no relationship graph

Start without semantic edges (`motivated-by`, `demonstrates`, `alternative-to`). A relationship graph sounds elegant but risks becoming a maintenance burden — stale edges are worse than no edges. Add relationships only when retrieval actually demands them.

### Single type — no subclass hierarchy yet

Start with just `Concept` rather than defining 15 subtypes (Purpose, Invariant, DesignDecision, Tradeoff, Lesson, AntiPattern, ...). Let categories emerge from actual usage. A `kind::String` field is sufficient for tagging until a real taxonomy proves necessary.

### AI-first lifecycle with human review

Typical lifecycle:

1. AI performs work on the codebase.
2. AI reflects on what was learned.
3. AI extracts a Concept (one semantic question, one answer).
4. Human reviews or the Concept is flagged as AI-generated/unreviewed.
5. Future AI sessions retrieve relevant Concepts.

AI-generated knowledge tends toward the generic ("this module handles X") rather than the genuinely useful ("we tried Y and it failed because Z"). A `confidence` or `reviewed` flag helps distinguish validated knowledge from speculative extraction.

## Implemented

Nothing yet.

## TODO

### Phase 1: JSON files in the repo

Store Concepts as plain JSON files in a `concepts/` directory at the repo root. No new Julia code needed — just files.

**Directory:** `concepts/`

Each Concept is a single `.json` file:

```json
{
    "title": "Why projections must be bidirectional",
    "kind": "invariant",
    "body": "Every printer needs a matching reader because the editor must map user actions back to the domain. A one-way projection creates a read-only view, which breaks the editing contract.",
    "subject": "projection-system",
    "confidence": "verified",
    "created_by": "human"
}
```

Schema:

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | The semantic question answered — short, specific |
| `kind` | string | Freeform tag: `"purpose"`, `"invariant"`, `"decision"`, `"lesson"`, `"tradeoff"`, `"antipattern"`, etc. |
| `body` | string | The answer — a few sentences, not a page |
| `subject` | string | What this is about: a module, projection, design area, or file |
| `confidence` | string | `"verified"`, `"unreviewed"`, or `"speculative"` |
| `created_by` | string | `"human"` or `"ai"` |

File naming convention: `concepts/{subject}--{slug}.json` (e.g. `concepts/projection-system--bidirectional-invariant.json`). The `--` separator makes subject-based filtering trivial with glob patterns.

Benefits of starting with JSON:
- Version-controlled with git — diffs, blame, history for free.
- LLMs can read and write JSON natively — no parsing infrastructure needed.
- Greppable: `grep -r '"kind": "lesson"' concepts/` works today.
- No Julia code to maintain until there's a reason to project them in the editor.
- Easy to bulk-load into a Document later when the editor-side is ready.

### Phase 2: Maintenance workflow

When code changes, relevant Concepts should be reviewed:

1. AI or human makes a code change.
2. Check if any Concept's `subject` overlaps with the changed files/modules.
3. Update or delete stale Concepts. Git tracks the change.

This is a manual/AI-assisted process — no automation needed yet.

### Phase 3: ConceptConcept document type (deferred)

When the collection is large enough to benefit from in-editor browsing, introduce the Document subtype:

**File:** `program/src/document/Concept.jl`

```julia
@document ConceptConcept begin
    title::String
    kind::String
    body::String
    subject::String
    confidence::Symbol      # :verified, :unreviewed, :speculative
    created_by::Symbol      # :human, :ai
end
```

A reader/loader parses the JSON files into `ConceptConcept` documents. The JSON files remain the source of truth; the Document is a projection of them.

### Phase 4: ConceptToSyntax projection (deferred)

**File:** `program/src/projection/primitive/ConceptToSyntax.jl`

Printer maps `ConceptConcept` to a `SyntaxNode` tree. Reader maps edits back. The pipeline reuses `SyntaxToText → TextToGraphics`.

Only build this when there's a reason to view/edit Concepts inside ProjecturEd rather than in a text editor.

### Phase 5: Concept browser example (deferred)

A workbench pane that loads the `concepts/` directory, filters by kind/subject, and displays selected Concepts. Uses `ComponentMasterDetail` if available.

## Open Questions

- **What's worth a Concept?** Not every observation deserves an entry. A useful filter: would a future AI session make a better decision if it had this knowledge? If the answer is "probably not" or "it could figure this out from the code", skip it.
- **Interaction with guides.** Guides and Concepts overlap in content. They coexist: guides are the curated human view, Concepts are the raw AI memory. Guides may eventually be generated from Concepts, but that's not needed to start.
- **Staleness.** Code changes but Concepts may not. A Concept referencing a deleted function is actively harmful. The `subject` field helps — when a module changes, grep for Concepts with that subject and review them.
- **When to graduate to Documents.** The JSON-files-in-repo approach works as long as the collection is small (< ~200) and read/write happens outside the editor. If Concepts need to be browsed, filtered, or edited inside ProjecturEd, that's the signal to build the Document type and projections (Phases 3–5).
