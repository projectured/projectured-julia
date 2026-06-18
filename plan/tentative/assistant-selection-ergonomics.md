# Assistant Selection Ergonomics

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> **Strong caveat:** The fixes proposed below are almost certainly *not* the
> right ones yet. They are reactions to the symptoms of one transcript, not a
> considered design. The real questions — what should the assistant's mental
> model of "the document" be, what is the right grain of tool, how much should
> live in tools vs. the system prompt vs. the API itself — are open. Treat the
> "candidate directions" purely as a starting point for a discussion, and expect
> most of them to be discarded or merged into something better.

---

## The artifact

A real assistant session, prompt: **"select 'Alice' in the current workbench
document."** The assistant *succeeded* — it ended with the correct
`replace_selection!(editor.document, .windows[1].content.editing_page.elements[3].content.entries[1].value.value{0:5})`
— but it took roughly **40 agent rounds** of trial and error to get there. The
full transcript was exported via `write_conversation` (see `struggle.txt` at the
time of writing).

The goal of this plan is to understand *why* it was so hard and whether the
system (tools / prompt / API) should change so this class of task ("select /
find X in the current document") is cheap. **It is not yet clear what the right
change is.**

## What went wrong (grounded in the transcript + code)

These observations are concrete; the *conclusions* drawn from them are not.

1. **The high-level helper it was told to use is broken in the real runtime.**
   The system prompt (`DEFAULT_ASSISTANT_SYSTEM` in
   `program/src/document/Workbench.jl`) tells the model to prefer the workbench
   helpers, so its first real move was `get_focused_workbench_document(editor)`,
   which threw:
   `editor.document is a ScreenDocument, not a WorkbenchWorkbench`.
   `_workbench_page` (`program/src/document/Workbench.jl:431`) assumes
   `editor.document isa WorkbenchWorkbench`, but in the running app it is
   `ScreenDocument → windows[1].content → WorkbenchWorkbench`. The one helper
   that should have been a single call failed, and the model fell back to
   walking the tree by hand for ~10 rounds. **This is a real bug regardless of
   what we decide about the assistant.**

2. **No select-by-content path, and the function that does exactly this is not
   surfaced.** `search_object(obj, predicate) -> Vector{ReferencePath}`
   (`program/src/projection/primitive/ObjectToSyntax.jl:392`) is purpose-built
   for this (its own docstring example finds nodes and `replace_selection!`s
   them). The model never found it — `search_api("workbench find select string")`
   returned `_content_to_string`, `color_darken_selection`, … but not
   `search_object` — and hand-reinvented it: iterate entries, find Alice,
   hand-build the path with `append_reference` / `FieldReference` /
   `ElementReference` / `RangeReference`.

3. **Cell-unwrapping cost ~6 failed calls.** Repeated
   `getindex(::CellVector)` / `getindex(::String)` /
   `getindex(::ConcreteReferencePath)` / `getindex(::WorkbenchWorkbench)` errors,
   all from `x.field[]` — the model didn't know that property access already
   unwraps cells while `getfield` / indexing does not. Nothing tells it this.

4. **Heavy over-reading and empty rounds.** It read the whole selection guide,
   `RangeReference` twice, `PositionReference`, `ReferencePath`,
   `append_reference`, `ElementReference`; and there are ~12 *empty* tool calls
   (blank code / blank result). Lots of tokens, little signal.

5. **The winning move was good** — `append_reference(editor.document.selection,
   …)` reused the live selection prefix — but it took 40 rounds to discover.

## Candidate directions (probably not the right fixes — for discussion only)

Ordered by apparent leverage, but every one of these needs to be challenged.
The meta-question is whether we are patching symptoms or whether there is a
single deeper change that dissolves several of them at once.

- **C1 — Make the workbench helpers see through Screen/Window.** Have
  `_workbench_page` (and friends) unwrap `ScreenDocument` → `WindowDocument` →
  `WorkbenchWorkbench` (focused/first window). This one is closest to a plain
  bug fix and is probably worth doing on its own merits. *Open:* which window is
  "current" when there are several? Does anything rely on the strict type check?

- **C2 — A select-by-content affordance.** Either a tool like
  `select(query)` / `find_and_select(text)` (run `search_object` +
  `replace_selection!`, one call solves the task), and/or just naming
  `search_object` + `replace_selection!` in the system prompt and making
  `search_api` rank `search_object`. *Open:* is a bespoke "select" tool the
  right grain, or does it paper over a missing general capability? How is the
  target disambiguated when a query matches many nodes? Does a content-string
  query even make sense across domains?

- **C3 — A document-inspection tool.** `inspect_document(; which=focused)`
  returning a text-filtered `print_object` of the focused document, so the model
  reads structure+values in one call instead of hand-walking with `getindex`.
  *Open:* overlaps with `editor.document` introspection the model already does;
  is a tool better than teaching the one-liner?

- **C4 — A short "inspecting documents" cheat-sheet resource** added to the
  MANDATORY list: property access unwraps cells (`getfield`/index don't);
  `editor.document` is a `ScreenDocument` in the running app; `search_object` +
  `replace_selection!` for select-by-content; the
  `append_reference(editor.document.selection, …)` trick. *Open:* the system
  prompt is already long and the model already over-reads — does more required
  reading help or hurt?

- **C5 — Reduce search noise / empty rounds.** Cap and rank `search_*` results;
  investigate the empty tool calls. Lowest priority; purely incremental.

## Things to reconsider before committing to any of the above

- Is the right unit of help a **tool**, a **prompt change**, or an **API
  change** (e.g. making the document model less surprising — cell unwrapping,
  the screen/window wrapper)? Several symptoms above are really "the API is
  surprising to a non-resident reader," which no amount of tooling fully fixes.
- Should the assistant operate on **raw documents** at all, or on a **stable,
  flattened view** (a façade that hides Screen/Window/Cell mechanics and exposes
  "the document the user is looking at" + "select this")?
- How much of this is **model-version specific** vs. a genuine system gap? Worth
  re-running the same prompt after C1 alone to see how much the broken helper
  accounted for.
- What is the **success metric**? Rounds-to-completion on a small suite of
  "select / find / edit X" prompts would let us evaluate any change instead of
  arguing from one transcript.

## Resolution (decided)

The reframing won. C1–C5 were patches on the wrong layer. The conclusion:

> The bespoke imperative workbench helpers (`list_/get_/open_/close_/
> set_focused_workbench_document*`) were a mistake. The AI can already do all of
> this with the **general primitives** — `search_references` / `search_objects`
> to locate nodes, build an `Operation`, and `evaluate_operation(editor, op)` to
> apply it. The primitives are wrapper-agnostic and transfer across every domain;
> the helpers hardcode the four-page model, re-navigate `editor.document`, and
> therefore break on the real `ScreenDocument`. What was missing was not an API —
> it was **documentation**.

Why the primitives are strictly better here (grounded):

- The workbench operations already **carry their own target** —
  `WorkbenchOpenDocumentOperation(page, entry)` /
  `WorkbenchCloseDocumentOperation(page, index)`, and their `evaluate_operation`
  acts on `op.page.elements` with no `editor.document` navigation. So the only
  thing the helpers added is the brittle `editor.document → page` resolution
  (`_workbench_page`), which search replaces generally.
- "search → build operation → `evaluate_operation`" is exactly what the editor's
  own `read! → evaluate! → print!` loop does, so it is one mental model that works
  for selection, edits, and workbench actions across all domains.

### Work items

1. **Document the workflow.** Extend `guide/editor/finding-and-selecting.md` from
   "find → select" to "find → build operation → evaluate", and add a *Driving
   operations programmatically* section + a workbench example to
   `guide/operations.md` (which already documents `Operation` /
   `evaluate_operation`). List the workbench operations in its table.
2. **Make operations discoverable** — confirm `search_api` surfaces `*Operation`
   types (they are structs → "classes").
3. **Add `resource://guide/operations` to the assistant's MANDATORY list** so the
   AI always learns the operation-centric path.
4. **Remove the helper family** (`_workbench_page`, `_resolve_workbench_index`,
   `_focused_index`, `open_workbench_document!`, `open_workbench_file!`,
   `close_workbench_document!`, `list_workbench_documents`,
   `get_workbench_document`, `get_focused_workbench_document`,
   `set_focused_workbench_document!`) and their exports. **Keep** the operation
   types (`WorkbenchOpenDocumentOperation` / `WorkbenchCloseDocumentOperation`) —
   they are the real, general API.
5. **Rewrite the `McpTest` cases** that used the helpers to use
   `search_objects` / `search_references` + the operations.

## Status

Resolved; implementing the work items above. The "candidate directions" C1–C5
are retained only as a record of the symptom-level thinking that the resolution
replaced.
