# Concept Test — Measuring Impact of Pre-extracted Concepts

Empirically test whether pre-extracted Concept JSON files improve AI programming efficiency on a real task: implementing the SyntaxToWidget projection.

## Motivation

The concept-document plan argues that pre-extracted Concepts reduce token usage (~75% reduction in context-gathering) and improve quality (fewer missed constraints). These claims need validation before investing in extracting ~150+ concepts across the codebase.

The SyntaxToWidget plan is an ideal test case:
- Complex — touches projection system, widget layer, selection mapping, layout.
- Well-documented challenges — 8 architectural challenges (C1–C8) identified in `plan/pending/syntax-to-widget.md`, each requiring knowledge from different parts of the codebase.
- Fresh — no implementation exists yet, so both sessions start equal.
- Knowledge-scattered — the relevant constraints live in guides, done plans, and code comments across ~15 files.

**⚠ This is a pilot, not a statistically valid experiment.** With N=1 per branch and high AI session variance, the results are anecdotal. The first round establishes whether the approach is *plausible*, not whether it *works*. If results are ambiguous, a second round (2–3 runs per branch) is needed to distinguish concept impact from session luck. Name it accordingly in any writeup.

**⚠ Cost of the test itself.** Running 4+ AI sessions to completion on a complex task isn't cheap. Each session could consume 100,000–300,000 tokens. With the analysis phase on top, the test might cost more tokens than the first year of concept-based savings. Worth doing for validated learning, but budget ~500,000–1,200,000 tokens for the full experiment.

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

**⚠ Confounding variable: CLAUDE.md differences.** The concept branches add retrieval instructions to CLAUDE.md that the control branch doesn't have. This means you're testing "concepts + CLAUDE.md instructions" vs "no concepts + no instructions," not concepts alone. To isolate the concept variable, the control branch should have equivalent-length CLAUDE.md additions that point to guides instead (e.g., "Before modifying a projection, read `guide/projection-system.md`"). Otherwise positive results might be attributable to the instructions, not the concepts.

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
| **Constraints discovered** | Count how many of C1–C8 the AI surfaces before or during implementation | Quality — missed constraints cause rework. ⚠ *Mentioning* a constraint ≠ *correctly applying* it — also check the resulting code. |
| **Discovery cost** | Tokens spent reading guides/code before writing any implementation code | Efficiency — pure overhead |
| **Course corrections** | Number of times the AI changes approach mid-implementation (⚠ see JSONL note below) | Path directness |
| **Total tokens** | End-to-end to a working first version | Overall cost |
| **Irrelevant reads** | Files read that didn't contribute to the solution | Wasted exploration |
| **Time to first correct code** | Tokens from start to first compilable/testable output | Convergence speed |
| **Rework after first version** | Tokens spent after first testable output fixing test failures and constraint violations | ⚠ This is the biggest claimed payoff ("one prevented mistake saves more than 20 sessions") — must measure it. Continue each session through at least one round of `test_printer`/`test_reader` validation. |

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

**⚠ Concept extraction must be independent from the test sessions.** If the same AI that will later use the concepts also writes them, it embeds its own understanding — biasing the test (the AI reads its own prior output). Procedure: a *separate* AI session reads the source material and produces JSON, then a human reviews for accuracy and completeness. This separates concept-writing quality from concept-reading impact.

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
4. **Continue through at least one round of test validation** (`test_printer`, `test_reader`) — don't stop at "first compilable output." The rework phase is where the biggest claimed payoff lies.
5. Save the full transcript for analysis.

### Phase 4: Analyze

Claude Code stores full session logs at `~/.claude/projects/{project}/{session-id}.jsonl`. Each JSONL file contains structured records with all the data needed for comparison:

**Available per assistant turn:**
- `usage.input_tokens`, `usage.output_tokens`, `usage.cache_creation_input_tokens`, `usage.cache_read_input_tokens`

**Available per tool call:**
- `type: "tool_use"` with `name` (Read, Grep, Glob, Bash, Edit, Write, Agent)
- `type: "tool_result"` with the output

**Extraction plan for each metric:**

| Metric | How to extract from JSONL |
|---|---|
| **Total tokens** | Sum `input_tokens + output_tokens` across all assistant messages |
| **Discovery cost** | Tokens consumed before the first `Edit` or `Write` tool call |
| **Files read** | Count distinct file paths in `Read` tool calls |
| **Irrelevant reads** | Files that appear in `Read` calls but never in subsequent `Edit`/`Write` calls. ⚠ This overcounts — reading a file to *understand a pattern* applied elsewhere is not irrelevant (e.g., reading `ConversationToWidget.jl` to learn the hybrid pattern, then applying it in `SyntaxToWidget.jl`). Consider a manual pass to reclassify "reads for understanding" vs "reads that led nowhere." |
| **Course corrections** | Count files that are `Edit`ed more than once (rewrites). ⚠ Iterative editing is normal (add function → add tests → wire into existing file = 3 edits, 0 corrections). A better proxy: count `Edit` calls that *revert or replace* previous edits to the same region. Harder to extract automatically — may need manual review of edits that touch overlapping line ranges. |
| **Tool call count** | Count by tool name |
| **Time to first code** | Token offset of the first `Edit`/`Write` call |
| **Rework after first version** | Tokens consumed after first testable output (continued session through test validation) |
| **Constraints discovered** | Manual — grep the assistant message text for C1–C8 keywords (delegation, navigation, gesture, WidgetLabel, mixed dispatch, component, indentation). Then verify in the code: was each discovered constraint correctly applied? |

A post-hoc analysis script can parse the JSONL and produce a comparison report. The script should:
1. Accept 2–4 session JSONL paths as arguments.
2. For each session, compute all metrics above.
3. Output a side-by-side comparison table.

Compare transcripts against the metrics table. For each session:
- List which of C1–C8 were discovered, and at what token offset.
- Count files read, tokens consumed, course corrections.
- Assess the resulting code: does it follow the delegation principle? Does it handle collapse? Does it wire selection correctly?

## Open Questions

- **Session variance.** AI sessions are non-deterministic. A single run per branch may not be representative. Running 2–3 sessions per branch would improve confidence but multiplies cost. Start with one run each; repeat only if results are ambiguous. ⚠ With N=1, frame the writeup as a "pilot" not an "experiment." Statistical claims require N≥3 per branch.
- **Concept quality matters more than quantity.** A poorly written concept that states the rule without the *why* may not help. The test also validates concept quality, not just the concept approach.
- **CLAUDE.md wording sensitivity.** The preload instruction in CLAUDE.md may significantly affect behavior. Small wording changes ("read at start" vs "check before modifying") could matter more than the concept content itself.
- **Fair comparison.** The control session has access to guides which contain the same knowledge (just buried in longer documents). The test measures retrieval efficiency, not knowledge availability.
- **This test validates Phase 1, not Phase 2.** The test uses simple glob-based retrieval + CLAUDE.md rules, not the INDEX.json/FILE_MAP.json/bundles infrastructure described in `concept-document.md` Phase 2. If the test shows positive results, it proves concepts help but says nothing about whether the retrieval infrastructure is the right approach. Conversely, if simple glob works well enough, Phase 2 may be unnecessary overhead. Let the results inform whether to build Phase 2 at all.
- **Concept creation during the test.** Neither plan addresses what happens when the AI discovers a new constraint *during* implementation. Does it stop and write a concept? Track this qualitatively: does the AI naturally want to capture what it learned? This informs the "maintenance workflow" design in the concept-document plan.
