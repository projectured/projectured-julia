# Operations

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

An **operation** is a user gesture expressed in the document's own terms,
decoupled from the raw device event that triggered it. The reader side of
the projection pipeline produces operations; the editor applies them via
`evaluate_operation`.

The abstract supertype lives in
[operation/OperationInterface.jl](../../../source/kernel/operation/OperationInterface.jl) and the built-in operations
in [operation/Operations.jl](../../../source/kernel/operation/Operations.jl).

```julia
abstract type Operation end
function evaluate_operation(editor, op::Operation) end   # generic function
```

## The two built-in selection operations

### `ReplaceSelectionOperation(path)`

Carries a `Reference` and is produced by every reader translating a
cursor-navigation gesture. Its evaluation:

```julia
function evaluate_operation(editor, op::ReplaceSelectionOperation)
    replace_selection!(editor.document, op.path)
end
```

`replace_selection!` does two steps. It clears the *old* selection path, which
writes `nothing` at every level, and then walks the *new* path and writes each
suffix into the matching child's `selection` cell. The first step is
important: if you only call `set_selection!`, fragments of the old
selection can remain in branches the new path doesn't visit, producing
multiple visible cursors.

`replace_selection!(document, path)` is also the function to call when scripting
selection from Julia code.

### `QuitEditorOperation()`

Produced when the user closes the window or presses Escape. Its evaluation
throws a `QuitEditorException`, which the `run_editor!` loop catches and uses to
break out cleanly.

### `InvalidateProjectionOperation()`

Its evaluation calls `invalidate_projection!(editor)`, so the editor drops its IO
map: the frame reads no more events, and the next print builds the whole view
anew. A projection that reads a value with no dependency edge, such as a value of
a theme through an `UntrackedCell`, adds it to each answer that changes that
value, in a `CompoundOperation`. It changes no document, so its inverse is
`DoNothingOperation()`.

## The generic write operation: `ReplaceReferencedValueOperation`

Most operations do one thing: **write a value into one slot of some object**. They
are all really the *same* operation, differing only in which object, which
slot, and what value:

```julia
struct ReplaceReferencedValueOperation
    document    # root to resolve `reference` against; `nothing` ⇒ editor.document
    reference   # Reference to the slot being written
    value       # the value to write
end
```

**Rooting** is chosen by the `document` field:

- `document === nothing` — rooted at `editor.document`, so container/generic
  projections **reroot `reference`** as the operation bubbles up (it is a
  reference-carrying operation; see the invariants below).
- `document !== nothing` — **self-contained**: it carries its own root (a widget, a
  `PaneTree`'s own `drag` field, or a projection's own parameter `Cell`), so it
  bubbles up **unchanged** and applying it never depends on where the document
  sits in the tree.

**Terminal-step dispatch** on `reference`'s last step determines what "write" means:

- `FieldReferenceStep` → set a `Cell`-backed field (`widget.visible`, `entry.value`, …).
- `RangeReferenceStep` + a single value → overwrite that one element.
- `RangeReferenceStep` + a *vector* → **splice**: replace the half-open element range
  `[start, stop)` with the items (zero-width range = insert, empty vector = delete).
- empty `reference` (only meaningful when `document === nothing`) → **whole-root
  swap**: rebind `editor.document` and drop the cached iomap.

**The write keeps the mouse target right.** Each document on the path of the part
under the pointer holds its own part of that path (`replace_mouse_target!`), and a
write into a slot changes what a path through that slot names. So when the mouse
target of the document of the slot passes through the slot, the write moves it:
a path into an element after a splice moves by the change in length, a path whose
slot is gone becomes the empty path, and the documents above it on the path of the
operation get the same tail. A child that the write takes from the slot holds no
mouse target. It can be shown at another place, and the move that the backend
sends after the frame finds the part under the pointer there. So a delete, an
undo and a redo leave one part lit. An edit that is no operation, such as a write
into a cell, does none of this: an assistant or a script edits through operations,
as the interface does on behalf of the user.

**Builders** package the common shapes (and any cursor follow-up) so the producing
readers stay small:

| Builder | Builds |
|---|---|
| `ReplaceReferencedValueOperation(obj, "field", v)` | a single field write on a carried root |
| `make_replace_document_operation(path, doc)` | write `doc` at `path`, then move the cursor to `path ⧺ doc.selection` — a `CompoundOperation` |
| `make_insert_elements_operation(path, i, items; selection, root=nothing)` | zero-width splice (insert), so that the first new element is the element at the 1-based `i`; with `selection`, append a cursor move |
| `make_delete_elements_operation(path, i; count = 1, root=nothing)` | range-with-empty splice (delete `count` elements from the element at the 1-based `i`) |

`CompoundOperation([op₁, op₂, …])` applies several operations as one editor step;
rerooting maps over the members, so a write and its cursor move stay in sync. This
is how a document replace or a sequence insert-and-select is expressed, and what the
clipboard cut/copy/paste produce.

`CollectedIntentsOperation([intent₁, intent₂, …])` is the other container, and it
follows the same rule for the same reason. It is the answer to a `CollectIntents`
payload — everything available where the question was asked — and rerooting maps
over the operations the intents carry. Applying it does nothing; being an
`Operation` is what lets a listing move through the pipeline the ordinary way,
arriving already rooted where its rows can be run. **Any seam that maps a `CompoundOperation`
elementwise must map this one too**, or a listing's operations come back rooted at
the wrong depth.

`WrappingOperation` is the third container, and the only one that is open. It
holds **one** operation and does something around it — records the way back,
traces it, wraps it in a transaction. A subtype answers `get_wrapped_operation`
and `rewrap_operation`, and every seam reaches the operation it holds through
those two rather than through a branch that names the subtype. So a wrapper
needs no `reroot_operation` method of its own and no entry in the default
`read_intent`: one base method of each serves every wrapper there will ever be.
`RecordUndoOperation` of the undo slice is the first one.

`ReplaceReferencedValueOperation` and these builders **cover what would otherwise be a
whole family** of single-purpose operations: a `ReplaceDocumentOperation`,
`HideWidgetOperation`, `ShowWidgetOperation`, `ScrollWidgetOperation`,
`SetScrollBarValueOperation`, `SetWidgetHoverOperation`, `SetWidgetPressedOperation`,
`CollectionInsertOperation`, `CollectionDeleteOperation`, and a pane's own tab open
and close all reduce to a single-slot write. A click on a tab of a
`WidgetTabbedPane` is a `ReplaceSelectionOperation` of `selector_element_pairs[i]`,
so no operation of its own selects a tab. **Reach for
`ReplaceReferencedValueOperation` (or a builder) before writing a new operation struct.** See
[`plan/done/consolidate-operations-replace.md`](../../../plan/done/consolidate-operations-replace.md).

## Operations that remain distinct

These do something other than a single-slot write, so they stay their own types:

| Operation | Where it lives | Why it stays |
|---|---|---|
| `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation` | `primitive/PrimitiveDocument.jl` | character-range edits on a string/number value; kept distinct because ~19 projection readers dispatch on the type to specialize char-edit handling (span↔flat mapping, control-edit parsing, …) |
| `ReplaceFocusPartOperation(projection, part)` | `projection/generic/Focusing.jl` | retargets a `FocusingProjection` |
| `MoveRangeOperation(src, a, b, dst, i)` | `dragging/Dragging.jl` | identity-preserving relocation of `CellVector` elements (carries the `CellVector`s directly) |
| `ToggleCollapseOperation` | `operation/Operations.jl` | view state |
| `ResizeWindowOperation`, `Open`/`CloseWindowOperation` | `screen/ScreenDocument.jl` | window state; an operation whose vocabulary belongs to one domain is declared with that domain's document |
| `ToggleClipboardSliceOperation`, `ToggleClipboardCollectionOperation`, `SetVersionCriterionOperation` | `clipboard/ClipboardSliceToAny.jl`, `clipboard/ClipboardCollectionToAny.jl`, `versioning/VersioningToAny.jl` | switch *which child* a projection exposes. Each one writes a cell, and the output of the projection is a computed cell over it, so the stages after it print again with no `editor.iomap` drop |
| `LoadDocumentOperation`, `SaveDocumentOperation` | `serialization/BinarySerialization.jl` | file I/O |
| `SaveFileOperation`, `ExportDocumentOperation` | `fileformat/DocumentFile.jl`, `fileformat/NaturalFormat.jl` | file I/O |
| `UpdateDatabaseCellOperation`, `InsertDatabaseRowOperation` | `database/DatabaseDocument.jl` | SQL I/O |
| `WriteOsClipboardOperation` | `clipboard/Clipboard.jl` | side-effecting OS-clipboard write — mirrors a copy/cut/note out to the system clipboard at evaluate time (best-effort; degrades to a no-op when no clipboard tool exists) |
| `InvokeActionOperation(action)` | `widget/WidgetDocument.jl` | runs an `Action`'s callback — an effect, not a field write. The one activation operation: every control (button, menu item, toolbar entry, keyboard shortcut) is a view of an `Action` and answers a press with this. It names its own target, so a projection that hosts controls forwards it unchanged rather than re-rooting it |
| assistant/composer & splitter-drag operations | `assistant/AssistantTurn.jl`, `conversation/ConversationEditor.jl`, `widget/WidgetDocument.jl` | async turns, multi-field resets, transient drag state |

