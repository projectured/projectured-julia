# Operations

An **operation** is a user gesture expressed in the document's own terms,
decoupled from the raw device event that triggered it. The reader side of
the projection pipeline produces operations; the editor applies them via
`evaluate_operation`.

The abstract supertype lives in
[api/Operation.jl](../package/kernel/src/api/Operation.jl) and the built-in operations
in [common/Operation.jl](../package/kernel/src/common/Operation.jl).

```julia
abstract type Operation end
function evaluate_operation(editor, op::Operation) end   # generic function
```

## The two built-in selection operations

### `ReplaceSelectionOperation(path)`

Carries a `ReferencePath` and is produced by every reader translating a
cursor-navigation gesture. Its evaluation:

```julia
function evaluate_operation(editor, op::ReplaceSelectionOperation)
    document = editor.document
    clear_selection!(document)
    set_selection!(document, op.path)
end
```

`clear_selection!` walks the *old* selection path and writes `nothing` at
every level. `set_selection!` walks the *new* path and writes each suffix
into the matching child's `selection` cell. The two-step pattern is
important: if you only call `set_selection!`, fragments of the old
selection can remain in branches the new path doesn't visit, producing
multiple visible cursors.

The shortcut `replace_selection!(document, path)` performs both steps and
is the function to call when scripting selection from Julia code.

### `QuitEditorOperation()`

Produced when the user closes the window or presses Escape. Its evaluation
throws a `QuitEditorException`, which the `run!` loop catches and uses to
break out cleanly.

## The generic write operation: `ReplaceReferencedValue`

Most operations do one thing — **write a value into one slot of some object** — so
they are all really the *same* operation, differing only in which object, which
slot, and what value:

```julia
struct ReplaceReferencedValue
    document    # root to resolve `reference` against; `nothing` ⇒ editor.document
    reference   # ReferencePath to the slot being written
    value       # the value to write
end
```

**Rooting** is chosen by the `document` field:

- `document === nothing` — rooted at `editor.document`, so container/generic
  projections **reroot `reference`** as the operation bubbles up (it is a
  reference-carrying operation; see the invariants below).
