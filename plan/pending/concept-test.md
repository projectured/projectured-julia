# Concept Test — Measuring Impact of Pre-extracted Concepts

Empirically test whether pre-extracted Concept JSON files improve AI programming efficiency on a real task: implementing the SyntaxToWidget projection.

## Motivation

The concept-document plan argues that pre-extracted Concepts reduce token usage (~75% reduction in context-gathering) and improve quality (fewer missed constraints). These claims need validation before investing in extracting ~150+ concepts across the codebase.

The SyntaxToWidget plan is an ideal test case:
- Complex — touches projection system, widget layer, selection mapping, layout.
- Well-documented challenges — 8 architectural challenges (C1–C8) identified in `plan/pending/syntax-to-widget.md`, each requiring knowledge from different parts of the codebase.
- Fresh — no implementation exists yet, so both sessions start equal.
- Knowledge-scattered — the relevant constraints live in guides, done plans, and code comments across ~15 files.

## Test Design

### The task prompt

Give a fresh AI session this prompt:

> Implement Phase 1 of SyntaxToWidget — a projection that maps a single SyntaxNode to a WidgetComposite/WidgetTitlePane, with collapse/expand support. Start with DbCatalog as the test domain.

Don't give it the full syntax-to-widget plan — just the goal. The plan's 8 challenges serve as a scorecard: how many does the AI discover, and at what cost?

### Branch structure

```
database (current)
├── syntax-to-widget/control          ← Session A: no concepts, current setup
├── syntax-to-widget/concepts         ← extracted JSON files only, no implementation
│   ├── syntax-to-widget/preload-all      ← Session B1: all ~30 concepts upfront
│   ├── syntax-to-widget/preload-subject  ← Session B2: on-demand by subject
│   └── syntax-to-widget/preload-core     ← Session B3: core concepts only
```

The `concepts` branch holds the extracted JSON files but no SyntaxToWidget implementation. Each preload branch forks from it and tries a different retrieval strategy. The control branch forks directly from `database` with no concept files.

### Preload variants

| Branch | Strategy | What it tests |
|---|---|---|
| `control` | No concepts. CLAUDE.md + guides (current setup). | Baseline — how does the AI work today? |
| `preload-all` | Load all ~30 relevant concepts into context at session start. | Does brute-force loading help, or does it flood context with noise? |
| `preload-subject` | CLAUDE.md rule: "before touching a subsystem, glob `concepts/core/{subject}--*.json` and read the matches." | Is on-demand retrieval better than upfront loading? |
| `preload-core` | Load only `concepts/core/` (~10 invariants/decisions), skip regular concepts. | Is the small protected set of core knowledge sufficient? |

### Metrics

| Metric | How to measure | Why it matters |
|---|---|---|
| **Constraints discovered** | Count how many of C1–C8 the AI surfaces before or during implementation | Quality — missed constraints cause rework |
| **Discovery cost** | Tokens spent reading guides/code before writing any implementation code | Efficiency — pure overhead |
| **Course corrections** | Number of times the AI changes approach mid-implementation | Path directness |
| **Total tokens** | End-to-end to a working first version | Overall cost |
| **Irrelevant reads** | Files read that didn't contribute to the solution | Wasted exploration |
| **Time to first correct code** | Tokens from start to first compilable/testable output | Convergence speed |

### Concepts to extract (~30)

Based on the challenges documented in `syntax-to-widget.md`:

| Subject | Concepts | Covers challenge |
|---|---|---|
| `projection-system` | Delegation principle, one-level-only rule, recursion contract | C1 |
| `syntax-to-text` | Root-only navigation handler, gesture-aware readers, Alt+click tree selection | C2, C3 |
| `widget` | WidgetLabel vs WidgetText editability, box model rendering, `_push_box_rects!` contract | C4, C6 |
| `type-dispatching` | Mixed dispatch is intentional composition, TypeDispatchingProjection purpose | C5 |
| `component-document` | Component layer between Widget and Workbench, overlap with widget projections | C7 |
| `syntax` | Indentation is rendering hint not structural nesting, collapsed field semantics | C8 |
| `selection` | Three-step selection algorithm, ProjectionReference wrapping, shared Cell pattern | Selection mapping |
| `reactive-cells` | CellVector thunk pattern, reactive children wiring | Implementation |
| `conversation-to-widget` | Precedent for domain-to-widget projection, hybrid widget+text pattern | Implementation |

### Predictions

| Prediction | Rationale |
|---|---|
| All concept sessions discover C1 (delegation) before implementation | The concept is explicit; without it, the AI likely iterates children directly |
| Control session discovers C5 (hybrid pattern) late or not at all | Requires reading ConversationToWidget code + understanding the codebase convention |
| `preload-subject` outperforms `preload-all` on total tokens | Less noise in context; loads only what's relevant when it's relevant |
| `preload-core` matches `preload-all` on constraint discovery | Core invariants are the high-leverage knowledge; regular concepts add volume but not insight |
| Control session reads 2–3x more files than concept sessions | Must explore to find knowledge that concepts provide directly |

## Execution

### Phase 1: Extract concepts

Create ~30 JSON files in `concepts/core/` and `concepts/` on the `syntax-to-widget/concepts` branch. Each file follows the schema from `plan/pending/concept-document.md`. Source the content from:

1. `guide/projection-system.md` — delegation principle, recursion contract
2. `guide/selection-deep-dive.md` — three-step selection, ProjectionReference
3. `guide/design-decisions.md` — pull-based reactivity, every-field-is-Cell
4. `plan/done/syntaxtotext-delegation.md` or `plan/pending/syntaxtotext-delegation.md` — root-only navigation, gesture handling
5. `program/src/projection/primitive/ConversationToWidget.jl` — code comments on the hybrid pattern
6. `program/src/document/Widget.jl` — WidgetLabel vs WidgetText distinction
7. `program/src/projection/primitive/WidgetToGraphics.jl` — `_push_box_rects!` contract

### Phase 2: Configure CLAUDE.md variants

Each preload branch gets a different CLAUDE.md addition:

- `preload-all`: "Read all files in `concepts/` and `concepts/core/` at the start of every session."
- `preload-subject`: "Before modifying a subsystem, glob `concepts/core/{subject}--*.json` and `concepts/{subject}--*.json` and read the matches."
- `preload-core`: "Read all files in `concepts/core/` at the start of every session. Do not read `concepts/` unless explicitly asked."

### Phase 3: Run sessions

Run each session independently:
1. Fresh conversation, no prior context.
2. Same task prompt.
3. Let the AI work to completion (or until it produces a testable first version).
4. Save the full transcript for analysis.

### Phase 4: Analyze

Compare transcripts against the metrics table. For each session:
- List which of C1–C8 were discovered, and at what token offset.
- Count files read, tokens consumed, course corrections.
- Assess the resulting code: does it follow the delegation principle? Does it handle collapse? Does it wire selection correctly?

## Open Questions

- **Session variance.** AI sessions are non-deterministic. A single run per branch may not be representative. Running 2–3 sessions per branch would improve confidence but multiplies cost. Start with one run each; repeat only if results are ambiguous.
- **Concept quality matters more than quantity.** A poorly written concept that states the rule without the *why* may not help. The test also validates concept quality, not just the concept approach.
- **CLAUDE.md wording sensitivity.** The preload instruction in CLAUDE.md may significantly affect behavior. Small wording changes ("read at start" vs "check before modifying") could matter more than the concept content itself.
- **Fair comparison.** The control session has access to guides which contain the same knowledge (just buried in longer documents). The test measures retrieval efficiency, not knowledge availability.
