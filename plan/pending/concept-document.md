# Concept Document — Structured Semantic Knowledge Layer

An AI-native knowledge layer where architectural intent, design decisions, lessons, and reasoning are captured as small, atomic `Concept` documents — independent from executable artifacts and optimized for machine retrieval and reasoning.

## Vision

The concept system serves two timescales:

**Near-term: accelerate development.** Pre-extracted concepts reduce token waste and prevent missed constraints during AI-assisted programming on this codebase. The AI loads relevant concepts before working, makes fewer mistakes, and takes more direct paths to solutions.

**Long-term: self-maintaining knowledge for end users.** ProjecturEd as a shipped application maintains its own concept base. When a user asks the AI agent to solve a problem — edit a document, build a projection pipeline, configure a workbench — the agent consults the application's concepts to understand what's possible, what constraints apply, and what patterns to follow. As the agent works, it reflects on what it learned and writes new concepts back. The knowledge base grows with usage.

This means the concept system must eventually support:

| Capability | Near-term (dev tool) | Long-term (application feature) |
|---|---|---|
| **Who writes concepts** | Developer + AI during development | The application's AI agent during user sessions |
| **Who reads concepts** | AI during development sessions | AI agent solving user problems |
| **Scope** | One repo's architecture | Per-user or per-project knowledge |
| **Lifecycle** | Manual review, git-tracked | Automatic creation, confidence-based retention |
| **Core concepts** | Curated by owner, protected | Shipped with the application, read-only for the agent |
| **Regular concepts** | AI-maintained, reviewed periodically | Agent-created, user-reviewable, prunable |

The near-term phases (1–3) build the infrastructure. The long-term phases (4–6) project concepts as Documents inside the editor, which is the prerequisite for the application to manage its own knowledge base — concepts become first-class editable objects in the same system that edits JSON, XML, SQL, and every other domain.

The progression is natural: JSON files in a repo → Documents in the editor → a self-maintaining knowledge layer that learns from every session.

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

**⚠ This estimate is optimistic.** The comparison assumes the AI reads *only* concepts and nothing else. In practice, even with perfect concepts, the AI still needs to read actual source code to understand the current implementation before modifying it. Concepts tell you *what constraints exist*, not *what the code currently looks like*. The honest comparison is (guides + code reading) vs (concepts + code reading) — the code-reading portion is identical. Real savings are probably ~30–50% of context-gathering overhead, not 75%. The 75% figure holds only for the guide-reading portion.

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
| `subject` | string or array | What this is about: a module, projection, design area, or file. Use an array for cross-cutting concepts (e.g. `["selection", "projection-system"]`). |
| `confidence` | string | `"verified"`, `"unreviewed"`, or `"speculative"` |
| `created_by` | string | `"human"` or `"ai"` |
| `status` | string | `"active"` (default) or `"deprecated"`. Deprecated concepts include a `"superseded_by"` note in the body. |

**⚠ Subject must support cross-cutting concepts.** Many high-value invariants span subsystems — e.g., "selection mapping through projections" touches `selection`, `projection-system`, and the specific projection. A single-string `subject` means FILE_MAP lookups miss these concepts for all but one subsystem. Making `subject` an array (or accepting both string and array) ensures cross-cutting concepts surface in all relevant contexts.

File naming convention: `concepts/{subject}--{slug}.json` (e.g. `concepts/projection-system--bidirectional-invariant.json`). The `--` separator makes subject-based filtering trivial with glob patterns.

Benefits of starting with JSON:
- Version-controlled with git — diffs, blame, history for free.
- LLMs can read and write JSON natively — no parsing infrastructure needed.
- Greppable: `grep -r '"kind": "lesson"' concepts/` works today.
- No Julia code to maintain until there's a reason to project them in the editor.
- Easy to bulk-load into a Document later when the editor-side is ready.

### Phase 2: Retrieval infrastructure

The retrieval problem is what makes or breaks the concept approach. The AI needs to find the right concepts at the right time without loading everything or missing critical constraints. A layered approach, from lightest to heaviest:

**⚠ Complexity risk.** Four retrieval layers (INDEX.json, FILE_MAP.json, bundles, source annotations) means four mechanisms to maintain, four places for staleness, and four things to explain in CLAUDE.md. Consider validating Phase 1 with just the naming convention (`{subject}--{slug}.json`) + glob first. If glob-based retrieval proves insufficient, *then* add the heavier layers. The concept-test plan actually tests the simpler glob approach — if that works, much of this infrastructure may be unnecessary overhead.

#### Layer 1: INDEX.json (always loaded)

**File:** `concepts/INDEX.json`

A lightweight manifest listing every concept with title, kind, and subject — no body. At ~15 tokens per entry, 150 concepts cost ~2,000 tokens. The AI always knows what exists and can pick what to deep-read.

```json
[
    {"file": "core/projection-system--delegation-principle.json", "title": "Projections must delegate children to recursion", "kind": "invariant", "subject": "projection-system"},
    {"file": "core/selection--three-step-algorithm.json", "title": "Three-step selection mapping algorithm", "kind": "pattern", "subject": "selection"}
]
```

CLAUDE.md rule: "Read `concepts/INDEX.json` at the start of every session."

**⚠ Staleness risk.** INDEX.json is a centralized manifest that must be regenerated whenever concepts are added, removed, or renamed. Unlike source annotations (Layer 4) that live with the code, this file rots invisibly. The lint script mentioned in "What to borrow" should be a Phase 2 gate requirement, not a nice-to-have — without it, a stale INDEX is worse than no INDEX.

#### Layer 2: FILE_MAP.json (auto-triggered)

**File:** `concepts/FILE_MAP.json`

Maps source files to relevant concept subjects. When the AI is about to modify a file, it looks up which subjects apply and loads the matching concepts automatically.

```json
{
    "program/src/projection/primitive/SyntaxToText.jl": ["projection-system", "syntax", "selection", "text"],
    "program/src/projection/primitive/WidgetToGraphics.jl": ["widget", "graphics", "layout"],
    "program/src/document/Widget.jl": ["widget"]
}
```

CLAUDE.md rule: "Before modifying a source file, look up its entry in `concepts/FILE_MAP.json` and read all concepts matching the listed subjects."

This is the equivalent of Cursor Rules' glob-based auto-scoping, but tool-agnostic and explicit.

**⚠ Same staleness risk as INDEX.json.** When someone adds a new `.jl` file or renames a module, FILE_MAP.json doesn't update itself. A stale FILE_MAP is worse than no FILE_MAP — the AI trusts it and misses concepts for the file it's about to modify. The lint script must validate FILE_MAP entries against existing source files.

#### Layer 3: Task bundles (task-scoped)

**Directory:** `concepts/bundles/`

Pre-composed concept sets for common task types. Instead of querying, load one bundle file that lists all relevant concept paths.

```json
{
    "description": "All concepts needed when creating a new projection",
    "concepts": [
        "core/projection-system--delegation-principle.json",
        "core/projection-system--four-interface-functions.json",
        "core/selection--three-step-algorithm.json",
        "core/selection--projection-reference-wrapping.json",
        "core/reactive-cells--cell-vector-thunk-pattern.json"
    ]
}
```

Example bundles:
- `bundles/new-projection.json` — creating a projection
- `bundles/selection-mapping.json` — wiring selection/reference
- `bundles/new-domain.json` — adding a new document domain

CLAUDE.md rule: "When starting a common task type, check `concepts/bundles/` for a matching bundle."

#### Layer 4: Source-file annotations (fallback)

For files not yet in FILE_MAP, a comment at the top of key source files points to relevant concepts:

```julia
# @concepts projection-system--delegation-principle, syntax--indentation-is-rendering-hint
```

When the AI reads a source file, it sees which concepts apply and can load them. This keeps the mapping close to the code — less likely to go stale than a separate map file.

#### Kind-based queries

Different phases of work benefit from different concept kinds:

| Task phase | Useful kinds |
|---|---|
| Planning | `decision`, `tradeoff`, `purpose` |
| Implementing | `invariant`, `pattern`, `constraint` |
| Debugging | `lesson`, `antipattern`, `invariant` |

The AI can filter the INDEX by kind to load phase-appropriate knowledge. E.g., before implementing, load all `invariant` concepts for the relevant subjects.

