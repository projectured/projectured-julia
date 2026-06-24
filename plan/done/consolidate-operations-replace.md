# Consolidating operations into `ReplaceReferencedValue`

> **Status (COMPLETE, 2026-06-24): merged to `main`; plan moved to `done/`.** Done:
> step 1 (keystone — `ReplaceReferencedValue` a reader-list citizen + the
> `document === nothing` rule), step 2 (Group 2 widget-state writes), step 3
> (`ReplaceDocumentOperation`), step 4 (Group 4 `Collection*`/Workbench sequence
> edits), step 6 (closed the latent reroot gap in the WorkbenchToWidget/`_retarget_op`
> readers), step 8 (docs). **Two steps were investigated and deliberately dropped:
> step 5** (fold `String`/`NumberReplaceRange` — dispatch-load-bearing; ~19 reader
> methods specialize on the type) **and step 7** (fold Group 2b — empirically tested:
> the projection's own derived output cell flips fine, but the projection-*composition*
> boundary (`SequentialProjection` reads each stage's `.output` once as a raw value,
> `_fixed_print` freezes children) consumes a stage's output exactly once at print
> time, so a Cell-output crashes the pipeline and even unwrapping it doesn't propagate;
> the `editor.iomap` drop forces the one re-print the frozen composition needs). Outcome: `ReplaceDocumentOperation`, the six
> widget-state ops, and the `Collection*`/Workbench ops are folded into
> `ReplaceReferencedValue` + builders (`replace_document`/`insert_elements`/`delete_elements`);
> reader rerooting is consistent and the latent gap is closed; `String`/`Number`,
> Group 2b, `SelectTab`, and the irreducibles stay distinct by design. See
> [Migration steps](#migration-steps).
>
> Background: a 2026-06-24 re-survey (a) widened the inventory to operations added
> since the 2026-06-23 audit (Group 2 widget-state writes, the projection-field
> sub-family, Workbench open/close, new irreducibles), and (b) **re-ordered the
> migration to lead with the easy, clear-benefit, reader-simplifying steps**. The
> headline win is collapsing the *two* hand-maintained, "kept-in-sync"
> reference-rerooting dispatch lists in the projection readers
> (`prepend_steps_to_op` + the default `projection_read`) down to a single
> `ReplaceReferencedValue` branch — already shrinking as Groups 1–4 fold in.

## Thesis

Most operations in the editor do one thing: **write a new value into one slot of
some object.** They differ only in *which* object, *which* slot, and *what*
value — yet each is a separate `struct <: Operation` with its own
`evaluate_operation` method, its own constructor, and (for the path-bearing
ones) its own special case in the re-rooting helpers. We already have a generic
operation for this:

```julia
struct ReplaceReferencedValue <: Operation
    document::Any            # root to resolve `reference` against; `nothing` ⇒ editor.document
    reference::ReferencePath # path to the slot being written
    value::Any               # value to write
end
```

No new operation type is needed — `ReplaceReferencedValue` already has the right
shape. This plan finishes the job by collapsing the whole family of single-slot
write operations into it.

The end state is a *small* set of primitive operations: `ReplaceReferencedValue`
for every single-slot write, a structural insert/delete primitive for sequence
growth/shrink, a `CompoundOperation` to bundle a write with a follow-up
selection move, and a handful of genuinely-irreducible operations (control flow,
file/DB I/O, async assistant turns). Everything else disappears.

This is the Julia analogue of the Lisp ProjecturEd `operation/replace-*` family
plus `make-operation/compound`; the existing `CollectionInsertOperation`
docstring already notes the compound precedent.

---

## Current inventory

Source of truth (verified 2026-06-24): the core operations in
[`common/Operation.jl`](../../package/kernel/src/common/Operation.jl), the
primitive replaces in [`document/Primitive.jl`](../../package/kernel/src/document/Primitive.jl),
and the per-domain operation blocks under `package/domain/src/`. Construction
counts are from a repo-wide grep, to gauge migration blast radius. The full set
of `struct … <: Operation` today (excluding the keep-as-is `ReplaceSelectionOperation`):

- **Single-slot writes** (the consolidation targets): `ReplaceDocumentOperation`,
  `HideWidgetOperation`, `ShowWidgetOperation`, `SetScrollBarValueOperation`,
  `ScrollWidgetOperation`, `SetWidgetHoverOperation`,
  `SetWidgetPressedOperation`, `ToggleCollapseOperation`, `ResizeWindowOperation`,
  `ReplaceFocusPartOperation`, `StringReplaceRangeOperation`,
  `NumberReplaceRangeOperation`. (`SelectTabOperation` looks single-slot but is
  **not** — the workbench overloads it into a document-selection move; it is an
  event-like signal, listed under irreducible below.)
- **Structural sequence edits**: `CollectionInsertOperation`,
  `CollectionDeleteOperation`, `WorkbenchOpenDocumentOperation`,
  `WorkbenchCloseDocumentOperation`.
- **Projection-field writes + iomap drop**: `ToggleClipboardSliceDisplayOperation`,
  `ToggleClipboardCollectionDisplayOperation`, `SetVersionCriterionOperation`.
- **Irreducible**: `QuitEditorOperation`, `LoadDocumentOperation`,
  `SaveDocumentOperation`, `ExportDocumentOperation`, `OpenWindowOperation`,
  `CloseWindowOperation`, `DatabaseUpdateOperation`, `DatabaseInsertOperation`,
  `SubmitProseOperation`, `SubmitJuliaOperation`, `SubmitDraftTurnOperation`,
  `ClearInputOperation`, `ResetConversationOperation`, the nine `Composer*`
  operations (`ConversationEditor.jl`), `InvokeWidgetActionOperation`,
  `StartSplitterDragOperation`, `ResizeSplitPaneOperation`,
  `EndSplitterDragOperation`, `MoveRangeOperation`.

### Group 1 — already a replace; fold in directly

| Operation | Root | Slot / value | ctor sites |
|---|---|---|---|
| `ReplaceDocumentOperation(path, document)` | `editor.document` | field cell **or** seq element ← `Document` | 3 |

`ReplaceReferencedValue` is the target — it already has the right three fields
(`document`, `reference`, `value`). `ReplaceDocumentOperation` is the special
case where `document === nothing` (root is the editor document) and the
reference may be empty (whole-root swap). Both share the `_split_terminal_step`
/ `_write_document_slot!` / `_write_value_slot!` machinery in
[`common/Operation.jl`](../../package/kernel/src/common/Operation.jl).

### Group 2 — single-slot writes carrying their target by identity

These already carry the object they mutate (not a path from `editor.document`),
so they map to `ReplaceReferencedValue(target, <relative-ref>, value)`:

| Operation | Becomes | Source |
|---|---|---|
| `HideWidgetOperation(w)` | `ReplaceReferencedValue(w, @reference visible, false)` | `Widget.jl:1131` |
| `ShowWidgetOperation(w)` | `ReplaceReferencedValue(w, @reference visible, true)` | `Widget.jl:1141` |
| `SetWidgetHoverOperation(w, v)` | `ReplaceReferencedValue(w, @reference hovered, v)` | `Widget.jl:1236` |
| `SetWidgetPressedOperation(w, v)` | `ReplaceReferencedValue(w, @reference pressed, v)` | `Widget.jl:1248` |
| `SetScrollBarValueOperation(bar, v)` | `ReplaceReferencedValue(bar, @reference value, clamp(v,0,1))` | `Widget.jl:1173` |
| `ScrollWidgetOperation(sp, Δ)` | `ReplaceReferencedValue(sp, @reference scroll_position, old+Δ)` — reader computes `old+Δ` | `Widget.jl:1151` |
| `ToggleCollapseOperation(node)` | `ReplaceReferencedValue(node, @reference collapsed, !node.collapsed)` — reader computes the flip | `Operation.jl:271` |
| `ResizeWindowOperation(w, ow, oh)` | two writes → a `CompoundOperation` (see below) | `Operation.jl:347` |
| `ReplaceFocusPartOperation(proj, part)` | `ReplaceReferencedValue(proj, @reference part, part)` — if `part_evaluator` is made lazy | `Focusing.jl:74` |

`SetWidgetHoverOperation` / `SetWidgetPressedOperation` are the simplest of the
whole inventory — plain `Bool` writes into a carried widget, no read-modify-write
— so they are the natural first fold (see Migration step 2).

Notes:
- **Clamp/flip/add happen in the reader**, where the current value is readable,
  so the operation stays a pure "write this value here." This is a deliberate
  shift: read-modify-write logic moves from `evaluate_operation` into
  `projection_read`. For `ScrollWidget` and `ToggleCollapse` the reader already
  has the target object in hand, so it can read the current value.
- All Group 2 ops are **identity-rooted** (`document !== nothing`), so once
  `ReplaceReferencedValue` is a citizen of the reader dispatch lists (Migration
  step 1) they bubble up through every container/generic projection **unchanged**
  — no per-op branch is ever needed for them.
- `ResizeWindowOperation` writes two fields (`width`, `height`); express it as
  `CompoundOperation([ReplaceReferencedValue(w, width, …), ReplaceReferencedValue(w, height, …)])`.
- `ReplaceFocusPartOperation(proj, part)` writes `proj.part` **and** the derived
  `proj.part_evaluator` (`Focusing.jl:79`). Either keep a tiny bespoke setter, or
  make the `part_evaluator` a lazily-derived accessor so only `part` needs
  writing — then it folds into `ReplaceReferencedValue(proj, @reference part, part)`.
  Prefer the latter; the evaluator is a pure function of `part`.

### Group 2b — projection-field writes that today drop `editor.iomap`

These flip a flag that selects which child a projection exposes, then null
`editor.iomap` to force a full rebuild:

| Operation | Writes | Source |
|---|---|---|
| `ToggleClipboardSliceDisplayOperation(p)` | `p.display_slice = !p.display_slice` | `ClipboardToAny.jl:212` |
| `ToggleClipboardCollectionDisplayOperation(p)` | `p.display_collection = !…` | `ClipboardToAny.jl:226` |
| `SetVersionCriterionOperation(target, c)` | `target.criterion = c` | `VersioningToAny.jl:150` |

**Why the iomap drop exists today — and why it is not intrinsic.** A naïve reading
says "the field is a `Cell`, so anything derived from it recomputes reactively, no
drop needed." That is the right *principle*, but it does not apply to these three
as currently authored:

- `ClipboardSliceToAnyProjection.display_slice` is a **plain `Bool`, not a `Cell`**
  (`ClipboardToAny.jl:69`), and `projection_print` reads it in an **eager ternary**
  (`:114`: `output = display_slice ? slice_iomap.output : content_iomap.output`).
  The choice is computed *once* and frozen into the iomap — there is no reactive
  dependency for the engine to track, so flipping it changes nothing without a rebuild.
- `VersionedObject.criterion` *is* a `Cell`, yet the drop is still required, which
  exposes the real reason: `projection_print` reads it **eagerly inside the printer**
  (`VersioningToAny.jl:91`: `select_version(input)`) to make a **structural** choice —
  which version's subtree to build a child iomap for. `projection_print` is the
  one-shot *construction* step that builds the cell graph; it is **not itself a
  reactive computation that re-runs when the cell changes**. The reactive engine
  propagates **values** through derived cells it was wired to depend on; it does not
  re-derive **structure** (which child / how many children). Changing the exposed
  child changes structure ⇒ rebuild ⇒ the iomap drop.

> **Empirically tested 2026-06-24 (worktree `clipboard-reactive-test`) — keep these
> distinct; the `editor.iomap` drop is the pragmatic structural-switch mechanism.**
> The appealing idea was: make the flag a `Cell` and express the flag-dependent
> `output` as a *derived cell*, so flipping it recomputes the selection reactively and
> the op folds into a plain `ReplaceReferencedValue`. I built exactly that
> (`display_slice::Cell`, `output = Cell(() -> display_slice[] ? slice_iomap.output :
> content_iomap.output)`, toggle drops the `editor.iomap` reset) and ran it. The
> result is more precise than "the engine can't switch structure":
>
> - **The projection's *own* derived output cell DOES flip reactively** (verified):
>   driving just the clipboard stage, flipping `display_slice[]` and re-reading
>   `iomap.output[]` switches the exposed syntax from content to slice with **no
>   re-print**. The earlier "no reactive structural-switch at all" framing was wrong
>   at this level — the cell machinery works.
> - **The blocker is the projection-*composition* boundary, not the engine.**
>   `SequentialProjection.projection_print` does `current = iomap.output` (Sequential.jl:67)
>   — a **one-time raw read** — and threads `current` as the *next stage's input
>   document*; `_fixed_print` likewise freezes each child via `CellVector(Cell[Cell(im.output)…])`
>   (ProjectionTemplate.jl:358). A stage's output is therefore consumed exactly once at
>   print time. Two consequences, both reproduced:
>   1. Making `output` a `Cell` **crashes the pipeline**: `TypeDispatchingProjection:
>      no projection registered for type Cell` — the `Cell` is threaded downstream as a
>      document to print.
>   2. Even *unwrapping* the cell once at the boundary (the obvious crash fix) **does
>      not propagate**: the downstream stage prints the captured syntax and a later
>      `display_slice[]` flip leaves its output frozen on the old child.
>
> So making Group 2b reactive end-to-end would require re-architecting the print
> *composition* pipeline (wrap each stage's print in a cell that re-pulls upstream
> output), a cross-cutting change far beyond folding one op — not an iomap-invalidation
> hook on the generic op (rejected). For 3 low-value ops that is not worth it: **they
> stay distinct** — a legitimate "switch which child this projection exposes" op, with
> the `editor.iomap` drop forcing the one re-print the frozen composition needs.
> (`ReplaceFocusPartOperation` is *not* a counter-example: its `part` change is re-read
> by the printer to navigate, a value change, not a structural child-swap — which is
> why it needs no drop.) See [Migration step 7](#migration-steps). Experiment harness
> kept at `experiment_group2b.jl` on branch `clipboard-reactive-test`.

### Group 3 — sub-value *range* writes (string/number) — **KEEP (reclassified)**

| Operation | ctor sites |
|---|---|
| `StringReplaceRangeOperation(reference, replacement)` | 47 |
| `NumberReplaceRangeOperation(reference, replacement)` | 11 |

> **Reclassified to keep (2026-06-24, after a trial fold + revert).** These look
> like a `RangeReference` splice into a primitive value field — superficially a
> `ReplaceReferencedValue` shape — but the *type* is **load-bearing for dispatch**:
> ~19 `projection_read(p, iomap, op::StringReplaceRangeOperation)` methods across
> ~12 projections specialize on it with non-trivial per-projection char-edit logic
> (`SyntaxToText`/`SyntaxToWidget` span↔flat mapping, `ObjectToWidget` control-edit
> parsing, `TextFiltering`/`TextHighlighting`/`WordWrapping`/`SelectionInverting`/
> `TextFirstLine`/`XmlToSyntax`/`BookToSyntax`/…). They intercept *only* char-range
> edits via the type; folding into the generic `ReplaceReferencedValue` would erase
> that dispatch key and force a value-guard + generic-retarget tail into all 19
> methods — more code, more fragile, on the most-used feature. So these are a
> genuine distinct operation — *character-range edits* — and **stay**, alongside
> `ReplaceSelectionOperation`. (Character splicing keeps living in the
> representation-dispatched `splice_value!`, `Primitive.jl`.) See
> [Migration step 5](#migration-steps) for the full rationale and the reverted trial.

### Group 4 — structural sequence edits (splice via `RangeReference`)

| Operation | Root | ctor sites |
|---|---|---|
| `CollectionInsertOperation(path, index, items, selection)` | `editor.document` | ~8 |
| `CollectionDeleteOperation(path, index, count)` | `editor.document` | ~6 |
| `WorkbenchOpenDocumentOperation(page, entry)` | `page` (by identity) | ~few |
| `WorkbenchCloseDocumentOperation(page, index)` | `page` (by identity) | ~few |

These grow/shrink a sequence, but `RangeReference` terminal dispatch already
handles splice semantics for strings. The same logic extends to `CellVector`:

| Operation | Becomes |
|---|---|
| `CollectionInsertOperation(path, i, items)` | `ReplaceReferencedValue(nothing, path / RangeReference(i, i), items)` — zero-width range = pure insert |
| `CollectionDeleteOperation(path, i, count)` | `ReplaceReferencedValue(nothing, path / RangeReference(i, i+count), [])` — replace range with empty = delete |
| `WorkbenchOpenDocumentOperation(page, entry)` | `ReplaceReferencedValue(page, @reference(elements) / RangeReference(n, n), [entry])` — identity-rooted append (`n = length`) |
| `WorkbenchCloseDocumentOperation(page, i)` | `ReplaceReferencedValue(page, @reference(elements) / RangeReference(i-1, i), [])` — identity-rooted delete |

Element *replacement* (delete-then-insert at same position) falls out for free
as `ReplaceReferencedValue(nothing, path / RangeReference(i, i+1), [new_item])`.

The Workbench pair already carry their `page` by identity (`Workbench.jl:364,381`),
so they map to the **identity-rooted** form (`document !== nothing`) and bubble up
unchanged — like Group 2. The two `Collection*` ops are `editor.document`-rooted.

The `selection` field on `CollectionInsertOperation` becomes the second half of a
`CompoundOperation([splice, ReplaceSelectionOperation(cursor_path)])`, matching
the pattern used for Group 3.

`MoveRangeOperation` (`Dragging.jl:112`) is *almost* Group 4 — it is a delete from
the source range plus an insert at the destination — but it **relocates the raw
`Cell`s to preserve element identity**, which a delete-`[]`-then-insert-copies
splice would not. Expressing it as a `CompoundOperation` of two splices loses that
identity guarantee, so it stays irreducible (Group 5) unless splice grows an
identity-preserving move variant. Low value; leave alone.

### Group 5 — genuinely irreducible; leave alone

These do something other than write a document slot, so they stay as distinct
operations:

| Operation | Why it stays |
|---|---|
| `QuitEditorOperation` | control flow — throws `QuitEditorException` |
| `LoadDocumentOperation` | reads a file (value unknown until I/O runs) |
| `SaveDocumentOperation` | writes a file; no document mutation |
| `ExportDocumentOperation` | writes a file; no document mutation |
| `OpenWindowOperation` / `CloseWindowOperation` | intercepted by `WindowManagerProjection`; append/remove on `screen.windows` (structural) |
| `DatabaseUpdateOperation` / `DatabaseInsertOperation` | external SQL via an adapter, not a document write |
| `SubmitProseOperation` | async Claude turn + multi-field mutation |
| `SubmitJuliaOperation` | evaluates code, appends messages |
| `SubmitDraftTurnOperation` | async assistant turn (`WorkbenchAssistant.jl:283`) |
| `ClearInputOperation` / `ResetConversationOperation` | multi-field assistant resets — *could* become `CompoundOperation`s of `ReplaceOperation`s, optional follow-up |
| nine `Composer*` operations | each manipulates the active conversation part (insert/parse/commit/revert/submit) on a carried `draft`; structural + parsing logic, not a single-slot write (`ConversationEditor.jl:128`–`186`) |
| `InvokeWidgetActionOperation` | calls the widget's `action` callable (`Widget.jl:1225`) — arbitrary control flow |
| `SelectTabOperation` | event-like "tab i clicked"; the workbench overloads it into a document-selection move (`WorkbenchPageToWidgetTabbedPane`), so not a single-slot write (`Widget.jl:1163`) |
| `StartSplitterDragOperation` | materialises `sizes`/`pinned` vectors and records a `drag_anchor` tuple — multi-field + conditional vector init (`Widget.jl:1187`) |
| `ResizeSplitPaneOperation` | writes `sizes[k]`,`sizes[k+1]` **and** pins both slots — multi-field with a length guard (`Widget.jl:1202`) |
| `EndSplitterDragOperation` | resets `active_splitter`+`drag_anchor` — two writes; could be a trivial `CompoundOperation`, but the drag-state trio reads cleaner together (`Widget.jl:1214`) |
| `MoveRangeOperation` | identity-preserving cell relocation between `CellVector`s (see Group 4 note) |

### `ReplaceSelectionOperation` — a special case, keep it

`ReplaceSelectionOperation(path)` does **not** write one slot: it walks the path
and writes the relevant suffix into the `selection` cell at *every* level
(`clear_selection!` then `set_selection!`). That recursive multi-slot write is
genuinely different from `ReplaceOperation`. Keep it as its own operation; it is
also the most-constructed operation (100 sites) and the natural second half of
every edit compound.

---

## The re-rooting rule (the key design decision)

Reference-bearing operations are re-targeted by the projection readers in **two**
hand-maintained dispatch lists that must be kept in lock-step (each carries an
explicit `INVARIANT:` comment pointing at the other):

1. **`prepend_steps_to_op`** in
   [`common/OperationRerooting.jl:49`](../../package/kernel/src/common/OperationRerooting.jl#L49)
   — a container projection (split pane, layout, composite) **prepends** the steps
   that lead from itself to the child the operation came from. Today it has a
   branch per op type (`ReplaceSelectionOperation`, `StringReplaceRangeOperation`,
   `NumberReplaceRangeOperation`, `ReplaceDocumentOperation`,
   `CollectionInsertOperation`, `CollectionDeleteOperation`, `CompoundOperation`)
   and its `else` returns the op **unchanged**.
2. **the default `projection_read`** in
   [`common/Projection.jl:81`](../../package/kernel/src/common/Projection.jl#L81)
   — a generic projection (sorting, reversing, copying, …) re-targets the
   operation's reference from output space to input space via
   `map_reference_backward`. It has the *same* per-op branches, plus a
   `ToggleCollapseOperation` pass-through, and its `else` returns **`nothing`
   (drops the op)**.

> **Latent inconsistency the consolidation fixes.** The two `else` branches
> disagree: `prepend_steps_to_op` passes an unrecognised op through unchanged,
> while `projection_read` drops it. `ReplaceReferencedValue` is in **neither**
> list, so today an identity-rooted `ReplaceReferencedValue` (produced by
> `ObjectToWidget`/`WidgetToGraphics` controls) is silently dropped if it ever
> traverses a generic `projection_read`. Making `ReplaceReferencedValue` a
> first-class citizen of both lists (Migration step 1) is the fix.

Once all single-slot writes are `ReplaceReferencedValue`, use the `document` field
as the signal in **both** lists:

- **`document === nothing`** ⇒ reference is rooted at `editor.document`; container
  projections **prepend their steps** / generic projections **`map_reference_backward`**
  the `reference` as the operation flows up.
- **`document !== nothing`** ⇒ self-contained (root is a carried object like a
  widget); the operation **passes through unchanged** in both lists.

This collapses the per-op branches in `prepend_steps_to_op` into one:

```julia
function prepend_steps_to_op(op::ReplaceReferencedValue, steps::Tuple)
    op.document === nothing || return op           # self-contained: pass through
    ReplaceReferencedValue(nothing, prepend_steps_to_ref(op.reference, steps), op.value)
end
```

and, symmetrically, the branches in the default `projection_read`:

```julia
function _read_replace(projection, iomap, op::ReplaceReferencedValue)
    op.document === nothing || return op           # self-contained: pass through
    ref = map_reference_backward(projection, iomap, op.reference)
    ref === nothing ? nothing : ReplaceReferencedValue(nothing, ref, op.value)
end
```

`evaluate_operation` resolves the root symmetrically:

```julia
function evaluate_operation(editor, op::ReplaceReferencedValue)
    root = op.document === nothing ? editor.document : op.document
    # empty reference ⇒ whole-root swap (today's ReplaceDocumentOperation branch)
    # else split terminal step; dispatch FieldReference vs RangeReference
end
```

---

## Evaluation: one method, terminal-dispatched

`evaluate_operation(editor, op::ReplaceReferencedValue)`:

1. `root = op.document === nothing ? editor.document : op.document`.
2. If `op.reference` is `EmptyReferencePath`: whole-root swap (rebind
   `editor.document`, drop cached `iomap`) — only meaningful when
   `document === nothing`. (Today's `ReplaceDocumentOperation` empty-path branch.)
3. Else split into `(parent_path, terminal)`; `parent = parent_path is empty ?
   root : evaluate_reference(root, parent_path)`.
4. Dispatch on `terminal`:
   - `FieldReference` → write `op.value` into the `Cell`-backed field
     (reuse `_write_value_slot!` / `_write_document_slot!`).
   - `RangeReference` → splice into the target sequence/string (reuse the
     representation-dispatched `splice_value!` for primitives; element
     overwrite/insert/delete for a `CellVector`, as `_write_document_slot!` and the
     `Collection*` evaluators do today).

Selection follow-up is **never** inside `ReplaceReferencedValue` — it is a sibling
`ReplaceSelectionOperation` inside a `CompoundOperation`.

---

## `CompoundOperation`

```julia
struct CompoundOperation <: Operation
    operations::Vector{Operation}
end
evaluate_operation(editor, op::CompoundOperation) =
    foreach(o -> evaluate_operation(editor, o), op.operations)
```

Re-rooting maps over the children. This absorbs the "write then move cursor"
shape currently baked into the range-replace ops and the optional `selection`
field of `CollectionInsertOperation`, matching Lisp `make-operation/compound`.

---

## Migration steps

> **Re-staged 2026-06-24.** The order below is deliberately **easiest-and-clearest
> first**, front-loading the steps that simplify *reference updating in the
> projection readers*. Each step is purely additive or a single-family fold, so it
> lands as one commit with one narrow test, and a regression bisects to one step.
> Status legend: ✅ done · 🟢 easy/clear-benefit · 🟡 medium · 🔴 high blast radius.

0. **✅ DONE:** **`CompoundOperation` scaffold** — exists at
   [`Operation.jl:36`](../../package/kernel/src/common/Operation.jl#L36) with a
   varargs ctor (`:40`) and a map-over-children evaluator (`:42`); re-rooting maps
   over the children (`OperationRerooting.jl:68`) and the default `projection_read`
   maps over them too (`Projection.jl:122`). The `_split_terminal_step` /
   `_write_document_slot!` / `_write_value_slot!` helpers are present
   (`Operation.jl:134,152,193`). (Its docstring still frames it as the clipboard-cut
   helper — update when it becomes the range/cursor compound.)

1. **✅ DONE (commit `c2af0f1`, on `main`):** keystone,
   purely additive — make `ReplaceReferencedValue` capable + a reader-list citizen.
   No existing op changed; behavior-preserving for current callers (all
   identity-rooted, non-empty `FieldReference`). Landed:
   - **Evaluator** (`Operation.jl:180`): `root = document===nothing ? editor.document : document`;
     **empty-reference ⇒ whole-root swap** when `document === nothing` (rebind
     `editor.document`, drop iomap). *Deferred to steps 4/5:* the terminal
     `RangeReference` ⇒ splice branch — it is only exercised once Groups 3/4 are
     folded, and is cleanest to add alongside them where `splice_value!` / the
     `CellVector` ops are in scope and there is a test.
   - **`prepend_steps_to_op`** (`OperationRerooting.jl:49`): reroot when
     `document === nothing`, pass through otherwise.
   - **default `projection_read`** (`Projection.jl:81`): `map_reference_backward` the
     reference when `document === nothing`, pass through unchanged when
     `document !== nothing` (also fixes the latent drop of identity-rooted
     `ReplaceReferencedValue`).
   - *Verified:* `test_object_to_widget`, `test_widget_text_editing`,
     `test_widget_button_behavior`, `test_versioning_to_any`, `test_clipboard_to_any`,
     `test_repl(json_example)` all green. (`test_split_pane_drag` shows 8 failures, but
     they are **pre-existing on clean `main`** — confirmed by a baseline run — and
     unrelated to this change.)

2. **✅ DONE (commit `0514e91`):** fold Group 2 identity-rooted widget-state writes.
   Deleted six structs + evaluators; the read-modify-write/clamp/path arithmetic
   moved into the producing readers. Added a
   `ReplaceReferencedValue(obj, field::AbstractString, value)` convenience ctor.
   - `SetWidgetHover`/`SetWidgetPressed` → `ReplaceReferencedValue(w, "hovered"/"pressed", v)`
   - `HideWidget`/`ShowWidget` → `"visible", false/true`
   - `SetScrollBarValue` → `"value", clamped` (the producer already clamped)
   - `ScrollWidget` → `"scroll_position", old+Δ` (reader reads `old` via `iomap.input`)
   - **`SelectTabOperation` was NOT folded** (correction to the original plan): the
     workbench *overloads* it into a document-selection move
     (`WorkbenchPageToWidgetTabbedPane` returns `ReplaceSelectionOperation(@reference elements[idx])`,
     since the tab's active state is a forward projection of the page selection). It
     is an event-like signal, not a single-slot write — left in Group 5.
   - Two bespoke readers updated: `TextToWidget` (was matching `ScrollWidgetOperation`)
     now passes identity-rooted `ReplaceReferencedValue` through;
     `WidgetHoverTracking._target_of` reads the target widget from `.document` (the
     folded hover/press op has no `.widget` field). Tests: `WidgetButtonTest`,
     `ProjectionConfiguringTest`.
   - *Verified:* `test_widget_button_behavior`, `test_projection_configuring`,
     `test_object_to_widget` all green; `test_repl(workbench_example)` 225/225;
     `test_split_pane_drag` unchanged at the pre-existing 23/8 baseline.

3. **✅ DONE (commit `eefa529`):** fold `ReplaceDocumentOperation` →
   `replace_document(path, doc)`, a helper that builds
   `CompoundOperation([ReplaceReferencedValue(nothing, path, doc), ReplaceSelectionOperation(path ⧺ doc.selection)])`
   — re-rooting prepends the same steps to both members, keeping write+cursor in
   sync; empty path is the whole-root swap from step 1. The struct + evaluator are
   deleted; `evaluate_operation(ReplaceReferencedValue)` now writes via the shared
   `_write_slot!` (FieldReference cell-write **or** RangeReference element-overwrite),
   covering the array-element replace. **Removed its branch from both central reader
   lists**, and taught the three bespoke `_prefix_op` re-rooting readers (ScreenToScreen,
   ClipboardToAny, VersioningToAny) to handle `ReplaceReferencedValue` + `CompoundOperation`
   (the latter two previously dropped compounds). Producers swapped: `Json._replace`,
   `XmlToSyntax`, `DocumentInsertion`, all six clipboard sites.
   - *Verified:* `test_json_to_syntax` 11/11; `test_json_to_syntax_reader` 47/1 (the 1
     is the pre-existing array-insert baseline); `test_xml_to_syntax_reader` 32/32;
     `test_document_insertion` 14/14; clipboard, versioning, dragging,
     `test_repl(json_example)`, `test_repl(workbench_example)` all green.

4. **✅ DONE (commit `5894a80`, on `main`):** fold
   Group 4 structural sequence edits.
   - `CollectionInsertOperation`/`CollectionDeleteOperation` deleted; replaced by the
     `insert_elements(path, index, items[, selection]; root)` and
     `delete_elements(path, index[, count]; root)` builders → a `ReplaceReferencedValue`
     whose terminal step is a `RangeReference` (zero-width = insert, range+empty =
     delete). A new `_write_slot!(parent, ::RangeReference, items::AbstractVector)`
     does the splice; a single (non-vector) value still hits the element-overwrite
     method. `insert` with a selection appends a trailing `ReplaceSelectionOperation`
     in a `CompoundOperation`.
   - `WorkbenchOpenDocumentOperation`/`WorkbenchCloseDocumentOperation` are now
     builder functions returning an identity-rooted splice (`root=page`; close
     converts its 1-based index to 0-based).
   - **Removed both `Collection*` branches from ALL FIVE reader dispatchers**
     (`prepend_steps_to_op`, default `projection_read`, and the ScreenToScreen /
     Clipboard / Versioning `_prefix_op` readers). *Verified:* `xml_reader`,
     `versioning`, `clipboard`, `doc_insertion`, `workbench_b1`, `dragging`,
     `object_to_widget`, `test_repl(json_example)`, `test_repl(workbench_example)`
     green; `json_reader` 47/1 (pre-existing array-insert selection baseline).

5. **❌ WON'T DO (attempted 2026-06-24, reverted) — do NOT fold
   `String`/`NumberReplaceRange` into `ReplaceReferencedValue`.** The operation
   *type* is **load-bearing for dispatch**: ~19 `projection_read(p, iomap, op::StringReplaceRangeOperation)`
   methods across ~12 projections (`SyntaxToText`/`SyntaxToWidget` span↔flat mapping,
   `ObjectToWidget` control-edit parsing, `TextFiltering`/`TextHighlighting`/
   `WordWrapping`/`SelectionInverting`/`TextFirstLine`/`XmlToSyntax`/`BookToSyntax`/…)
   specialize on it with **non-trivial per-projection char-edit logic**, intercepting
   *only* character-range edits via the type. Folding it into the generic
   `ReplaceReferencedValue` erases that dispatch key: every one of those 19 methods
   would have to become `op::ReplaceReferencedValue` + an internal value-guard
   (`document === nothing && value isa AbstractString && RangeReference terminal`) +
   an `invoke`/replicated generic-retarget tail for the non-char RRVs they'd now also
   catch — **more** code and more fragile than the current clean type-dispatch, on the
   most-used feature (text editing). A trial fold (shim + char-splice evaluator + reader
   reconciliation) was implemented and **reverted** at `bfc139c` once the 19-method
   dispatch surface became clear. **Conclusion:** `String`/`NumberReplaceRange` are a
   legitimate distinct operation — *character-range edits* — not a single-slot write.
   They join `ReplaceSelectionOperation` as kept-by-design (Group 3 is reclassified as
   "keep" in the inventory). The 2-line splice cleanup (a `RangeReference`+`CellVector`
   element/insert/delete handler living in one place) was already achieved for Group 4;
   character splicing stays in `Primitive.splice_value!`.

6. **✅ DONE (commit `89a12de`, on `main`) — closed the
   latent reroot gap for the folded ops.** Steps 3–4 taught the five main dispatchers
   about `ReplaceReferencedValue`/`CompoundOperation`, but the *bespoke* re-rooting
   readers were missed, so a folded `replace_document`/`insert_elements`/`delete_elements`
   op flowing through one was passed through unrerooted (or dropped):
   - `WidgetToGraphics._retarget_op` — added `ReplaceReferencedValue` (reroot via
     `map_reference_backward` when `document === nothing`; self-contained passes
     through) + `CompoundOperation` branches.
   - `WorkbenchToWidget` — the shell reader and `_retarget_panel_op` gained the same
     two branches; **`_prefix_operation` now delegates to the shared
     `prepend_steps_to_op`** (which already handles RRV/Compound), so the duplicated
     `_prepend_path` helper was deleted — the small dedup the reframed step aimed for.
   - `ProjectionConfiguring` already **delegates** document edits to the inner reader
     (so the inner chain reroots them), and the **ODBC** tabular reader only handles
     cell text edits (`String`/`Number`) that structural folded ops never reach — both
     left unchanged after confirming they aren't gaps.
   - `String`/`Number` branches stay (distinct op per step 5).
   - *Verified:* object_to_widget, widget_button, projection_configuring, clipboard,
     versioning, document_insertion, dragging, `test_repl(json_example)`,
     `test_repl(workbench_example)` all green; split_pane_drag unchanged at the
     pre-existing 23/8 baseline; `database_tabular` errored only on a live-DB SQL
     teardown (environmental).

7. **❌ WON'T DO (empirically tested 2026-06-24, worktree `clipboard-reactive-test`)
   — leave Group 2b (`Toggle{Clipboard…Display}` + `SetVersionCriterion`) as distinct
   ops.** I built the reactive version (`display_slice::Cell`,
   `output = Cell(() -> display_slice[] ? slice_iomap.output : content_iomap.output)`,
   toggle does a plain cell write with **no** `editor.iomap` drop) and ran it through
   the real clipboard pipeline. The finding is more precise than the earlier
   analysis-only claim:

   - **The projection's *own* derived output cell flips reactively** — verified by
     driving the clipboard stage alone: flipping `display_slice[]` and re-reading
     `iomap.output[]` switches the exposed syntax content→slice with no re-print. So
     "there is no reactive structural-switch *at all*" was wrong; the cell works.
   - **The blocker is the projection-*composition* boundary.**
     `SequentialProjection.projection_print` does `current = iomap.output`
     (Sequential.jl:67) — a one-time raw read — and threads `current` as the next
     stage's input *document*; `_fixed_print` freezes each child via
     `CellVector(Cell[Cell(im.output)…])` (ProjectionTemplate.jl:358). A stage's output
     is consumed exactly once at print time. Reproduced consequences:
     1. A `Cell`-valued output **crashes the pipeline**: `TypeDispatchingProjection:
        no projection registered for type Cell` (the `Cell` is threaded downstream as a
        document).
     2. Even *unwrapping* the cell once at the boundary **does not propagate**: the
        downstream stage prints the captured syntax; a later flip leaves it frozen.
   - The clipboard/versioning projections also output the **active child's type
     directly (no wrapper)** — required by the chain's type contract (the parent
     expects e.g. a `SyntaxNode`) — so a "derived content cell in a stable wrapper"
     would change the output type and break the chain anyway.

   So making Group 2b reactive end-to-end would require re-architecting the print
   *composition* pipeline (each stage's print wrapped in a cell that re-pulls upstream
   output), not an iomap-invalidation hook on the generic op (rejected). For 3
   low-value ops that is not worth it. **They stay distinct** (a legitimate "switch
   which child this projection exposes" operation, the `editor.iomap` drop forcing the
   one re-print the frozen composition needs), alongside `ReplaceSelectionOperation`
   and the Group 3 range edits. `ToggleCollapseOperation` likewise stays (its `nothing`-target
   resolution at the SyntaxToText layer is also non-trivial). `ReplaceFocusPartOperation`
   could still fold *if* `part_evaluator` were made lazy, but it is a single op of
   marginal value — defer.

8. **✅ DONE (commits `33e767c`, `343d9d6`, on `main`):** Docs.
   [`documentation/operations.md`](../../documentation/operations.md) leads with the
   generic `ReplaceReferencedValue` (rooting rule, terminal-kind dispatch, the
   `replace_document`/`insert_elements`/`delete_elements` builder table, `CompoundOperation`),
   tells authors to prefer the generic op, and both `INVARIANT:` notes are updated. The
   "remain distinct" table records the kept-by-design ops with their rationale —
   `String`/`NumberReplaceRange` (dispatch-load-bearing, step 5), `SelectTabOperation`,
   the Group 2b `Toggle…Display`/`SetVersionCriterion` (structural switches, step 7),
   `MoveRange`, control-flow/I/O/async ops. Stale references in `widget.md`,
   `versioning.md`, `architecture.md`, `concepts.md`, `orientation.md`, `editor.md`,
   `tutorial-new-domain.md`, `roadmap.md` were updated to the generic operations.

9. **Leave alone — Group 5 irreducible** + `ReplaceSelectionOperation` (the
   multi-slot recursive selection write, `Operation.jl:74`). No work; listed for
   completeness.

---

## Testing

Per [CLAUDE.md](../../CLAUDE.md), run the narrowest test per stage rather than
`test_all`:

- Editor-level operation evaluation: `test_repl(<example>)` /
  `test_repls()` after the keystone step 1 — the REPL tests drive
  reader → operation → evaluate end-to-end.
- String/number range folding (step 5): the primitive-to-text and selection tests
  (`test_selection(<example>)`, `PrimitiveToTextTest`) exercise the cursor
  follow-up most directly.
- Widget ops (step 2): the widget/workbench examples (`test_repl(workbench_example)`),
  `WidgetButtonTest`, `SplitPaneDragTest`.
- Re-rooting itself is best covered by container examples (split pane, layout,
  tabbed pane) — pick one `test_repl` per container after step 1.

Do each fold as its own commit so a regression bisects to a single operation
family.

---

## Open questions

1. **`document === nothing` as the reroot signal** — clean, but it means "root is
   editor document" is encoded by a sentinel rather than a type. Acceptable, or
   prefer an explicit `rooted_at_document::Bool`? (Recommendation: sentinel; it
   mirrors the existing empty-path-means-root convention and
   `ReplaceReferencedValue` already uses it this way.)
2. **Read-modify-write moving into readers** (scroll delta, collapse flip) —
   fine for current readers (they hold the target), but if any future producer
   lacks the current value, it would need a `ToggleOperation`-style primitive.
   Flagging, not blocking.
3. **Inverse / undo for sequence splices** — `CollectionInsert` and
   `CollectionDelete` are currently defined inverses of each other. Once both
   are `ReplaceReferencedValue` with a `RangeReference`, their inverse
   relationship is implicit (swap range bounds and replacement). Confirm this is
   sufficient for undo, or add an explicit inverse helper.
4. **Whether `ClearInput`/`ResetConversation` should become `CompoundOperation`s**
   — low value (two assistant-local resets), optional.
