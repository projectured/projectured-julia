# Consolidating operations into a single `ReplaceOperation`

## Thesis

Most operations in the editor do one thing: **write a new value into one slot of
some object.** They differ only in *which* object, *which* slot, and *what*
value — yet each is a separate `struct <: Operation` with its own
`evaluate_operation` method, its own constructor, and (for the path-bearing
ones) its own special case in the re-rooting helpers. This is the same insight
that already produced `ReplaceDocumentOperation` and `ReplaceReferencedValue`;
this plan finishes the job by collapsing the whole family into one operation:

```julia
struct ReplaceOperation <: Operation
    document::Any            # root to resolve `reference` against; `nothing` ⇒ editor.document
    reference::ReferencePath # path to the slot being written
    replacement::Any         # value to write
end
```

The end state is a *small* set of primitive operations: `ReplaceOperation` for
every single-slot write, a structural insert/delete primitive for sequence
growth/shrink, a `CompoundOperation` to bundle a write with a follow-up
selection move, and a handful of genuinely-irreducible operations (control flow,
file/DB I/O, async assistant turns). Everything else disappears.

This is the Julia analogue of the Lisp ProjecturEd `operation/replace-*` family
plus `make-operation/compound`; the existing `CollectionInsertOperation`
docstring already notes the compound precedent.

---

## Current inventory

Source of truth: [`api/Operation.jl`](../../program/src/api/Operation.jl),
[`common/Operation.jl`](../../program/src/common/Operation.jl), and the
per-domain operation blocks. Construction counts are from a repo-wide grep, to
gauge migration blast radius.

### Group 1 — already a replace; fold in directly

| Operation | Root | Slot / value | ctor sites |
|---|---|---|---|
| `ReplaceReferencedValue(document, reference, value)` | explicit `document` | field cell ← scalar | 11 |
| `ReplaceDocumentOperation(path, document)` | `editor.document` | field cell **or** seq element ← `Document` | 3 |

`ReplaceReferencedValue` *is* `ReplaceOperation` already — same three fields,
same name order. `ReplaceDocumentOperation` is the special case where
`document === nothing` (root is the editor document) and the reference may be
empty (whole-root swap). Both share the `_split_terminal_step` /
`_write_document_slot!` / `_write_value_slot!` machinery in
[`common/Operation.jl`](../../program/src/common/Operation.jl).

### Group 2 — single-slot writes carrying their target by identity

These already carry the object they mutate (not a path from `editor.document`),
so they map to `ReplaceOperation(target, <relative-ref>, value)`:

| Operation | Becomes |
|---|---|
| `HideWidgetOperation(w)` | `ReplaceOperation(w, @reference visible, false)` |
| `ShowWidgetOperation(w)` | `ReplaceOperation(w, @reference visible, true)` |
| `SetScrollBarValueOperation(bar, v)` | `ReplaceOperation(bar, @reference value, clamp(v,0,1))` |
| `SelectTabOperation(pane, i)` | `ReplaceOperation(pane, @reference selection, ElementReference(i)-path)` |
| `ScrollWidgetOperation(sp, Δ)` | `ReplaceOperation(sp, @reference scroll_position, old+Δ)` — reader computes `old+Δ` |
| `ToggleCollapseOperation(node)` | `ReplaceOperation(node, @reference collapsed, !node.collapsed)` — reader computes the flip |
| `ResizeWindowOperation(w, ow, oh)` | two writes → a `CompoundOperation` (see below) |

Notes:
- **Clamp/flip/add happen in the reader**, where the current value is readable,
  so the operation stays a pure "write this value here." This is a deliberate
  shift: read-modify-write logic moves from `evaluate_operation` into
  `projection_read`. For `ScrollWidget` and `ToggleCollapse` the reader already
  has the target object in hand, so it can read the current value.
- `ResizeWindowOperation` writes two fields (`width`, `height`); express it as
  `CompoundOperation([ReplaceOperation(w, width, …), ReplaceOperation(w, height, …)])`.
- `ReplaceFocusPartOperation(proj, part)` writes `proj.part` **and** the derived
  `proj.part_evaluator`. Either keep a tiny bespoke setter, or make the
  `part_evaluator` a lazily-derived accessor so only `part` needs writing — then
  it folds into `ReplaceOperation(proj, @reference part, part)`. Prefer the
  latter; the evaluator is a pure function of `part`.