- `document !== nothing` — **self-contained**: it carries its own root (a widget, a
  `WorkbenchPage`, or a projection's own parameter `Cell`), so it bubbles up
  **unchanged** and applying it never depends on where the document sits in the tree.

**Terminal-step dispatch** on `reference`'s last step decides what "write" means:

- `FieldReference` → set a `Cell`-backed field (`widget.visible`, `entry.value`, …).
- `RangeReference` + a single value → overwrite that one element.
- `RangeReference` + a *vector* → **splice**: replace the half-open element range
  `[start, stop)` with the items (zero-width range = insert, empty vector = delete).
- empty `reference` (only meaningful when `document === nothing`) → **whole-root
  swap**: rebind `editor.document` and drop the cached iomap.

**Builders** package the common shapes (and any cursor follow-up) so the producing
readers stay small:

| Builder | Builds |
|---|---|
| `ReplaceReferencedValue(obj, "field", v)` | a single field write on a carried root |
| `replace_document(path, doc)` | write `doc` at `path`, then move the cursor to `path ⧺ doc.selection` — a `CompoundOperation` |
| `insert_elements(path, i, items[, sel]; root=nothing)` | zero-width splice (insert); with `sel`, append a cursor move |
| `delete_elements(path, i[, n]; root=nothing)` | range-with-empty splice (delete `n` elements) |

`CompoundOperation([op₁, op₂, …])` applies several operations as one editor step;
rerooting maps over the members, so a write and its cursor move stay in sync. This
is how a document replace or a sequence insert-and-select is expressed, and what the
clipboard cut/copy/paste produce.

`ReplaceReferencedValue` and these builders **replace a whole family** of former
single-purpose operations — `ReplaceDocumentOperation`, `HideWidgetOperation`,
`ShowWidgetOperation`, `ScrollWidgetOperation`, `SetScrollBarValueOperation`,
`SetWidgetHoverOperation`, `SetWidgetPressedOperation`, `CollectionInsertOperation`,
`CollectionDeleteOperation`, and the Workbench open/close. **Reach for
`ReplaceReferencedValue` (or a builder) before writing a new operation struct.** See
[`plan/done/consolidate-operations-replace.md`](../plan/done/consolidate-operations-replace.md).

## Operations that remain distinct

These do something other than a single-slot write, so they stay their own types:

| Operation | Where it lives | Why it stays |
|---|---|---|
| `StringReplaceRangeOperation` / `NumberReplaceRangeOperation` | `document/Primitive.jl` | character-range edits on a string/number value; kept distinct because ~19 projection readers dispatch on the type to specialize char-edit handling (span↔flat mapping, control-edit parsing, …) |
| `SelectTabOperation(tabbed_pane, index)` | `document/Widget.jl` | event-like signal — the workbench overloads it into a document-selection move |
| `ReplaceFocusPartOperation(projection, part)` | `projection/generic/Focusing.jl` | retargets a `FocusingProjection` |
| `MoveRangeOperation(src, a, b, dst, i)` | `projection/higherorder/Dragging.jl` | identity-preserving relocation of `CellVector` elements (carries the `CellVector`s directly) |
| `ToggleCollapseOperation`, `ResizeWindowOperation`, `Open`/`CloseWindowOperation` | `common/Operation.jl` | view/window state |
| `Toggle{ClipboardSlice,ClipboardCollection}DisplayOperation`, `SetVersionCriterionOperation` | `projection/primitive/{ClipboardToAny,VersioningToAny}.jl` | switch *which child* a projection exposes — a structural change that drops `editor.iomap`, not an in-place cell write (the reactive engine only propagates value changes within a fixed structure) |
| `Load`/`Save`/`ExportDocumentOperation`, `Database*Operation` | `document/*.jl` | file/SQL I/O |
| assistant/composer & splitter-drag operations | `editor/*`, `document/Widget.jl` | async turns, multi-field resets, transient drag state, arbitrary `action` callables |

Operation modules are the right place to look when wiring a new gesture: the
operation declares its semantics once, the projections that emit it stay small, and
the editor's `evaluate_operation` dispatches on type.

## Driving operations programmatically (scripting the editor)

`evaluate_operation(editor, op)` is the **one way** to change the document, and
you can call it yourself — it is the same step the editor loop runs after a
gesture. So to script the editor (e.g. from `execute_julia_code`, or the REPL),
do exactly what a reader does: find the target, build the operation, evaluate it.

```julia
# Move the selection: find the node's path, then select it. (The predicate can be
# the string/regex shorthand instead: search_references(editor.document, "Alice").)
ref = first(search_references(editor.document, v -> v isa JsonString && v.value == "Alice"))
evaluate_operation(editor, ReplaceSelectionOperation(ref))   # == replace_selection!(editor.document, ref)

# A workbench action: find the page, build the op carrying it, evaluate.
page = editor.document |> d -> first(search_objects(d, x -> x isa WorkbenchPage && !isempty(x.elements)))
evaluate_operation(editor, WorkbenchCloseDocumentOperation(page, 1))
```

This pattern — **`search_objects` / `search_references` → build `Operation` →
`evaluate_operation`** — is general: it works through any wrapper
(`ScreenDocument` → `WindowDocument` → … → the document you want), and the same
three steps apply in every domain. Prefer it over bespoke imperative helpers;
the operation is the durable, composable unit. See the
[finding-and-selecting guide](editor/finding-and-selecting.md) for the search
half, and [`evaluate_operation`'s flow](#reader--operation--evaluate-flow) for
how the editor itself uses it.

This is also how a **timeline** scripts a session: `record_video` (headless) and
`play_live!` ([editor guide](editor.md#scripted-live-playback)) accept timed
entries that are *either* a device `event` (run through the reader) *or* an
`operation` (evaluated directly, exactly the pattern above). Because a
directly-injected operation skips the reader, it is **not** rerooted through
container wrappers automatically — when the document is wrapped (e.g. in a
`ScreenDocument`/`WindowDocument` for live playback), `play_live!` reroots it via
`op_prefix` using `prepend_steps_to_op` (see the
[rerooting invariant](#two-invariants-every-operation-must-respect) below). The
search-based pattern above sidesteps this by searching the *live* root, so it
needs no prefix.

## Reader → operation → evaluate flow

```
SDL_EVENT ──read_from_devices──► KeyPress/MousePress/...  ──► Change(gesture, nothing)
                                          │
                                          ▼
          projection_read(projection, recursion, change::Change, iomap)
                                          │
                                          ▼
                  Change(gesture, operation)  (operation may be nothing)
                                          │
                                          ▼
                       evaluate_operation(editor, change.operation)
                                          │
                                          ▼
                             cells written → invalidated
                                          │
                                          ▼
                       projection_print refreshes the iomap lazily
```

The reader threads a [`Change`](projection-system.md#the-change-the-reader-threads)
(the originating `gesture` plus the `operation` produced so far) and walks the
pipeline last-to-first, calling `projection_read` on each step. The `gesture`
rides along unchanged; the first step that fills in a non-nothing `operation`
short-circuits the walk, and subsequent earlier steps translate that operation
further toward the document's own domain.

## Adding a new operation

**First ask whether you need one.** If the gesture just writes a value into a slot
(a field, or an element of a sequence), emit a `ReplaceReferencedValue` — or a
`replace_document` / `insert_elements` / `delete_elements` builder, optionally inside
a `CompoundOperation` with a `ReplaceSelectionOperation` cursor move. No new type,
no new evaluator, and rerooting already works. Add a new `Operation` struct only for
genuinely different behaviour (control flow, I/O, async, multi-field/structural
changes that are not a single splice).

When you do need a new one:

1. **Declare it.** `struct MyOp <: Operation; ...; end` in the most natural
   module (the domain that owns the affected document, or `OperationModule`
   for cross-domain operations).
2. **Define `evaluate_operation(editor, ::MyOp)`** (reach for the document via
   `editor.document`). Use the existing
   primitives — `replace_selection!`, mutating reactive cells, throwing
   `QuitEditorException` — rather than reaching directly into private state.
3. **Have a projection produce it.** Add a 4-arg
   `projection_read(p, recursion, change::Change, iomap)` method on the
   projection that owns the gesture; return `Change(change.gesture, MyOp(...))`
   when the event applies (and a nothing-change otherwise). If the projection
   only needs to re-target a reference-carrying operation, you need no method at
   all — the default reader does that.
4. **(Optional) Translate it upstream.** If the operation needs to flow
   through more projections before reaching the document, give the
   upstream projections matching `projection_read` methods that consume the
   downstream operation and emit an equivalent operation in their own
   input domain.

### Two invariants every operation must respect

- **Mutate existing cells in place — or drop the iomap.** The editor builds the
  projection iomap **once** and never rebuilds it on its own; between frames,
  updates flow *only* through reactive Cell writes (`print!` reuses
  `editor.iomap` whenever it is non-`nothing`). So an `evaluate_operation` must
  change the document by writing into the Cells that are already wired into the
  projection graph. If an operation instead swaps a whole value/subtree out from
  under the projection (replacing the structure the iomap was built against), it
  must **null `editor.iomap`** to force a fresh `projection_print` — exactly what a
  `ReplaceReferencedValue` with an empty reference (the `replace_document` whole-root
  swap) does. An operation that silently rebinds structure without dropping the iomap
  renders stale.
- **A new *reference-carrying* operation must be registered in two places.** If
  your operation embeds a `ReferencePath` that has to cross projection boundaries
  — the generic `ReplaceReferencedValue` (when `document === nothing`), or the
  remaining path-bearing types `ReplaceSelectionOperation` /
  `StringReplaceRangeOperation` / `NumberReplaceRangeOperation`, or a
  `CompoundOperation` of them — it is only retargeted/rerooted automatically if it
  is handled in **both** the default `projection_read`
  ([common/Projection.jl](../package/kernel/src/common/Projection.jl)) **and**
  `prepend_steps_to_op`
  ([common/OperationRerooting.jl](../package/kernel/src/common/OperationRerooting.jl)).
  Both enumerate the path-bearing operation types explicitly; an operation missing
  from either is **silently passed through unmapped** — its reference stays in the
  wrong domain with no error. A `ReplaceReferencedValue` that carries its own root
  (`document !== nothing`) needs no rerooting — it is passed through unchanged — so
  prefer that form for an operation targeting a carried object.

## The fall-through cases

```julia
evaluate_operation(editor, ::Nothing) = nothing
evaluate_operation(editor, op)        = nothing  # any other type
```

These exist so the reader can return whatever it likes (including raw
events that nothing knows how to handle) without crashing the editor —
unknown values simply produce no effect.