### A text paste is a range edit

The clipboard makes the same two range operations when it pastes text. A
selection that ends in a field and a range of that field's text (a caret, or a
range of characters) is a *text target*: `Ctrl+V` answers
`ReplaceStringRangeOperation(path, text)`, or `ReplaceNumberRangeOperation` for a
number field, with the text of the system clipboard, and the kernel applies it as
it applies a typed character. `Ctrl+C`, `Ctrl+N` and `Ctrl+X` of a range store
its characters in the slice and on the system clipboard. The branch runs before
the rules for a whole document; `accepts_pasted_text` returns whether a document
accepts the paste and the cut. It is in [clipboard/Clipboard.jl](../../../source/platform/clipboard/Clipboard.jl)
and [clipboard/ClipboardSliceToAny.jl](../../../source/platform/clipboard/ClipboardSliceToAny.jl).
A field that holds a span of the text domain is not a text target yet.

Operation modules are the right place to look when wiring a new gesture: the
operation declares its semantics once, the projections that emit it stay small, and
the editor's `evaluate_operation` dispatches on type.

## Driving operations programmatically (scripting the editor)

`evaluate_operation(editor, op)` is the **one way** to change the document, and
you can call it yourself. It is the same step the editor loop runs after a
gesture. So to script the editor (e.g. from `execute_julia_code`, or the REPL),
do exactly what a reader does: find the target, build the operation, evaluate it.

```julia
# Move the selection: find the node's path, then select it. (The predicate can be
# the string/regex shorthand instead: search_references(editor.document, "Alice").)
ref = first(search_references(editor.document, v -> v isa JsonString && v.value == "Alice"))
evaluate_operation(editor, ReplaceSelectionOperation(ref))   # == replace_selection!(editor.document, ref)

# A pane action: find the group, build the op carrying it, evaluate.
tree = get_window_tree(; editor)
group = editor.document |> d -> first(search_documents(d, x -> x isa PaneGroup && !isempty(x.tabs)))
evaluate_operation(editor, make_pane_close_tab_operation(tree, group, 1))
```

