# Conversation redesign — turns, parts, rich composer, widget presentation

A staged redesign of the in-editor AI conversation. Supersedes the earlier
"collapsible icon parts" plan (which was scoped to rendering only). The redesign
covers three coupled topics:

1. **The conversation document data structure** — a uniform *turn / part* model.
2. **Editing & submitting a new user message** — a rich multi-part composer
   (type prose, paste JSON/XML/Julia/Tables, add & **evaluate** Julia inline)
   before submitting to the AI.
3. **Presentation** — a vertical list of widgets, one per top-level 
turn and one
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

## Stage 2 — Widget presentation (vertical list, nested collapsible widgets) ✅ DONE

**Implemented.** `WidgetCard` now recurses a `Document` `title` (avatar+label
header) and a `Document` `content` (tracking the title iomap). `ConversationToWidget`
rewritten: `ConversationConversation` → `VerticalLayout` of turn `WidgetCard`s
(avatar role header + reactive part stack); `ConversationPart` → `WidgetCard`
(kind avatar header + recursed content; `EvaluatorForm` → code-over-result, each
sized to content). Collapse via graphics-viewport clip (`WidgetScrollPane` to ~1
row), read from the domain `collapsed` at print time; turn and part collapse
independently. New standalone `conversation_widget_example` (two-stage
widget→graphics).

**Interactive collapse (done).** `WidgetCard` gained a reader: a click on its
header (Document title) emits `ToggleCollapseOperation(card)`; `ConversationToWidget`
iomaps track their children (`ChildrenIoMap`) and its root reader walks the iomap
tree to translate `card → domain turn/part`, so `evaluate_operation` flips the
right `collapsed`. Verified end-to-end: header clicks on turns and parts resolve
to the correct domain nodes and toggle them (integration test
`_mvp_test_collapse_click`). Walk 0 errors; collapse shrinks height; reactive
lists intact; widget/layout example walks unregressed.

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

- **Foundation — ✅ DONE** (`program/src/projection/primitive/DocumentInsertionToSyntax.jl`).
  Implemented `InsertionToSyntaxLeaf(commit; prefix, suffix)` (printer renders
  `prefix·value·suffix`; reader edits `value`, **Enter** commits via `commit(value)`
  → `ReplaceDocumentOperation`, **Esc** → `DocumentNothing`); `default_factory` /
  `default_completion`; `DocumentInsertionToSyntaxLeaf()` (names → domain docs) and
  `JuliaInsertionToSyntaxLeaf()` (juliaparse). Added the `JuliaInsertion` Julia type
  + `_apply_string_replace!` methods; **wired the previously-orphaned
  `document/Document.jl` (`DocumentInsertion`/`DocumentNothing`) into the build.**
  Verified (`test_document_insertion`, 14 asserts): type `julia`+Enter →
  `JuliaInsertion` → source+Enter → `JuliaDocument`; Esc → `DocumentNothing`.
  *Deferred:* live completion hint + green/red colouring. Original spec below:
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
### Composer — ✅ DONE (`program/src/editor/ConversationEditor.jl`)

Implemented as a self-contained `ConversationComposerToWidget` projection
(printer renders the draft turn as a chat-bubble `WidgetCard` — avatar header
over a reactive `VerticalLayout` of per-part cards; reader maps every gesture to
a composer operation by dispatching on the **active** (last) part's content
type). Wired through the **widget** pipeline:
`RecursiveProjection(ConversationComposerToWidget())` → the same widget→graphics
inner dispatch as `conversation_widget_example`
(`make_conversation_editor_projection_example`). The per-part label list is a
`CellVector` thunk over the parts' `value`s, so typing recomputes the labels
without reprinting. `map_reference_forward/backward` return `nothing` so the
widget layers never hijack keys for a mapped cursor; the composer tracks
`value{k}` selection itself.

Operations (direct mutation of the draft turn): `ComposerInputOperation`,
`ComposerBackspaceOperation`, `ComposerNewlineOperation` (SHIFT+ENTER),
`ComposerInsertPartOperation` (INSERT — commit/drop the typein, append a
`DocumentInsertion`), `ComposerCommitChooserOperation` (ENTER, `default_factory`),
`ComposerCommitSourceOperation` (ENTER, `juliaparse` → `JuliaDocument`),
`ComposerEvaluateOperation` (ALT+ENTER, `execute_julia_code` → `EvaluatorForm`),
`ComposerRevertOperation` (ESC), `ComposerSubmitOperation` (ENTER —
`PrimitiveString`→`TextText`, drop trailing blank). Example
`conversation_editor_example`; tests in
`test/src/projection/ConversationEditorTest.jl` (`test_conversation_editor`,
28 asserts) cover the worked case, ESC-revert, unknown-keyword no-op, blank-drop,
and the reader's gesture→operation mapping per state.

