# Concept Document — Structured Semantic Knowledge Layer

An AI-native knowledge layer where architectural intent, design decisions, lessons, and reasoning are captured as small, atomic `Concept` documents — independent from executable artifacts and optimized for machine retrieval and reasoning.

## Why This Matters

### The token economics problem

An AI working on this codebase currently gathers context by reading guides, plans, and grepping code comments. For a typical task like "modify a projection's reader":

| What the AI reads | Lines | ~Tokens | Actually useful |
|---|---:|---:|---:|
| `guide/projection-system.md` | 563 | ~3,000 | ~300 tokens (~10%) |
| `guide/selection-deep-dive.md` | 292 | ~1,500 | ~200 tokens |
| `guide/macros.md` | 135 | ~700 | ~100 tokens |
| A relevant done plan | ~300 | ~1,500 | ~200 tokens |
| Grep/explore to find the right files | — | ~2,000 | — |
| **Total context-gathering** | | **~8,700** | **~800 useful** |

That's roughly 10% signal, 90% noise — ~8,700 tokens read to extract ~800 tokens of actionable knowledge. And the AI might still miss a design decision buried in paragraph 47 of a guide.

With pre-extracted Concepts, the same task loads only what's relevant:

| What the AI reads | Files | ~Tokens |
|---|---:|---:|
| `concepts/core/projection-system--*.json` | ~8 | ~1,200 |
| `concepts/core/selection--*.json` | ~4 | ~600 |
| `concepts/core/macros--*.json` | ~2 | ~300 |
| **Total** | **~14** | **~2,100** |

That's a ~75% reduction in context-gathering tokens, with signal-to-noise near 100%.

### Quality improvement is the bigger payoff

Per-task token savings (~5,000–7,000) are nice but not transformative alone. The real wins:

**Fewer mistakes.** Currently the AI can miss an invariant it didn't know to look for. With tagged Concepts, a simple `glob concepts/core/projection-system--*.json` surfaces all invariants for that area. No constraint gets skipped because it was buried in a 500-line guide. One prevented mistake saves more tokens than 20 sessions of reduced reading — a missed invariant can cost 10,000–30,000 tokens to debug and fix.

**No repeated research across sessions.** Every new conversation starts from zero — re-reads the same guides, rediscovers the same design decisions. Over 10 sessions touching projections, that's ~50,000–70,000 tokens of redundant reading eliminated.

**Faster convergence on complex tasks.** Multi-step tasks (new domain, new projection pipeline) currently require 3–5 rounds of "read, try, discover a constraint, re-read." With Concepts, the constraints are front-loaded.

### Summary

| | Without Concepts | With Concepts |
|---|---|---|
| Context-gathering per task | ~8,000–15,000 tokens | ~2,000–3,000 tokens |
| Risk of missing a constraint | Medium–high | Low |
| Cross-session redundancy | Full re-read every time | Zero for extracted knowledge |
| Estimated saving over 10 sessions | — | ~50,000–100,000 tokens |

### Core vs. regular Concepts

Not all Concepts are equal. A small set of **core** Concepts encode invariants, design decisions, and constraints that are always true and rarely change — the foundational knowledge that, if violated, causes cascading mistakes. These need protection:

- Core Concepts live in `concepts/core/` with `"protected": true`.
- Regular Concepts live in `concepts/` with `"protected": false` (or field omitted).
- CLAUDE.md rule: "Never create, modify, or delete files in `concepts/core/` unless the user explicitly asks. These are owner-curated concepts."
- The AI can freely create/update/delete unprotected Concepts as part of its normal workflow.

Core Concepts are prepared once and only change when the owner asks. Regular Concepts are living knowledge that the AI maintains as the codebase evolves.

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

## Volume Estimate

An audit of the existing repo content estimated how many Concept JSON files could be extracted from current sources.

### Source material

| Source | Files | Lines |
|--------|------:|------:|
| Guides (`guide/`) | 32 | ~5,800 |
| Plans (`plan/`) | ~97 | ~24,700 |
| Code comments (`.jl`) | ~210 | ~4,000 comment lines |

### Estimated Concept yield

Two granularity levels: *conservative* counts only design rationale, invariants, tradeoffs, and lessons — knowledge an AI couldn't derive from the code alone. *With patterns & invariants* also includes architectural patterns, DSL rules, and operational semantics that are documented in comments but not obvious from code structure.

| Source | Conservative | With patterns & invariants |
|--------|------:|------:|
| Guides | 80–120 | 300–400 |
| Plans | 100–150 | 480–800 |
| Code comments | 130–165 | 130–165 |
| Cross-cutting | 15–25 | 30–50 |
| **Total** | **~325–460** | **~940–1,415** |

Code comments were surprisingly rich — the reference DSL (`ReferenceCase.jl`, `ReferenceBuilder.jl`) alone encodes ~40 distinct semantic rules, and projection files contain ~30–40 architectural patterns documented in "why" comments.

### Recommended first batch: ~150

Target the highest-value sources first:

1. `guide/design-decisions.md` — ~10 concepts, already distilled
2. Done plans with "Design Decisions" sections (~32 plans have them) — ~60–80 concepts
3. Code comments in ReferenceCase/ReferenceBuilder — ~20 concepts (DSL rules)
4. `guide/projection-system.md` + `guide/selection-deep-dive.md` — ~25 concepts
5. Cross-cutting invariants (bidirectionality, 1-based indexing, pull-based reactivity) — ~15 concepts

This fits comfortably in the JSON-files-in-a-directory approach. At ~325–460 total conservative concepts, even a full extraction stays within the "no database needed" range.

## Open Questions

- **What's worth a Concept?** Not every observation deserves an entry. A useful filter: would a future AI session make a better decision if it had this knowledge? If the answer is "probably not" or "it could figure this out from the code", skip it.
- **Interaction with guides.** Guides and Concepts overlap in content. They coexist: guides are the curated human view, Concepts are the raw AI memory. Guides may eventually be generated from Concepts, but that's not needed to start.
- **Staleness.** Code changes but Concepts may not. A Concept referencing a deleted function is actively harmful. The `subject` field helps — when a module changes, grep for Concepts with that subject and review them.
- **When to graduate to Documents.** The JSON-files-in-repo approach works as long as the collection is small (< ~200) and read/write happens outside the editor. If Concepts need to be browsed, filtered, or edited inside ProjecturEd, that's the signal to build the Document type and projections (Phases 3–5).