#### Token budget summary

| Layer | Tokens | When loaded |
|---|---:|---|
| INDEX.json | ~2,000 | Every session |
| FILE_MAP lookup + matched concepts | ~500–1,500 | Before modifying a file |
| Task bundle | ~1,000–2,000 | At task start |
| Source annotations | ~0 (read with file) | When reading source |
| **Typical session total** | **~3,000–5,000** | |

Compared to the current approach (~8,000–15,000 tokens reading guides), this is a ~60–75% reduction with higher signal-to-noise.

### Phase 3: Maintenance workflow

When code changes, relevant Concepts should be reviewed:

1. AI or human makes a code change.
2. Check if any Concept's `subject` overlaps with the changed files/modules.
3. Update or delete stale Concepts. Git tracks the change.

This is a manual/AI-assisted process — no automation needed yet.

**⚠ Missing: concept creation during work.** Neither Phase 1 nor Phase 3 addresses what happens when the AI discovers a new constraint *during* implementation. Does it stop and write a concept? Note it for later? The long-term vision says "the agent reflects and writes concepts back," but there's no near-term mechanism for this. Consider adding a CLAUDE.md rule: "After completing a task, if you learned something non-obvious, propose a new concept."

### Phase 4: ConceptConcept document type (deferred)

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

### Phase 5: ConceptToSyntax projection (deferred)

**File:** `program/src/projection/primitive/ConceptToSyntax.jl`

Printer maps `ConceptConcept` to a `SyntaxNode` tree. Reader maps edits back. The pipeline reuses `SyntaxToText → TextToGraphics`.

Only build this when there's a reason to view/edit Concepts inside ProjecturEd rather than in a text editor.

### Phase 6: Concept browser example (deferred)

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

## Alternatives Considered

A survey of existing tools (June 2026) for building AI-agent knowledge bases.

### Karpathy's LLM Wiki pattern (April 2026)

The closest match to this plan. Three-layer architecture: `raw/` (immutable sources), `wiki/` (LLM-generated structured markdown pages), and a schema in CLAUDE.md. The LLM incrementally compiles raw material into structured wiki pages, maintains cross-references, and lints for consistency. Open-source implementation exists for Claude Code and Cursor.

**Pros:**
- Auto-compilation from raw sources — drop in documents, the LLM extracts and structures knowledge.
- Citation tracking back to source material.
- Built-in lint step that checks for staleness and contradictions.
- Active community, 5,000+ stars within days of release.

**Cons:**
- Free-form markdown wiki pages — less structured and queryable than schema-constrained JSON.
- Designed for raw/unstructured source ingestion. Our sources (guides, plans) are already structured, so the compilation step adds complexity without proportional value.
- No `kind`, `subject`, `confidence` fields — harder to filter by topic or trust level.

**Verdict:** The lint/validation idea is worth borrowing. The compilation pipeline is overkill for our already-structured sources.