This pattern — **`search_documents` / `search_references` → build `Operation` →
`evaluate_operation`** — is general: it works through any wrapper
(`ScreenDocument` → `WindowDocument` → … → the document you want), and the same
three steps apply in every domain. Prefer it over bespoke imperative helpers;
the operation is the durable, composable unit. See the
[finding-and-selecting guide](finding-and-selecting.md) for the search
half, and [`evaluate_operation`'s flow](#reader-operation-evaluate-flow) for
how the editor itself uses it.

This is also how a **timeline** scripts a session: `record_video` (headless) and
`play_live!` ([editor guide](editor.md#scripted-live-playback)) accept timed
entries that are *either* a device `event` (run through the reader) *or* an
`operation` (evaluated directly, exactly the pattern above). Because a
directly-injected operation skips the reader, it is **not** rerooted through
container wrappers automatically. When the document is wrapped (e.g. in a
`ScreenDocument`/`WindowDocument` for live playback), `play_live!` reroots it via
`op_prefix` using `reroot_operation` (see the
[rerooting invariant](#two-invariants-every-operation-must-respect) below). The
search-based pattern above sidesteps this by searching the *live* root, so it
needs no prefix.

## Reader → operation → evaluate flow

```
SDL_EVENT ──take_from_devices!──► KeyPress/MouseClick/...  ──► Intent(gesture, nothing)
                                          │
                                          ▼
          read_intent(projection, recursion, change::Intent, iomap)
                                          │
                                          ▼
                  Intent(gesture, operation)  (operation may be nothing)
                                          │
                                          ▼
                       evaluate_operation(editor, change.operation)
                                          │
                                          ▼
                             cells written → invalidated
                                          │
                                          ▼
                       print_document refreshes the iomap lazily
```

The reader threads a [`Intent`](projection-system.md#the-intent-the-reader-threads)
(the originating `gesture` plus the `operation` produced so far) and walks the
pipeline last-to-first, calling `read_intent` on each step. The `gesture`
passes through unchanged; the first step that fills in a non-nothing `operation`
short-circuits the walk, and subsequent earlier steps translate that operation
further toward the document's own domain.

Within a single structural projection, the reader recurses the same way the
printer does: it **delegates a raw authoring gesture to the projection of the
selected child** and **lifts** the child's operation back into its own domain by
prepending the step that reaches the child (`reroot_operation`). It handles the
gesture itself (via [`read_gesture`](projection-system.md#domain-owned-geometry-free-gesture-mapping-read_gesture))
only when the child returns nothing for it. This is what makes `,`/`Tab` reach the *nearest
enclosing* object/array rather than only the root. See
[Recursive gesture reading](projection-system.md#recursive-gesture-reading-delegate-to-the-selected-child-lift-the-operation).

## Adding a new operation

**First ask whether you need one.** If the gesture just writes a value into a slot
(a field, or an element of a sequence), emit a `ReplaceReferencedValueOperation`, or a
`make_replace_document_operation` / `make_insert_elements_operation` / `make_delete_elements_operation` builder, optionally inside
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
   `read_intent(p, recursion, change::Intent, iomap)` method on the
   projection that owns the gesture; return `Intent(change.gesture, MyOp(...))`
   when the event applies (and a nothing-change otherwise). If the projection
   only needs to re-target a reference-carrying operation, you need no method at
   all — the default reader does that.
4. **(Optional) Translate it upstream.** If the operation needs to flow
   through more projections before reaching the document, give the
   upstream projections matching `read_intent` methods that consume the
   downstream operation and emit an equivalent operation in their own
   input domain.

### Two invariants every operation must respect

- **Mutate existing cells in place — or drop the iomap.** The editor builds the
  projection iomap **once** and never rebuilds it on its own; between frames,
  updates flow *only* through reactive Cell writes (`run_print_stage!` reuses
  `editor.iomap` whenever it is non-`nothing`). So an `evaluate_operation` must
  change the document by writing into the Cells that are already wired into the
  projection graph. If an operation instead swaps a whole value/subtree out from
  under the projection (replacing the structure the iomap was built against), it
  must **null `editor.iomap`** to force a fresh `print_document` — exactly what a
  `ReplaceReferencedValueOperation` with an empty reference (the `make_replace_document_operation` whole-root
  swap) does. An operation that silently rebinds structure without dropping the iomap
  renders stale.
- **A new *reference-carrying* operation must be registered in two places.** If
  your operation embeds a `Reference` that has to cross projection boundaries,
  such as the generic `ReplaceReferencedValueOperation` (when `document === nothing`), the
  remaining path-bearing types `ReplaceSelectionOperation` /
  `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`, or a
  `CompoundOperation` of them, it is only retargeted/rerooted automatically if it
  is handled in **both** the default `read_intent`
  ([projection/ProjectionDefaults.jl](../../../source/kernel/projection/ProjectionDefaults.jl)) **and**
  `reroot_operation`
  ([operation/Rerooting.jl](../../../source/kernel/operation/Rerooting.jl)).
  Both enumerate the path-bearing operation types explicitly; an operation missing
  from either is **silently passed through unmapped**. Its reference stays in the
  wrong domain with no error. A `ReplaceReferencedValueOperation` that carries its own root
  (`document !== nothing`) needs no rerooting: it is passed through unchanged.
  Prefer that form for an operation targeting a carried object.

## The fall-through cases

```julia
evaluate_operation(editor, ::Nothing) = nothing
evaluate_operation(editor, op)        = nothing  # any other value
```

A reader that declines returns `nothing`, and the first method takes it. The
second method takes any other value that is not an `Operation`, so a stray value
does no harm: it produces no effect. Both methods are in
[operation/OperationDefaults.jl](../../../source/kernel/operation/OperationDefaults.jl).

## The operation layer

The material above is *how* to reach for and add operations. The rest of this
guide is the layer's **structure**: where the code lives, and the open seams that
a path-bearing operation, a container document or a new operation type extends.

Layer 13 of the kernel is **changing documents**. An operation is the reified
edit the reader side of the projection pipeline produces and
`evaluate_operation` applies. The layer holds the abstract `Operation` and
`WrappingOperation` supertypes, the built-in concrete operations, the builders
and the splice helpers, the seams that reroot an operation, the way back of an
operation, and the description of an operation for a person.

The layer lives in [source/kernel/operation/](../../../source/kernel/operation/), inside one aggregator
module (`OperationModule`) split across six fragments:

```
OperationModule.jl        (OperationModule)             — the aggregator
        │ uses Cell, Document, Fault, Reference and Selection; exports every public name
        ├─ OperationInterface.jl — the contract: Operation, WrappingOperation with
        │                          get_wrapped_operation / rewrap_operation,
        │                          evaluate_operation, invalidate_projection!, and
        │                          the declaration of each seam below
        ├─ OperationDefaults.jl  — the fallbacks: evaluate_operation for nothing and
        │                          for any other value, and invalidate_projection!
        ├─ Operations.jl         — the built-in ops (DoNothing, CompoundOperation,
        │                          Quit with QuitEditorException, ReplaceSelection,
        │                          ReplaceViewState, ReplaceReferencedValue,
        │                          SelectNextInsertion, Adjust*, ToggleCollapse),
        │                          the builders, the splice helpers, and the open
        │                          child_reference_steps seam
        ├─ Rerooting.jl          — reroot_reference, and the reroot_operation /
        │                          operation_reference / retarget_operation /
        │                          is_self_contained_operation seams with their
        │                          base methods
        ├─ Inversion.jl          — the way back: make_inverse_operation,
        │                          evaluate_invertible_operation! and the
        │                          get_slot_at seam
        └─ Description.jl        — describe_operation and describe_reference
```

The six files share one namespace because they are only ever imported
together.

### The open `child_reference_steps(node)` traversal seam

Without this seam, `SelectNextInsertionOperation`'s pre-order document walk would have to hard-code each container type:

```julia
function _preorder_documents!(node, ...)
    ...
    if node isa CellVector
        for i in 1:length(node)
            _preorder_documents!(node[i], extend_reference(path, RangeReferenceStep(i-1, i)), ...)
        end
        return
    end
    for nm in fieldnames(typeof(node))
        ...
```

The `isa CellVector` branch is the smell: an operation-layer file
hard-referencing a concrete document type. The open generic form dissolves it:

```julia
function child_reference_steps end         # declaration in OperationInterface.jl

child_reference_steps(node) = [(FieldReferenceStep(...), val), ...]   # default (fieldnames)

# in collection/CellVector.jl:
child_reference_steps(node::CellVector) = [(RangeReferenceStep(i-1, i), node[i]), ...]
```

A new container document type adds a `child_reference_steps` method beside its
type definition. The default handles ordinary structs.

**Testing pressure.** `test/kernel/operation/TraversalTest.jl` defines a test-local
`@document struct ToyList` and registers its own `child_reference_steps`
method: the exact pressure that keeps the seam honest. If a fresh test-local
type could not drive the walk, the seam would not be open.

### The open `reroot_operation(op, steps)` generic

Without this seam, `reroot_operation` would be a closed if-chain:

```julia
function reroot_operation(op, steps)
    op === nothing && return nothing
    if op isa ReplaceReferencedValueOperation ...
    elseif op isa ReplaceSelectionOperation ...
    elseif op isa ReplaceStringRangeOperation ...      # ← Primitive!
    elseif op isa ReplaceNumberRangeOperation ...      # ← Primitive!
    elseif op isa CompoundOperation ...
    else op
    end
end
```

The `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation` branches
would import `PrimitiveModule` from a lower kernel layer: a wrong-direction
edge. The open generic form avoids it, with the base methods in
`Rerooting.jl`:

```julia
function reroot_operation end
reroot_operation(::Nothing, steps) = nothing
reroot_operation(op, steps) = ...   # through operation_reference / retarget_operation
reroot_operation(op::ReplacePathOperation, steps) = ...   # every kind of path, once
reroot_operation(op::CompoundOperation, steps) = ...
reroot_operation(op::WrappingOperation, steps) = ...   # every wrapper, once
```

The catch-all asks `operation_reference` for the reference of the operation,
prepends the steps, and rebuilds the operation with `retarget_operation`. An
operation that reports no reference comes back unchanged. So a path-bearing
operation type registers **once, with the pair**: the catch-all reroots it, and
the default `read_intent` maps it back through a projection. The `Primitive`
operations do this in `primitive/PrimitiveDocument.jl`, beside their type
declarations:

```julia
# primitive/PrimitiveDocument.jl:
operation_reference(op::ReplaceStringRangeOperation) = op.reference
retarget_operation(op::ReplaceStringRangeOperation, reference::Reference) =
    ReplaceStringRangeOperation(reference, op.replacement)
```

A type with no pair reports no reference, so its reference is never rerooted and
the default reader drops it. A family with a contract of its own registers through
that contract: a `ReplacePathOperation` answers `get_operation_path` and
`make_path_operation`, and a wrapper answers `get_wrapped_operation` and
`rewrap_operation`.

**Testing pressure.** `test/kernel/operation/RerootingTest.jl` declares a test-local
`ToyPathOperation <: Operation` that answers only the pair, and the catch-all
reroots it, proving the seam is genuinely open: you cannot depend on a concrete
higher-layer type at layer 13.

### An operation that names no place: `is_self_contained_operation`

An operation either says *where* it acts, with a reference, or says *what* it acts
on, with the object in a field. A chain re-targets the first kind at each stage
through `operation_reference` and `retarget_operation`. The second kind has
nothing to re-target, so a stage either passes it up as it is or drops it.
`is_self_contained_operation(op)` answers which. The default is `false`, so a
stage drops what it can not place. `Rerooting.jl` answers `true` for the
operations of this layer that name no place: `DoNothingOperation`,
`QuitEditorOperation`, `InvalidateProjectionOperation`, `ToggleCollapseOperation`
and `SelectNextInsertionOperation`. A package whose operations carry their
subject adds one method for them.

### The way back: `make_inverse_operation`

`make_inverse_operation(document, op)` answers the operation that takes
`document` back to the state it is in now, once `op` is applied, or `nothing`
when `op` has no way back. It reads the document, so a caller takes it before it
applies `op`. `evaluate_invertible_operation!(editor, op)` does the two in that
order. For a `CompoundOperation` it inverts each member against the state that
member sees, and runs the inverses in the opposite order. An operation that
changes no document, such as a zoom, answers `DoNothingOperation()`. The inverse
of a `ReplaceReferencedValueOperation` carries the object that it writes into, not
a path, so it stays right when the document moves in the tree. `get_slot_at` is
the seam through which a collection of cells gives back the cell of an element
for a splice, so the element that comes back is the same object. The operations
of a higher package declare their inverses beside their own declarations.

### The description: `describe_operation`

`describe_operation(op)` writes an operation in one line for a person:
`select entries[1].value`, `set entries[2].key = "b"`. An operation type
that this layer does not name reads as its type name without the `Operation`
suffix, followed by the reference that `operation_reference` reports, so a domain
that adds an operation needs no method here. `describe_operation(op, root)` and
`describe_reference(reference, root)` write a reference from the deepest document
on it that has a title (`get_document_title`), past the fields that
`get_edited_field` names: `items.json › [2].price`.

### A write of view state: `ReplaceViewStateOperation`

`ReplaceViewStateOperation(operation)` is a `WrappingOperation` that marks
`operation` as a write of view state: what the pointer is over, what it holds
down, what a drag carries. Applying it applies `operation`. A history does not
record it, because a hover is not an edit. The reader that writes the state marks
it, because only that reader knows that the field belongs to the pointer and not
to the document.

### Downward edges

- `..FaultModule` — `is_passthrough_exception`, which `QuitEditorException`
  extends so that no fault barrier catches a request to quit
- `..CellModule: Cell, AbstractCell`
- `..DocumentModule: Document, get_edited_field, get_document_title`
- `..ReferenceModule: Reference, …, extend_reference, evaluate_reference, …`
- `..SelectionModule: replace_selection!, set_selection!, get_selection`

That is the whole import surface. No projection, no device, no editor. This
is what keeps the operation layer below the binding, iomap and projection layers.