### Group 3 — sub-value *range* writes (string/number)

| Operation | ctor sites |
|---|---|
| `StringReplaceRangeOperation(reference, replacement)` | 47 |
| `NumberReplaceRangeOperation(reference, replacement)` | 11 |

These splice a string into a character range whose terminal step is a
`RangeReference`, then move the cursor. They fold into `ReplaceOperation` if
**evaluation dispatches on the terminal step kind**:

- terminal `FieldReference` → overwrite the whole cell value (Group 1/2 path);
- terminal `RangeReference` → splice `replacement` into the target's
  string/sequence at `[start, stop]` (today's `_apply_string_replace!` /
  `_apply_number_replace!`, which already dispatch on target type).

The cursor-move-after-edit is **not** part of the write — model it as a
`CompoundOperation([replace, ReplaceSelectionOperation(cursor_path)])`, matching
how `_replace_selection_with_cursor!` currently runs as a second step. String vs
number is a property of the *target type*, not the operation, so the two ops
merge into one path. (47+11 = 58 construction sites — the bulk of the migration;
most are in tests and can be updated mechanically, or kept working via a
deprecated constructor shim during transition.)

### Group 4 — structural sequence edits (NOT a replace)

| Operation | Why it can't be a `ReplaceOperation` |
|---|---|
| `CollectionInsertOperation(path, index, items, selection)` | grows a sequence; no existing slot to overwrite |
| `CollectionDeleteOperation(path, index, count)` | shrinks a sequence |

Keep these as a structural primitive. Two reasonable shapes:
1. leave `CollectionInsert`/`CollectionDelete` as-is (they're already a clean
   pair with a defined inverse), or
2. unify them into one `SpliceOperation(reference, index, count, items)` (delete
   `count` then insert `items`), of which insert (`count=0`) and delete
   (`items=[]`) are special cases — and which makes element *replacement* a
   splice too. Worth considering but **out of scope** for the first pass; this
   plan's `ReplaceOperation` covers only single-slot writes.

The `selection` field on `CollectionInsertOperation` becomes the compound
follow-up instead of an operation field (see `CompoundOperation`).

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
| `ClearInputOperation` / `ResetConversationOperation` | multi-field assistant resets — *could* become `CompoundOperation`s of `ReplaceOperation`s, optional follow-up |

### `ReplaceSelectionOperation` — a special case, keep it

`ReplaceSelectionOperation(path)` does **not** write one slot: it walks the path
and writes the relevant suffix into the `selection` cell at *every* level
(`clear_selection!` then `set_selection!`). That recursive multi-slot write is
genuinely different from `ReplaceOperation`. Keep it as its own operation; it is
also the most-constructed operation (100 sites) and the natural second half of
every edit compound.

---

## The re-rooting rule (the key design decision)

Operations bubble up the projection pipeline via `prepend_steps_to_op` in
[`common/OperationRerooting.jl`](../../program/src/common/OperationRerooting.jl),
which today special-cases each path-bearing op type and passes identity-carrying
ops through unchanged. With one `ReplaceOperation` type, the type no longer
tells us whether to reroot. Use the `document` field as the signal:

- **`document === nothing`** ⇒ reference is rooted at `editor.document`; container
  projections **prepend their steps** to `reference` as the operation flows up.
- **`document !== nothing`** ⇒ self-contained (root is a carried object like a
  widget); the operation **passes through unchanged**, exactly as the
  identity-carrying ops do today.

This collapses the three special cases in `prepend_steps_to_op` into one:

```julia
function prepend_steps_to_op(op::ReplaceOperation, steps::Tuple)
    op.document === nothing || return op           # self-contained: pass through
    ReplaceOperation(nothing, prepend_steps_to_ref(op.reference, steps), op.replacement)
end
```

`evaluate_operation` resolves the root symmetrically:

```julia
function evaluate_operation(editor, op::ReplaceOperation)
    root = op.document === nothing ? editor.document : op.document
    # empty reference ⇒ whole-root swap (today's ReplaceDocumentOperation branch)
    # else split terminal step; dispatch FieldReference vs RangeReference
end
```

---

## Evaluation: one method, terminal-dispatched

`evaluate_operation(editor, op::ReplaceOperation)`:

