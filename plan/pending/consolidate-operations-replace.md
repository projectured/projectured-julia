# Consolidating operations into `ReplaceReferencedValue`

> **Status (audit 2026-06-23): mostly OPEN.** Only the `CompoundOperation`
> scaffold (migration step 1) is implemented. The actual consolidation — folding
> the Group 1–4 operation families into `ReplaceReferencedValue`, the
> `document === nothing` re-rooting rule, terminal-kind dispatch / `RangeReference`
> splice, and the docs rewrite — is **not done**. See per-step annotations under
> [Migration steps](#migration-steps). Paths below referencing `program/src/...`
> and `guide/...` are stale post-restructure; current locations are noted inline.

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

Source of truth: [`api/Operation.jl`](../../program/src/api/Operation.jl),
[`common/Operation.jl`](../../program/src/common/Operation.jl), and the
per-domain operation blocks. Construction counts are from a repo-wide grep, to
gauge migration blast radius.

### Group 1 — already a replace; fold in directly

| Operation | Root | Slot / value | ctor sites |
|---|---|---|---|
| `ReplaceDocumentOperation(path, document)` | `editor.document` | field cell **or** seq element ← `Document` | 3 |

`ReplaceReferencedValue` is the target — it already has the right three fields
(`document`, `reference`, `value`). `ReplaceDocumentOperation` is the special
case where `document === nothing` (root is the editor document) and the
reference may be empty (whole-root swap). Both share the `_split_terminal_step`
/ `_write_document_slot!` / `_write_value_slot!` machinery in
[`common/Operation.jl`](../../program/src/common/Operation.jl).

### Group 2 — single-slot writes carrying their target by identity

These already carry the object they mutate (not a path from `editor.document`),
so they map to `ReplaceReferencedValue(target, <relative-ref>, value)`:

| Operation | Becomes |
|---|---|
| `HideWidgetOperation(w)` | `ReplaceReferencedValue(w, @reference visible, false)` |
| `ShowWidgetOperation(w)` | `ReplaceReferencedValue(w, @reference visible, true)` |
| `SetScrollBarValueOperation(bar, v)` | `ReplaceReferencedValue(bar, @reference value, clamp(v,0,1))` |
| `SelectTabOperation(pane, i)` | `ReplaceReferencedValue(pane, @reference selection, ElementReference(i)-path)` |
| `ScrollWidgetOperation(sp, Δ)` | `ReplaceReferencedValue(sp, @reference scroll_position, old+Δ)` — reader computes `old+Δ` |
| `ToggleCollapseOperation(node)` | `ReplaceReferencedValue(node, @reference collapsed, !node.collapsed)` — reader computes the flip |
| `ResizeWindowOperation(w, ow, oh)` | two writes → a `CompoundOperation` (see below) |

Notes:
- **Clamp/flip/add happen in the reader**, where the current value is readable,
  so the operation stays a pure "write this value here." This is a deliberate
  shift: read-modify-write logic moves from `evaluate_operation` into
  `projection_read`. For `ScrollWidget` and `ToggleCollapse` the reader already
  has the target object in hand, so it can read the current value.
- `ResizeWindowOperation` writes two fields (`width`, `height`); express it as
  `CompoundOperation([ReplaceReferencedValue(w, width, …), ReplaceReferencedValue(w, height, …)])`.
- `ReplaceFocusPartOperation(proj, part)` writes `proj.part` **and** the derived
  `proj.part_evaluator`. Either keep a tiny bespoke setter, or make the
  `part_evaluator` a lazily-derived accessor so only `part` needs writing — then
  it folds into `ReplaceReferencedValue(proj, @reference part, part)`. Prefer the
  latter; the evaluator is a pure function of `part`.

### Group 3 — sub-value *range* writes (string/number)

| Operation | ctor sites |
|---|---|
| `StringReplaceRangeOperation(reference, replacement)` | 47 |
| `NumberReplaceRangeOperation(reference, replacement)` | 11 |

These splice a string into a character range whose terminal step is a
`RangeReference`, then move the cursor. They fold into `ReplaceReferencedValue`
if **evaluation dispatches on the terminal step kind**:

- terminal `FieldReference` → overwrite the whole cell value (Group 1/2 path);
- terminal `RangeReference` → splice `value` into the target's
  string/sequence at `[start, stop]` (today's `_apply_string_replace!` /
  `_apply_number_replace!`, which already dispatch on target type).

The cursor-move-after-edit is **not** part of the write — model it as a
`CompoundOperation([replace, ReplaceSelectionOperation(cursor_path)])`, matching
how `_replace_selection_with_cursor!` currently runs as a second step. String vs
number is a property of the *target type*, not the operation, so the two ops
merge into one path. (47+11 = 58 construction sites — the bulk of the migration;
most are in tests and can be updated mechanically, or kept working via a
deprecated constructor shim during transition.)

### Group 4 — structural sequence edits (splice via `RangeReference`)

| Operation | ctor sites |
|---|---|
| `CollectionInsertOperation(path, index, items, selection)` | ~8 |
| `CollectionDeleteOperation(path, index, count)` | ~6 |

These grow/shrink a sequence, but `RangeReference` terminal dispatch already
handles splice semantics for strings. The same logic extends to `CellVector`:

| Operation | Becomes |
|---|---|
| `CollectionInsertOperation(path, i, items)` | `ReplaceReferencedValue(nothing, path / RangeReference(i, i), items)` — zero-width range = pure insert |
| `CollectionDeleteOperation(path, i, count)` | `ReplaceReferencedValue(nothing, path / RangeReference(i, i+count), [])` — replace range with empty = delete |

Element *replacement* (delete-then-insert at same position) falls out for free
as `ReplaceReferencedValue(nothing, path / RangeReference(i, i+1), [new_item])`.

The `selection` field on `CollectionInsertOperation` becomes the second half of a
`CompoundOperation([splice, ReplaceSelectionOperation(cursor_path)])`, matching
the pattern used for Group 3.

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
ops through unchanged. Once all single-slot writes are `ReplaceReferencedValue`,
use the `document` field as the signal:

- **`document === nothing`** ⇒ reference is rooted at `editor.document`; container
  projections **prepend their steps** to `reference` as the operation flows up.
- **`document !== nothing`** ⇒ self-contained (root is a carried object like a
  widget); the operation **passes through unchanged**, exactly as the
  identity-carrying ops do today.

This collapses the three special cases in `prepend_steps_to_op` into one:

```julia
function prepend_steps_to_op(op::ReplaceReferencedValue, steps::Tuple)
    op.document === nothing || return op           # self-contained: pass through
    ReplaceReferencedValue(nothing, prepend_steps_to_ref(op.reference, steps), op.value)
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
   - `RangeReference` → splice into the target sequence/string (reuse
     `_apply_string_replace!` / `_apply_number_replace!` for primitives;
     element overwrite for a `CellVector`, as `_write_document_slot!` does today).

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

> **Audit (2026-06-23):** verified against the restructured tree under
> `package/*/src/`. The partial-credit summary: only the `CompoundOperation`
> scaffold (step 1) landed; the actual consolidation (steps 2–6) has not been
> done — every targeted operation still exists as its own standalone `struct`,
> `ReplaceReferencedValue` still only handles a `FieldReference` terminal and
> still errors on an empty reference, and `OperationRerooting.jl` still keeps a
> special case per op type. Steps 7–8 remain open. Plan stays in **pending**.

1. **✅ DONE (verified):** **Introduce `CompoundOperation`** — exists at
   `package/kernel/src/common/Operation.jl:36` (`struct CompoundOperation`) with a
   varargs ctor (`:40`) and a map-over-children evaluator (`:42`). The
   `_split_terminal_step` / `_write_*_slot!` helpers are still present
   (`Operation.jl:134`, `:152`, `:193`). (Note: its docstring frames it as the
   clipboard-cut helper, not yet the range/cursor compound this plan envisions.)
2. **⏳ OPEN:** **Re-rooting single rule** — not done. `prepend_steps_to_op` in
   `package/kernel/src/common/OperationRerooting.jl:49` still special-cases
   `ReplaceSelectionOperation`, `StringReplaceRangeOperation`,
   `NumberReplaceRangeOperation`, `ReplaceDocumentOperation`,
   `CollectionInsertOperation`, `CollectionDeleteOperation`, `CompoundOperation`.
   There is no `document === nothing` rule for `ReplaceReferencedValue`; it falls
   through to the `else` (pass-through), which is only correct for the
   self-contained case.
3. **⏳ OPEN:** **Fold Group 1 (`ReplaceDocumentOperation`)** — not done. Still a
   full standalone struct with its own evaluator at
   `package/kernel/src/common/Operation.jl:100`–`124`; not an alias for
   `ReplaceReferencedValue`.
4. **⏳ OPEN:** **Fold Group 2 widget/focus ops** — not done. All structs still
   present and standalone: `HideWidgetOperation`/`ShowWidgetOperation`/
   `ScrollWidgetOperation`/`SelectTabOperation`/`SetScrollBarValueOperation` at
   `package/domain/src/document/Widget.jl:1082,1092,1102,1114,1124`;
   `ReplaceFocusPartOperation` at
   `package/kernel/src/projection/generic/Focusing.jl:74`.
5. **⏳ OPEN:** **Fold Group 3 range replaces** — not done.
   `StringReplaceRangeOperation`/`NumberReplaceRangeOperation` still standalone at
   `package/kernel/src/document/Primitive.jl:117,99`. `ReplaceReferencedValue`'s
   evaluator (`Operation.jl:180`) only dispatches the `FieldReference` terminal
   (`_write_value_slot!`, `:193`) and explicitly `error`s on an empty reference —
   no `RangeReference` splice path exists.
6. **⏳ OPEN:** **Fold Group 4 sequence ops** — not done.
   `CollectionInsertOperation`/`CollectionDeleteOperation` still standalone with
   their own evaluators at `package/kernel/src/common/Operation.jl:209,235`; not
   re-expressed as `ReplaceReferencedValue` + `RangeReference`.
7. **⏳ OPEN (correctly untouched, but plan not complete):** **Leave Group 5 and
   `ReplaceSelectionOperation`** — these are intentionally still present
   (`ReplaceSelectionOperation` at `Operation.jl:74`; Group 5 ops in
   `package/domain/src/document/Document.jl:98,109,120`,
   `package/domain/src/document/Database.jl:69,84`,
   `package/domain/src/editor/WorkbenchAssistant.jl:101,112,121,130`). This step
   is satisfied in isolation, but it only describes the *absence* of work, so it
   does not move the plan toward completion on its own.
8. **⏳ OPEN:** **Docs** — not done. The operations guide now lives at
   `documentation/operations.md` (old `guide/operations.md` path is gone); it has
   not been rewritten around `ReplaceReferencedValue`/`CompoundOperation`, since
   the underlying consolidation has not happened.

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
