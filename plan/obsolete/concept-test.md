# Concept Test — Measuring Impact of Pre-extracted Concepts

Empirically test whether pre-extracted Concept JSON files improve AI programming efficiency. The test framework is reusable — it works for any task, from large projection implementations to small bug fixes that involve digging through the codebase before writing a few lines of code.

## Motivation

The concept-document plan argues that pre-extracted Concepts reduce token usage (~75% reduction in context-gathering) and improve quality (fewer missed constraints). These claims need validation before investing in extracting ~150+ concepts across the codebase.

The pattern this tests is common: the AI spends most of its tokens *reading and exploring* to understand constraints, then writes relatively little code. Pre-extracted concepts should compress the exploration phase dramatically.

### First test case: SyntaxToWidget

The SyntaxToWidget plan is the first test case:
- Complex — touches projection system, widget layer, selection mapping, layout.
- Well-documented challenges — 8 architectural challenges (C1–C8) identified in `plan/pending/syntax-to-widget.md`, each requiring knowledge from different parts of the codebase.
- Fresh — no implementation exists yet, so both sessions start equal.
- Knowledge-scattered — the relevant constraints live in guides, done plans, and code comments across ~15 files.

Future test cases can be any task — a new projection, a bug fix, a refactor. The branch structure, analysis script, and metrics are task-independent.

**⚠ This is a pilot, not a statistically valid experiment.** With N=1 per branch and high AI session variance, the results are anecdotal. The first round establishes whether the approach is *plausible*, not whether it *works*. If results are ambiguous, a second round (2–3 runs per branch) is needed to distinguish concept impact from session luck.

**⚠ Cost of the test itself.** Each session could consume 100,000–300,000 tokens. Worth doing for validated learning, but budget accordingly.

## Test Design

### The task prompt

Give a fresh AI session this prompt:

> Implement Phase 1 of SyntaxToWidget — a projection that maps a single SyntaxNode to a WidgetComposite/WidgetTitlePane, with collapse/expand support. Start with DbCatalog as the test domain.

Don't give it the full syntax-to-widget plan — just the goal. The plan's 8 challenges serve as a scorecard: how many does the AI discover, and at what cost?

### Branch structure

```
database (current)
├── control    ← Session A: no concepts, current setup
└── concepts   ← Session B: core preloaded + rest on-demand
```

**Creating the branches:**
```bash
# From the database branch:
git checkout -b control database
git checkout -b concepts database
# Add concept files and CLAUDE.md changes on the concepts branch, then commit.
# Switch back to database when done:
git checkout database
```

**Setting up worktrees for parallel sessions:**
```bash
# From the main repo (on database branch):
git worktree add ../projectured-julia-control control
git worktree add ../projectured-julia-concepts concepts
```

This creates two independent working directories side by side:
```
gitworkspace/
├── projectured-julia/            ← main repo (database branch)
├── projectured-julia-control/    ← worktree (control branch)
└── projectured-julia-concepts/   ← worktree (concepts branch)
```

**Switching between sessions:** Open each worktree in its own VS Code window. Switch between windows freely — they are fully independent. No commit/stash needed, no branch checkout, no risk of changes bleeding across.

**Two branches, one strategy:**

- **`control`** forks from `database` with no concept files. The AI works as it does today — CLAUDE.md + guides.
- **`concepts`** forks from `database` and holds all extracted JSON files (~30 core + 100–200 regular) with a mixed retrieval strategy:
  - **Preloaded (~30 core):** CLAUDE.md rule: "Read all files in `concepts/core/` at the start of every session." These are the invariants, design decisions, and constraints that apply broadly.
  - **On-demand (100–200 regular):** CLAUDE.md rule: "Before modifying a subsystem, glob `concepts/{subject}--*.json` and read the matches." These are patterns, lessons, and implementation details that matter only in context.

This mirrors the intended production setup — core knowledge is always available, domain-specific knowledge loads when needed.

**⚠ Confounding variable: CLAUDE.md differences.** The concept branch adds retrieval instructions to CLAUDE.md that the control branch doesn't have. To partially isolate the concept variable, the control branch should have equivalent-length CLAUDE.md additions pointing to guides instead (e.g., "Before modifying a projection, read `guide/projection-system.md`"). Otherwise positive results might be attributable to the instructions, not the concepts.

**Cleanup** when the test is done:
```bash
git worktree remove ../projectured-julia-control
git worktree remove ../projectured-julia-concepts
```

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
| Concept session discovers C1 (delegation) before implementation | The core concept is explicit and preloaded; without it, the AI likely iterates children directly |
| Control session discovers C5 (hybrid pattern) late or not at all | Requires reading ConversationToWidget code + understanding the codebase convention |
| Concept session discovers more of C1–C8 before first code | Core preload front-loads the high-leverage constraints; on-demand fills gaps when the AI reaches a subsystem |
| Control session reads 2–3x more files than concept session | Must explore to find knowledge that concepts provide directly |
| Concept session has less rework after first version | Fewer missed constraints means fewer test failures to fix |

## Execution

### Phase 1: Extract concepts

**⚠ Concept extraction must be independent from the test sessions.** If the same AI that will later use the concepts also writes them, it embeds its own understanding — biasing the test (the AI reads its own prior output). Procedure: a *separate* AI session reads the source material and produces JSON, then a human reviews for accuracy and completeness. This separates concept-writing quality from concept-reading impact.

Create ~30 core JSON files in `concepts/core/` and 100–200 regular JSON files in `concepts/` on the `concepts` branch. Each file follows the schema from `plan/pending/concept-document.md`. Source the content from:

