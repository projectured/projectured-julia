# Conversation redesign — turns, parts, rich composer, widget presentation

A staged redesign of the in-editor AI conversation. Supersedes the earlier
"collapsible icon parts" plan (which was scoped to rendering only). The redesign
covers three coupled topics:

1. **The conversation document data structure** — a uniform *turn / part* model.
2. **Editing & submitting a new user message** — a rich multi-part composer
   (type prose, paste JSON/XML/Julia/Tables, add & **evaluate** Julia inline)
   before submitting to the AI.
3. **Presentation** — a vertical list of widgets, one per top-level turn and one
   per part, each independently collapsible.

Plus the two serialization directions that connect the document model to the LLM:

4. **Conversation → string/messages** so the LLM understands it.
5. **LLM response → documents** via existing and new parsers.

## Guiding model: turns of parts

```
ConversationConversation = { turns::[ConversationTurn] }
ConversationTurn         = { role::(:user|:assistant), parts::[ConversationPart], collapsed, selection }
ConversationPart         = { content::Document, collapsed, selection }      # ONE type
```

There is **one** part type. A part is a thin, collapsible slot around an
arbitrary `content::Document`; the content carries its own type and data, and the
existing `TypeDispatchingProjection` projects/serializes it by that type. So the
`content` of a part is e.g.:

- prose      → `TextText`
- heading / list → a Book-domain document (`BookChapter`/`BookParagraph`/`BookList`) — the level/structure lives in the content type
- Julia code → `JuliaDocument`
- a Julia **evaluation** → an `EvaluatorForm` document (new `Evaluator.jl`,
  modeled on the Lisp [evaluator.lisp](../../../projectured-lisp/source/document/evaluator.lisp)):
  two fields, `form::Document` (the code — a `JuliaDocument`) and
  `result::Document` (the result document type(s) are **not yet created** — for
  now `result` can be a `TextText` of the output; richer result documents are
  future work). Code+result live *in the content document*, not as separate parts
  and not as part metadata.
- pasted data → `JsonDocument` / `XmlDocument` / `TableTable` / …
- being typed → a `DocumentInsertion` (until committed to the above, via Stage 3)

Why one part type (this replaces the earlier subtype hierarchy):

- The subtypes mostly **re-encoded the content's own type** (`TextPart`→`TextText`,
  `DataPart.kind`→the document type), giving the type-dispatch projection nothing
  it didn't already have. The only genuine carriers (heading level, list
  structure, code+result) move into **content document types** (Book domain; the
  evaluator document) — the projectional way, matching the Lisp original where
  containers hold arbitrary `t` documents sorted out by type-dispatch.
- The only things a part legitimately adds beyond its content — `collapsed` and
  slot `selection` — are the same for every part, so they justify **one** wrapper,
  not a hierarchy. (Turn likewise is one type; `role` is a field.)
- **Both user and assistant turns are part-lists**, so the old asymmetry
  (assistant code nested as a block, user code top-level as an execution)
  disappears: every part is a uniform slot in exactly one turn, with a uniform
  reference path `turns[i].parts[j]`, a uniform `collapsed`, and a uniform widget.
- It maps 1:1 to the Anthropic API (`message = {role, content:[blocks]}`): a
  multi-part user turn serializes to **one** user message with several content
  blocks — fixing today's "multiple consecutive user messages" shape.

## Already done (foundation)

- **`TextFirstLine` projection** ([program/src/projection/primitive/TextFirstLine.jl](../../program/src/projection/primitive/TextFirstLine.jl)),
  registered in `Projectured.jl`. `TextText → TextText` keeping the first visual
  line (cuts at a standalone `TextNewline` or an embedded `'\n'`), with identity
  selection mapping over the kept prefix. **Not on the critical path anymore** —
  per the decision below, collapse uses graphics-viewport clipping first; this is
  the later high-fidelity refinement (Stage 7).
- **Baseline `conversation_example`** (standalone document + the current
  `ConversationToSyntax` projection) in
  [example/src/document/Conversation.jl](../../example/src/document/Conversation.jl)
  and [example/src/projection/Conversation.jl](../../example/src/projection/Conversation.jl).
  Keep as the "old rendering" reference until Stage 2's widget example lands.

## Key decisions