1. `root = op.document === nothing ? editor.document : op.document`.
2. If `op.reference` is `EmptyReferencePath`: whole-root swap (rebind
   `editor.document`, drop cached `iomap`) — only meaningful when
   `document === nothing`. (Today's `ReplaceDocumentOperation` empty-path branch.)
3. Else split into `(parent_path, terminal)`; `parent = parent_path is empty ?
   root : evaluate_reference(root, parent_path)`.
4. Dispatch on `terminal`:
   - `FieldReference` → write `op.replacement` into the `Cell`-backed field
     (reuse `_write_value_slot!` / `_write_document_slot!`).
   - `RangeReference` → splice into the target sequence/string (reuse
     `_apply_string_replace!` / `_apply_number_replace!` for primitives;
     element overwrite for a `CellVector`, as `_write_document_slot!` does today).

Selection follow-up is **never** inside `ReplaceOperation` — it is a sibling
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

1. **Introduce primitives** in [`common/Operation.jl`](../../program/src/common/Operation.jl):
   `ReplaceOperation` and `CompoundOperation`, with the terminal-dispatched
   evaluator. Keep the existing `_split_terminal_step` / `_write_*_slot!` helpers;
   they already do the work.
2. **Re-rooting**: replace the three special cases in
   [`OperationRerooting.jl`](../../program/src/common/OperationRerooting.jl) with
   the single `document === nothing` rule above, plus a `CompoundOperation`
   map-over-children case.
3. **Fold Group 1** by making `ReplaceReferencedValue` and
   `ReplaceDocumentOperation` deprecated aliases / thin constructors that build a
   `ReplaceOperation`, then delete them once call sites are migrated.
4. **Fold Group 2** widget/focus ops: move the clamp/flip/add/derive logic into
   the producing `projection_read` methods; have them emit `ReplaceOperation`.
   Delete the structs and their `evaluate_operation` methods. Update the
   `guide/operations.md` table.
5. **Fold Group 3** range replaces: route both through `ReplaceOperation` +
   `CompoundOperation`-with-cursor. This is the largest diff (58 sites) — provide
   a transitional `StringReplaceRangeOperation(ref, repl)` constructor that
   returns the compound so tests keep passing, then sweep the explicit sites.
6. **Decide Group 4**: keep `CollectionInsert/Delete` as-is for now (move their
   `selection` follow-up into a compound), or pursue `SpliceOperation` as a
   separate plan.
7. **Leave Group 5 and `ReplaceSelectionOperation`** untouched.
8. **Docs**: rewrite the "Other domain operations" table and the worked examples
   in [`guide/operations.md`](../../guide/operations.md); cross-link the
   `evaluate_operation` signature question in
   [`../tentative/evaluate-operation-document-arg.md`](../tentative/evaluate-operation-document-arg.md)
   — consolidation makes "operations are self-contained" (its Option A) the
   natural conclusion, since `ReplaceOperation` already carries its own root.

---

## Testing

Per [CLAUDE.md](../../CLAUDE.md), run the narrowest test per stage rather than
`test_all`:

- Editor-level operation evaluation: `test_repl(<example>)` /
  `test_repls()` after the re-rooting change — the REPL tests drive
  reader → operation → evaluate end-to-end.
- String/number range folding: the primitive-to-text and selection tests
  (`test_selection(<example>)`, `PrimitiveToTextTest`) exercise the cursor
  follow-up most directly.
- Widget ops: the widget/workbench examples (`test_repl(workbench_example)`).
- Re-rooting itself is best covered by container examples (split pane, layout,
  tabbed pane) — pick one `test_repl` per container after step 2.

Do each fold as its own commit so a regression bisects to a single operation
family.

---

## Open questions

1. **`document === nothing` as the reroot signal** — clean, but it means "root is
   editor document" is encoded by a sentinel rather than a type. Acceptable, or
   prefer an explicit `rooted_at_document::Bool` / a separate
   `RootedReplaceOperation`? (Recommendation: sentinel; it mirrors the existing
   empty-path-means-root convention.)
2. **Read-modify-write moving into readers** (scroll delta, collapse flip) —
   fine for current readers (they hold the target), but if any future producer
   lacks the current value, it would need a `ToggleOperation`-style primitive.
   Flagging, not blocking.
3. **`SpliceOperation`** (Group 4 unification) — defer to a follow-up plan or do
   it here? Recommendation: defer; keep this plan to single-slot writes.
4. **Whether `ClearInput`/`ResetConversation` should become `CompoundOperation`s**
   — low value (two assistant-local resets), optional.