1. `guide/projection-system.md` — delegation principle, recursion contract
2. `guide/selection-deep-dive.md` — three-step selection, ProjectionReference
3. `guide/design-decisions.md` — pull-based reactivity, every-field-is-Cell
4. `plan/done/syntaxtotext-delegation.md` or `plan/pending/syntaxtotext-delegation.md` — root-only navigation, gesture handling
5. `program/src/projection/primitive/ConversationToWidget.jl` — code comments on the hybrid pattern
6. `program/src/document/Widget.jl` — WidgetLabel vs WidgetText distinction
7. `program/src/projection/primitive/WidgetToGraphics.jl` — `_push_box_rects!` contract

### Phase 2: Configure CLAUDE.md

The `concepts` branch gets these CLAUDE.md additions:

- "Read all files in `concepts/core/` at the start of every session."
- "Before modifying a subsystem, glob `concepts/{subject}--*.json` and read the matches."

The `control` branch gets equivalent-length guide-pointing instructions to reduce the CLAUDE.md confounding variable:

- "Read `guide/projection-system.md` and `guide/selection-deep-dive.md` at the start of every session."
- "Before modifying a subsystem, check the relevant guide in `guide/document/` or `guide/editor/`."

### Phase 3: Run sessions

With worktrees set up (see Branch structure above), open each in its own VS Code window.

**Workflow:**
1. Start a fresh Claude Code session in each worktree with the same task prompt.
2. Switch between windows freely — they are fully independent.
3. **Continue each session through at least one round of test validation** (`test_printer`, `test_reader`) — don't stop at "first compilable output." The rework phase is where the biggest claimed payoff lies.
4. At any point, run the analysis script to compare progress so far (see Phase 4).

### Phase 4: Analyze with `session/analyze-session.jl`

**Script:** `session/analyze-session.jl` (already implemented)

Parses Claude Code JSONL session logs and writes a structured markdown comparison report to `session/report-{timestamp}.md`.

**Usage:**
```bash
# Compare the two test sessions by passing their JSONL paths directly:
julia --project=program session/analyze-session.jl \
  ~/.claude/projects/{control-project-slug}/{session-id}.jsonl \
  ~/.claude/projects/{concepts-project-slug}/{session-id}.jsonl

# Or analyze the most recent session in the current project:
julia --project=program session/analyze-session.jl --latest

# Compare the two most recent sessions:
julia --project=program session/analyze-session.jl --latest 2
```

Because the two worktrees are different directories, Claude Code stores their JSONL files under different project slugs in `~/.claude/projects/`. Find the right paths:
```bash
ls ~/.claude/projects/ | grep projectured
```

**Metrics computed automatically:**

| Metric | What the script extracts |
|---|---|
| **Effective total tokens** | input (fresh + cache creation + cache read) + output |
| **Output tokens** | actual generated tokens — the real "work" measure |
| **Cache hit rate** | cache read / effective input — how much context was reused |
| **Discovery cost** | output tokens before first Edit/Write — pure exploration overhead |
| **First code at token** | cumulative token offset when first Edit/Write appears |
| **Files read / edited** | distinct file paths from Read / Edit+Write tool calls |
| **Irrelevant reads** | files read but never edited (approximate — reads for understanding may be counted) |
| **Multi-edited files** | files with >1 Edit call (approximate — iterative ≠ corrective) |
| **Tool call counts** | count by tool name (Read, Edit, Write, Bash, Grep, Glob, Agent, etc.) |
| **Assistant turns** | number of assistant messages |

**Report structure:** Each session gets a full detail section (token usage, activity, tool calls, file lists with read/edit counts), followed by a side-by-side comparison table when 2+ sessions are analyzed.

**What to look for manually** (not automated):
- Which of C1–C8 were discovered, and when? Grep the JSONL or transcript for constraint keywords.
- Was each discovered constraint *correctly applied* in the resulting code?
- Qualitative path comparison: did the control session wander while the concepts session went direct?

**Iterative comparison workflow:**
1. Both sessions are working in parallel.
2. At any milestone (e.g., "both sessions wrote their first file"), run the analysis script.
3. The report captures progress-so-far — partial sessions are fine, the script warns if a JSONL was modified within 60 seconds.
4. Save successive reports to track how the gap evolves: `session/report-milestone-1.md`, `session/report-milestone-2.md`, etc.
5. At the end, run a final comparison with both completed sessions.

## Open Questions

- **Session variance.** AI sessions are non-deterministic. A single run per branch may not be representative. Running 2–3 sessions per branch would improve confidence but multiplies cost. Start with one run each; repeat only if results are ambiguous. ⚠ With N=1, frame the writeup as a "pilot" not an "experiment." Statistical claims require N≥3 per branch.
- **Concept quality matters more than quantity.** A poorly written concept that states the rule without the *why* may not help. The test also validates concept quality, not just the concept approach.
- **CLAUDE.md wording sensitivity.** The preload instruction in CLAUDE.md may significantly affect behavior. Small wording changes ("read at start" vs "check before modifying") could matter more than the concept content itself.
- **Fair comparison.** The control session has access to guides which contain the same knowledge (just buried in longer documents). The test measures retrieval efficiency, not knowledge availability.
- **This test validates Phase 1, not Phase 2.** The test uses simple glob-based retrieval + CLAUDE.md rules, not the INDEX.json/FILE_MAP.json/bundles infrastructure described in `concept-document.md` Phase 2. If the test shows positive results, it proves concepts help but says nothing about whether the retrieval infrastructure is the right approach. Conversely, if simple glob works well enough, Phase 2 may be unnecessary overhead. Let the results inform whether to build Phase 2 at all.
- **Concept creation during the test.** Neither plan addresses what happens when the AI discovers a new constraint *during* implementation. Does it stop and write a concept? Track this qualitatively: does the AI naturally want to capture what it learned? This informs the "maintenance workflow" design in the concept-document plan.