- **Collapse = graphics-viewport clipping, for now.** A collapsed turn/part wraps
  its content in a `WidgetScrollPane` sized to a few lines (the viewport clips,
  via `GraphicsViewport`); expanded shows the content at intrinsic height. This
  reuses the existing scroll-pane viewport mechanism
  ([WidgetToGraphics.jl:1784](../../program/src/projection/primitive/WidgetToGraphics.jl#L1784))
  and the `_ITEM_VIEWPORT_H` pattern. `TextFirstLine` (Stage 7) replaces the clip
  with a real first-line projection later.
- **Two collapse levels:** the turn widget collapses the whole turn; each part
  widget collapses that part. `collapsed::Cell{Bool}` lives on the **domain**
  (turn and part) so streaming re-projection can't reset folds. Reuse the generic
  `ToggleCollapseOperation(target)` ([common/Operation.jl:243](../../program/src/common/Operation.jl#L243)).
- **Presentation is a vertical list of widgets** (`VerticalLayout` of turn
  widgets, each a `VerticalLayout` of part widgets); one widget per turn, one per
  part. `WidgetCard`/`WidgetComposite` with a `WidgetAvatar` role icon in a
  recursive `title` header (the header is the fold click target).
- **Insert-by-typing via a generic `DocumentInsertion`.** Typed parts are added
  with the domain-independent insertion mechanism ported from the Lisp editor:
  type the domain name (`julia`, `json`, …) + Enter to get the domain document.
  Reusable editor-wide; it is the substrate for the composer (Stage 3) and shares
  the Stage-5 parsers. See Stage 3's "Foundation".
- **Build new capability in standalone examples first, integrate into the live
  `WorkbenchAssistant` panel last** — the user explicitly wants presentation and
  editing testable in isolation.

---

# Stages

Each stage is independently testable and leaves the build green. Order reflects
dependencies; Stages 2–5 can largely proceed in parallel once Stage 1 lands.

## Stage 1 — Domain: turn/part data structure ✅ DONE

**Goal.** Replace the message/block types with the uniform turn/part model.

**Implemented.** `Evaluator.jl` (`EvaluatorForm{form,result,is_error,tool_use_id}`,
`EvaluatorToplevel`); `Conversation.jl` rewritten to
`ConversationConversation{turns}` / `ConversationTurn{role,parts,stop_reason,collapsed}`
/ `ConversationPart{content,collapsed}`; `ConversationToSyntax`/`ConversationToWidget`
ported (stringify-render); `WorkbenchAssistant.jl` `build_messages`/streaming/
`parse_markdown_blocks` ported; `Projectured.jl`, example doc, and tests updated.
Verified: package compiles; conversation example walk 0 errors; McpTest
editor-reference green; tool-use round-trip (13) + reactive-thunk (3) green.
(The pre-existing `test_assistant_mvp` typing-scene failures are environmental —
identical counts on clean HEAD — not from this work.)

**Stage-1 deviations from the model above (revisit in later stages):**
- `EvaluatorForm` carries `is_error` + `tool_use_id` (tool-protocol metadata)
  beyond the conceptual `form`+`result`; `form`/`result` use the `JuliaIdentifier`
  placeholder + `TextText` output (real `juliaparse` + result documents = Stage 5).
- **Heading/list parts are `TextText`** (markdown text preserved), not yet
  Book-domain documents — deferred.
- **1:1 message→turn mapping**: each old message became one turn (so an assistant
  tool call is its own `:assistant` eval turn); `build_messages` keeps the
  cross-turn lookahead. Grouping text+tool calls into one turn is a later refinement.
- `ConversationTurn` gained a `stop_reason::Symbol` field (assistant streaming
  status) — not in the bare model sketch.

- Rewrite [program/src/document/Conversation.jl](../../program/src/document/Conversation.jl):
  - `ConversationConversation { turns::CellVector }`.
  - `ConversationTurn { role::Symbol, parts::CellVector, collapsed::Cell{Bool},
    selection }`.
  - `ConversationPart { content::Document, collapsed::Cell{Bool}, selection }` —
    **one** type wrapping an arbitrary content document (no subtypes).
  - `collapsed` defaults to `false`. Element access, `push!`, `setfn!`, `show`,
    constructors (incl. convenience ctors that wrap a string/`TextText` or a
    document directly into a part).
- New **`program/src/document/Evaluator.jl`**, an `EvaluatorModule` modeled on
  the Lisp [evaluator.lisp](../../../projectured-lisp/source/document/evaluator.lisp):
  - `EvaluatorDocument <: Document` (abstract base, mirrors `evaluator/base`).
  - `EvaluatorForm { form::Document, result::Document, selection }` — one code +
    its result (mirrors `evaluator/form`). `form` holds the code (`JuliaDocument`);
    `result`'s document type(s) are deferred — use `TextText` for the output for
    now.
  - `EvaluatorToplevel { elements::CellVector, selection }` — a sequence of
    `EvaluatorForm`s (mirrors `evaluator/toplevel`); useful as a notebook/REPL
    container, optional for the conversation use.
  - (The Lisp `evaluator/completion` — autocomplete over defined functions — is
    out of scope for now; note as future work.)
  This is the content of a part that represents a Julia evaluation; code+result
  live here, not as parts or part metadata. Constructors, element access on the
  toplevel, `setfn!`, `show`.
- Port the existing consumers mechanically so everything compiles and current
  behaviour is preserved (real redesign of these is Stages 4–5):
  `ConversationToSyntax`, `ConversationToWidget`, `WorkbenchAssistant.jl`
  (`build_messages`, streaming handlers, `parse_markdown_blocks`). Old block
  semantics map onto content types: text→`TextText`, heading/list→Book-domain
  documents, code→`JuliaDocument`, execution→the evaluator document.
- Update the baseline `conversation_example` document to the new types.

**Deliverable / test.** Construct a conversation whose parts cover the content
kinds (text, Book heading/list, `JuliaDocument`, evaluator, a pasted
`JsonDocument`); `show` + walk it; `test_printer(conversation_example)` still
green.

## Stage 2 — Widget presentation (vertical list, nested collapsible widgets)

**Goal.** Render a conversation as a vertical list of collapsible turn widgets,
each holding collapsible part widgets. Standalone, testable in isolation.

- New/rewritten `ConversationToWidget`:
  - `ConversationConversation` → `VerticalLayout` of turn widgets.
  - `ConversationTurn` → `WidgetCard`: `title` = header row
    `HorizontalLayout[WidgetAvatar(role icon), WidgetLabel(role)]`; `content` =
    `VerticalLayout` of part widgets. Collapsible: when `turn.collapsed`, wrap
    `content` in a `WidgetScrollPane` clipped to N lines.
  - `ConversationPart` → `WidgetCard`/`WidgetComposite`: header (an icon derived
    from `content`'s type) + body = the `content` document embedded and recursed
    by type-dispatch (`TextText` → text chain; `JuliaDocument` / evaluator /
    `JsonDocument` / `XmlDocument` / `TableTable` / Book → their projection
    chains). One projection for all parts; the content type selects the body.
    Collapsible the same way via viewport clip.
- `WidgetCard` change in [WidgetToGraphics.jl](../../program/src/projection/primitive/WidgetToGraphics.jl):
  recurse a `Document` `title` (not just stringify) and track its iomap in
  `child_iomaps` so header clicks route; generalize `content` to recurse any
  `Document`. (Sizing: card height bottom-up from content, width top-down via
  `_resolve_width`; collapse shrinks the clipped body so the column reflows.)
- Click on a turn/part header → `ToggleCollapseOperation(domain node)`
  (hit-test modeled on the tab-bar at [WidgetToGraphics.jl:1693](../../program/src/projection/primitive/WidgetToGraphics.jl#L1693)).
- Keep the reactive-thunk pattern so streamed turns/parts append live.

**Deliverable / test.** New example `conversation_widget_example` (document +
widget projection) registered in `Examples.jl` / `ProjecturedExample.jl`.
Tests: printer walk (0 errors); reader test that a header click yields
`ToggleCollapseOperation` with the right target; collapse flips the body between
clipped and full; `write_image_example` snapshot.

## Stage 3 — User-message composer (rich editing)

**Goal.** A draft user turn the user assembles from multiple parts before
submitting — the complex replacement for today's single-string input.

- A draft `ConversationTurn(role=:user)` (or a dedicated `WorkbenchAssistant.draft`
  field). Starts **empty**. The composer is projected with the same Stage-2 part
  widgets plus an editable affordance.
**Adding a typed part = the generic `DocumentInsertion` mechanism (ported from
Lisp).** Rather than bespoke `AddCodePart`/`PasteAsPart` operations with an
explicit kind menu, an empty/new part slot holds a `DocumentInsertion`
placeholder; the user **types the domain name and presses Enter** to get the
matching domain document. This is how the Lisp editor inserts everything
([source/projection/primitive/document-to-syntax.lisp](../../../projectured-lisp/source/projection/primitive/document-to-syntax.lisp),
factory in [source/executable/projection.lisp](../../../projectured-lisp/source/executable/projection.lisp)).
It is reusable editor-wide, not just here.

- **Foundation — port first** (domain-general, lands before the composer wiring):
  - `DocumentInsertionToSyntaxLeaf(factory)` projection. `DocumentInsertion`
    already exists ([Document.jl:58](../../program/src/document/Document.jl#L58),
    prefix `"Insert a new "` / suffix `" here"`). Printer: render
    `prefix · value · completion-hint · suffix`, value **green when commitable,
    red when not** (from `factory(value)`). Reader: **Tab** accepts the
    completion, **Enter** commits via `factory(value)` → replaces the placeholder
    with the produced domain document, **Esc** aborts to `DocumentNothing`, other
    keys edit `value`. Model on the Lisp reader + our existing
    `JsonInsertionToSyntaxLeaf`.
  - `default_factory(name)` + a `completion_prefix_switch` helper: name →
    domain document/insertion (`"json …"` → `JsonInsertion`/`JsonArray`/…,
    `"xml …"` → `XmlInsertion`, `"text"` → `TextText`, `"table"` → `TableTable`,
    **`"julia"` → `JuliaInsertion`**, …), driving both the completion hint and the
    commit.
  - **`JuliaInsertion`** (new — the Julia domain has no insertion type) + its
    reader: entering Julia source commits via `juliaparse` → `JuliaDocument`.
    This is the chain *domain-independent insertion → domain-specific insertion →
    enter the domain's actual source*; for Julia that source is Julia code.
- Composer operations on top of that foundation (all act on uniform
  `ConversationPart`s whose `content` differs):
  - typing into a part whose `content` is a `TextText` → existing `TextText`
    reader path.
  - a new/empty part has `content = DocumentInsertion`; type `julia`/`json`/`xml`/
    `table` + Enter → the part's `content` becomes the matching document
    (`JuliaInsertion` → Julia source → `JuliaDocument`).
  - **paste** → seed a `DocumentInsertion`'s `value` (or, when the kind is
    detected, commit straight to the parsed document via the same factory/Stage-5
    parsers).
  - `EvaluatePart` → for a part whose `content` is a `JuliaDocument` (or an
    `EvaluatorForm`), run the code via the existing `execute_julia_code` tool
    (`McpModule` / `ToolRegistry`) and store the output in the `EvaluatorForm`'s
    `result` field — **inline, while editing**, before submit (generalizes
    today's ALT+ENTER `SubmitJuliaOperation`). (Evaluating a bare `JuliaDocument`
    part wraps its `content` in an `EvaluatorForm`: `form` = the code, `result` =
    the output.)
  - `SubmitDraftTurn` → push the draft turn into `conversation.turns`, reset the
    draft to empty, and trigger the assistant turn.
- Composer keymap: typing edits the focused part / insertion; a chord (e.g.
  ALT+ENTER) → `EvaluatePart` on the focused code part; **Send** (e.g.
  Ctrl+ENTER / button) → `SubmitDraftTurn`. (Separating "add/eval a part" from
  "send the turn" is the one genuinely new UX decision; note Enter is already
  taken by insertion-commit, so Send needs its own chord.)

**Deliverable / test.** New example `conversation_editor_example` exercising the
lifecycle: empty start → type text → add a part by typing `julia` + Enter (via
`DocumentInsertion`) → enter Julia source → evaluate it (result appears) → paste
(JSON/XML/Table) → submit (draft becomes a turn, draft re-empties). Also a
focused test of `DocumentInsertionToSyntaxLeaf` + `default_factory` on its own
(type prefix → completion + green/red commitability; Enter → correct domain
document; `"julia"` → `JuliaInsertion` → `JuliaDocument`). Tests: scripted
operation sequences via the reader (mirroring `TypeinTest` / `ClickRoundtripTest`),
asserting the draft turn's parts after each step.

## Stage 4 — Serialization: conversation → LLM messages/string

**Goal.** Convert the turn/part conversation into the Anthropic messages array
(and a plain-string fallback) so the LLM understands it.

- Rewrite `build_messages` around turns: `turn → message`, `parts → content
  blocks`, dispatching on each part's `content` **type** (not a part subtype):
  - `TextText` / Book heading/list → `{type:text}` (markdown).
  - `JuliaDocument` (quoted, no eval) → fenced ```` ```julia ```` text in the turn.
  - `EvaluatorForm`, in an `:assistant` turn → `tool_use` block (the `form`/code)
    in the assistant turn + `tool_result` block (the `result`, paired by
    `tool_use_id`) in the next user turn.
  - `EvaluatorForm`, in a `:user` turn (inline eval) → user text ("I ran …
    Result: …") **as a block within the same user turn**.
  - `JsonDocument` / `XmlDocument` / `TableTable` → serialized to text (the
    domain's document→string), fenced with its kind.
- A multi-part user turn becomes **one** user message with N content blocks.
- `tool_use_id` pairing for `EvaluatorForm` parts lives on the form (or is
  recovered by adjacency) — the one piece of API metadata not implied by content.
- Provide a human-readable `conversation_to_string` too (for logging / the plain
  fallback).

**Deliverable / test.** `build_messages(conversation)` over a mixed example →
assert message count, role alternation, and per-block shape; assert a multi-part
user turn yields a single user message.

## Stage 5 — Parsing: LLM response (and pasted text) → documents

**Goal.** Parse assistant output and pasted clipboard text into part documents,
using existing parsers and adding the missing ones.

- Assistant text → parts: extend `parse_markdown_blocks` to emit uniform
  `ConversationPart`s whose `content` is the right document — prose→`TextText`,
  heading→Book heading, list→Book list, fenced code → a part whose `content` is a
  real document:
  - `julia` → `juliaparse` (exists) → `JuliaDocument`.
  - `json` → **new** JSON parser → `JsonDocument`.
  - `xml`  → **new** XML parser → `XmlDocument`.
  - `ini`/`ned` → `iniparse`/`nedparse` (exist) where relevant.
  - otherwise → `TextText` (plain monospace), with a `try/catch` fallback so a
    malformed block never breaks the turn.
- Same parser set backs Stage 3's paste (paste detection → parse → part content).
- **New parsers needed:** JSON string → `JsonDocument`, XML string →
  `XmlDocument`, and a tabular/CSV string → `TableTable`/`TabularTabular`. Model
  them on [JuliaParser.jl](../../program/src/parser/JuliaParser.jl) (string →
  document tree), in `program/src/parser/`. (Existing: `juliaparse`, `iniparse`,
  `nedparse`.)
- Streaming: the assistant turn accumulates parts as deltas arrive; on
  `content_block_stop`, finalize/parse the scratch text into parts (each with its
  parsed `content` document) — port of today's `_replace_last_block!`.

**Deliverable / test.** `parse_markdown_blocks` / `parse_response` over sample
markdown → assert each part's `content` is the right document type and that
`julia`/`json`/`xml` contents are real documents (not stringified). Unit-test
each new parser (string → document → re-serialized round-trip where feasible).

## Stage 6 — Integrate into the live WorkbenchAssistant panel

**Goal.** Replace the panel's conversation slot + simple input with the Stage-2
presentation and the Stage-3 composer; wire streaming to Stage-5 parsing and
sends to Stage-4 serialization.

- `WorkbenchAssistantToWidgetSplitPane`: conversation pane = Stage-2 widget
  projection; input pane = Stage-3 composer.
- `_run_agent_loop!` / `_handle_sse_event!` produce assistant turn parts via
  Stage 5; `SubmitDraftTurn` uses Stage 4.
- Update existing assistant tests; the panel shows a vertical list of widgets.

**Deliverable / test.** Assistant example end-to-end; existing
`test_*(assistant_example)` updated and green.

## Stage 7 — Refinement: first-line collapse via `TextFirstLine` (optional)

Swap the viewport clip for the already-built `TextFirstLine` projection on text
and code parts where a real, self-sizing, selectable first line beats a pixel
clip (uses `AlternativeProjection` keyed on the part's `collapsed` cell, sharing
the upstream `…→Text` work). Optional polish; not required for the feature.

---

## Sequencing notes

- **Stage 1 is the gate**; 2/3 (presentation, composer) and 4/5 (serialize,
  parse) can run in parallel after it. 6 needs 2–5. 7 is optional and last.
- New parsers (Stage 5) are shared by both the LLM-response path and the paste
  path (Stage 3) — build them once.
- The **`DocumentInsertion` mechanism + `JuliaInsertion`** (Stage 3 "Foundation")
  is domain-general and standalone-testable (no conversation needed) — like
  `TextFirstLine`, a good self-contained next unit to implement and verify on its
  own before the composer wiring.
- Keep each stage's example registered and green before moving on; never run
  `test_all` — use the targeted `test_*(example)` per the repo testing guide.

## Open decisions (resolve as stages start)

- **Composer "send" gesture** vs "add/eval part" (Stage 3) — the one new UX call.
- **Paste kind detection** — auto-detect from content vs. an explicit
  paste-as menu (Stage 3/5).
- **`EvaluatorForm` shape** — `{form::Document (code, a JuliaDocument), result::Document}`
  with `result`'s document type(s) deferred (`TextText` output for now); decide
  the richer result documents later. Quoted-vs-evaluated is the content type
  (`JuliaDocument` vs `EvaluatorForm`), not a part subtype.
- **Explicit `ConversationTurn` type vs flat parts tagged by role** — plan assumes
  an explicit turn container (cleaner "open turn"/send boundary).
- **Where `collapsed` for the turn-level lives** — on `ConversationTurn`; part-level
  on each `ConversationPart`. Both uniform.