**Reactive rendering (done).** Three reactivity fixes so the widget output
updates live as you edit:

- *Value edits* — each part body is a `TextText` whose `TextString` content/color
  are reactive thunks over the part's live value/cursor (the proven text→graphics
  reactive path), so typing repaints without the part list recomputing.
- *Structural changes* — the widget `layout→graphics` printers snapshotted
  `length(children)` at print time, so added/swapped part cards never appeared.
  Fixed properly in `LayoutToGraphics.jl`: `VerticalLayoutToGraphicsCanvas` /
  `HorizontalLayoutToGraphicsCanvas` now wrap their body in a `build` cell keyed
  on `doc.children` (`_vl_build`/`_hl_build`), exposing a stable output canvas
  whose elements/size/entries derive reactively — adding a child repaints with
  **no `iomap = nothing`** (that reset is only correct for whole-root swaps). The
  per-child size/position cells stay lazy, so a child merely growing still
  updates incrementally. Verified regression-free across the layout/widget tests.
- *Card sizing* — `WidgetCardToGraphicsCanvas` likewise computed `card_height` /
  the surface panel / the output-canvas size eagerly, so a card did not grow with
  its content (the parts overflowed the turn bubble's border). Same fix: recurse
  the Document title/content once (stable iomaps), then derive height, panel,
  element positions, and canvas size from a `build` cell (`_card_build`) that
  reads the content's reactive height. The turn card now grows as parts are
  added/evaluated.
- *Caret + placeholder* — the active (last) editable part's body `TextText` gets a
  reactive `selection` thunk (`.elements[span].content[k:k]` at the part's cursor),
  so `TextToGraphics` draws its **genuine thin-line caret** following the cursor —
  no glyph. Safe because the enclosing turn `WidgetCard` reader drops coordless key
  events ([WidgetToGraphics.jl](../../program/src/projection/primitive/WidgetToGraphics.jl#L2164)),
  so the text layer never hijacks the composer's keystrokes. A `PrimitiveString` /
  `JuliaInsertion` body is one span with a reactive pale-gray `type here…`
  placeholder while empty. A `DocumentInsertion` keeps its **`Insert a new <value>
  here`** decoration — gray prefix/suffix spans around the editable value span,
  caret in the value (anchored to the end of the prefix while the value is empty,
  since a caret can't sit in a zero-width span).

- *Committed parts render through their real projections.* Once a part is
  committed, its card body is the actual content document recursed through the
  inner dispatch: a `JuliaDocument` renders as a **parsed, tokenised Julia
  document** (juliaparse → julia→syntax→text→graphics, not a lossy `string`),
  `TextText` prose as text, and an `EvaluatorForm` as its `form` stacked over its
  `result`. Only the active editing part uses the custom editable `TextText`.

**Kind chooser → domain insertions.** The chooser commits `julia`/`json`/`xml` to
a `JuliaInsertion` / `JsonInsertion` / `XmlInsertion` (a composer-local factory).
All are editable insertions (type a source, with caret + reactive rendering) and
**parse on ENTER** into their domain document via the parsers
(`juliaparse`/`jsonparse`/`xmlparse`); committed parts then render through the
domain projection (parsed JSON/XML/Julia, tokenised). Julia additionally
**evaluates** (ALT+ENTER → `EvaluatorForm`). `jsonparse`/`xmlparse` are small
recursive-descent parsers (`parser/JsonParser.jl`, `parser/XmlParser.jl`) — basic
but real. Structural key-driven insertion (e.g. `[` on a `JsonInsertion` →
`JsonArray`) is still future work.

Deferred to Stage 6: pushing the finalized turn into a live conversation +
triggering the assistant (`ComposerSubmitOperation` only normalizes for now);
paste-as-part (needs Stage-5 parsers).

### Composer model (decided — the grow-a-turn-by-parts flow)

The composer edits a draft `ConversationTurn(:user)`. Only the **last** part is
*active* (has the cursor); earlier parts are committed/static. A part's `content`
moves through five states:

| State | content type | screen |
|---|---|---|
| text typein | `PrimitiveString` (placeholder when empty) | pale `type a message…▮` / typed text |
| kind chooser | `DocumentInsertion` | pale `Insert a new ▮ here` (value `julia` highlights) |
| julia source | `JuliaInsertion` | monospace source `2+2▮` |
| quoted code | `JuliaDocument` | syntax-highlighted code |
| eval form | `EvaluatorForm{form,result}` | `> code` over `= result` |

**Gesture → state (applies to the active part):**

| Active state | Gesture | Result |
|---|---|---|
| text typein | printable key | insert char |
| text typein | **SHIFT+ENTER** | newline in text |
| text typein | **INSERT** | commit current text (drop if empty) → append active `DocumentInsertion` |
| text typein | **ENTER** | **submit the turn** |
| kind chooser | printable key | edit value (free typing; no switch on keystroke) |
| kind chooser | **ENTER** | if value is a known keyword (`julia`/`json`/`xml`/`text`) **commit** → corresponding insertion (`JuliaInsertion`, …); otherwise *ignore* (stay editing) |
| kind chooser | **ESC** | revert active part → empty text typein |
| julia source | printable key | edit source |
| julia source | **SHIFT+ENTER** | newline in source (multi-line code) |
| julia source | **ENTER** | `juliaparse(src)` → active becomes `JuliaDocument`; append active text typein |
| julia source | **ALT+ENTER** | parse **+ eval** (`execute_julia_code`) → active becomes `EvaluatorForm`; append active text typein |
| julia source | **ESC** | revert active part → empty text typein |

(Parse failure on ENTER/ALT+ENTER ⇒ no-op, stay editing. After any structured
commit, the new active text typein keeps the "always end on a typein" invariant.)

**Decisions locked:** text typein = `PrimitiveString` (reuse placeholder +
editing), converted to `TextText` when committed; ENTER submits only from a text
typein; SHIFT+ENTER newlines in both text and Julia source; ESC reverts a
structured insertion entirely to an empty text typein; keyword `julia`.

**Operations** (in a new `ConversationEditor.jl` or `WorkbenchAssistant.jl`):
`InsertPart` (text→chooser), `EvaluatePart` (ALT+ENTER, via `execute_julia_code`
→ `EvaluatorForm`), `SubmitDraftTurn` (finalize: drop trailing empty typein,
convert active `PrimitiveString`→`TextText`, push to conversation, trigger
assistant). Source-commit (`JuliaInsertion`→`JuliaDocument`) reuses the Stage-3a
`InsertionToSyntaxLeaf` reader; the chooser commits the keyword → insertion **on
ENTER** (the Stage-3a `DocumentInsertionToSyntaxLeaf` reader already does this via
the factory — no per-keystroke switching).

**Worked case** (`"hey assistant, look what I've got"` · evaluated `2+2` ·
`"see, it's not that complicated"`): type → INSERT → type `julia` → **ENTER**
(commit chooser → `JuliaInsertion`) → type `2+2` → ALT+ENTER (`> 2+2 / = 4`, new
typein) → type → ENTER submit ⇒ turn parts `[TextText, EvaluatorForm(2+2→4),
TextText]`.

**Deliverable / test.** New example `conversation_editor_example` (root = a draft
`ConversationTurn(:user)`), exercising the worked case end-to-end. Tests: scripted
gesture sequences via the reader (mirroring `TypeinTest`), asserting the draft
turn's parts after each gesture, and the final 3-part turn. Paste (JSON/XML/Table
→ a part) folds in once the Stage-5 parsers exist.

## Stage 4 — Serialization: conversation → LLM messages/string ✅ DONE

Implemented in `editor/WorkbenchAssistant.jl`. `build_messages` walks turns →
messages, dispatching on each part's content type; structured documents serialize
to **fenced source via their print chain** (`…→syntax→text`, flattened — the same
text the editor shows): `JuliaDocument`→```` ```julia ````, `JsonDocument`→
```` ```json ````, `XmlDocument`→```` ```xml ````. `EvaluatorForm` →
`tool_use`+`tool_result` (assistant) / inline "I ran …" text (user). A multi-part
user turn is one message with N blocks. Added `conversation_to_string` (readable
plain fallback) and exported `result_text`. Tests:
`test/src/editor/ConversationSerializationTest.jl` (`test_conversation_serialization`,
16 asserts) — message count, role alternation, per-block shape, multi-part → one
message, tool_use/tool_result pairing.

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