*References: [Karpathy's LLM Wiki](https://www.aibuilderclub.com/blog/karpathy-llm-wiki), [GitHub implementation](https://github.com/Astro-Han/karpathy-llm-wiki), [LLM Wiki v2 extensions](https://gist.github.com/rohitg00/2067ab416f7bbe447c1977edaaa681e2)*

### Packmind

Enterprise platform that captures an engineering playbook and generates context files for every AI tool (`.claude/rules/`, `.cursor/rules/`, `.github/instructions/`). Full ContextOps lifecycle: Build, Distribute, Govern, Maintain. Open-source core, paid enterprise tier with drift detection and RBAC.

**Pros:**
- Multi-tool distribution — one source of truth, generated files for Claude Code, Cursor, Copilot, Codex.
- Drift detection linter — automatically detects when AI-generated code diverges from standards.
- Team governance features — SSO, RBAC, approval workflows for rule changes.

**Cons:**
- Designed for team-wide coding standards, not project-specific semantic knowledge (invariants, design decisions, lessons).
- Heavy for single-developer, single-repo use — the governance layer adds overhead without benefit.
- Focus is on enforcement ("code your way"), not knowledge retrieval ("what constraints apply here").

**Verdict:** Useful if Concepts ever need to be distributed across multiple repos or teams. Overkill for the current single-project scope.

*References: [Packmind](https://packmind.com/), [GitHub](https://github.com/PackmindHub/packmind), [Context engineering tools comparison](https://packmind.com/context-engineering-ai-coding/best-context-engineering-tools/)*

### Cursor Rules (.cursor/rules/)

Directory of `.mdc` files with YAML frontmatter and glob-based scoping. Rules load automatically based on which files are being edited — e.g., a rule scoped to `src/projection/**` loads only when touching projection files.

**Pros:**
- Conditional loading by file glob — the right context activates for the right task without manual selection.
- Already a de facto standard for Cursor users; well-documented patterns.
- Lightweight — just files in a directory with frontmatter.

**Cons:**
- Cursor-specific — doesn't work with Claude Code, Copilot, or other tools without adaptation.
- Scoping is file-path-based, not semantic — can't scope by concept `kind` or `subject` without mapping those to file paths.
- No schema enforcement — rules are free-form markdown, quality varies.

**Verdict:** The glob-based conditional loading is the key insight. Our `concepts/core/{subject}--*.json` naming convention already provides this — `glob concepts/core/projection-system--*.json` achieves the same targeted loading without tool-specific infrastructure.

*References: [awesome-cursorrules](https://github.com/PatrickJS/awesome-cursorrules), [Context management for Cursor](https://datalakehousehub.com/blog/2026-03-context-management-cursor/)*

### Comparison summary

| | Our JSON approach | Karpathy LLM Wiki | Packmind | Cursor Rules |
|---|---|---|---|---|
| **Format** | Schema-constrained JSON | Free-form markdown | Playbook → generated files | Markdown + YAML frontmatter |
| **Queryable by subject/kind** | Yes (filename + fields) | Manual cross-references | Tag-based | Glob on file path |
| **Tool-agnostic** | Yes | Yes (file-based) | Yes (multi-tool output) | Cursor only |
| **Auto-compilation** | No (manual/AI-assisted) | Yes | Yes | No |
| **Staleness detection** | Manual (grep by subject) | Built-in lint | Drift detection | No |
| **Overhead** | Minimal (just files) | Medium (raw + wiki layers) | High (platform) | Low (just files) |
| **Fits our scale** | Yes | Partially | No | Partially |

### What to borrow

From the alternatives, two ideas are worth incorporating without adopting the tools themselves:

1. **Lint/validation step** (from Karpathy): A simple script that checks for broken `subject` references (does the module still exist?), duplicate concepts, and concepts with `confidence: "speculative"` older than N days. No framework needed — just a Julia or shell script.

2. **Glob-based conditional loading** (from Cursor Rules): Already designed into the naming convention (`{subject}--{slug}.json`). The CLAUDE.md instruction "glob by subject before modifying a subsystem" is the equivalent of Cursor's auto-scoping.

## Open Questions

- **What's worth a Concept?** Not every observation deserves an entry. A useful filter: would a future AI session make a better decision if it had this knowledge? If the answer is "probably not" or "it could figure this out from the code", skip it.
- **Interaction with guides.** Guides and Concepts overlap in content. They coexist: guides are the curated human view, Concepts are the raw AI memory. Guides may eventually be generated from Concepts, but that's not needed to start.
- **Staleness.** Code changes but Concepts may not. A Concept referencing a deleted function is actively harmful. The `subject` field helps — when a module changes, grep for Concepts with that subject and review them.
- **When to graduate to Documents.** The JSON-files-in-repo approach works as long as the collection is small (< ~200) and read/write happens outside the editor. The signal to graduate is *not* "concepts need to be browsed" — every JSON file can already be browsed via JsonToSyntax. The real signals are: "concepts need to participate in projections that reference other documents" or "the AI agent needs to create concepts during a user session without git." Don't graduate prematurely.
- **The test may prove Phase 2 unnecessary.** If the concept-test shows that simple glob-by-subject works well enough, the retrieval infrastructure (INDEX.json, FILE_MAP.json, bundles) adds maintenance cost without proportional value. Let the test results inform whether Phase 2 is needed at all.
