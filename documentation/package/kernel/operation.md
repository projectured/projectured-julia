# Operations

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

An **operation** is a user gesture expressed in the document's own terms,
decoupled from the raw device event that triggered it. The reader side of
the projection pipeline produces operations; the editor applies them via
`evaluate_operation`.

The abstract supertype lives in
[operation/Interface.jl](../../../source/kernel/operation/Interface.jl) and the built-in operations
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
throws a `QuitEditorException`, which the `run_editor!` loop catches and uses to
break out cleanly.

## The generic write operation: `ReplaceReferencedValueOperation`

Most operations do one thing — **write a value into one slot of some object** — so
they are all really the *same* operation, differing only in which object, which
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
  `WorkbenchPage`, or a projection's own parameter `Cell`), so it bubbles up
  **unchanged** and applying it never depends on where the document sits in the tree.

**Terminal-step dispatch** on `reference`'s last step decides what "write" means:

- `FieldReferenceStep` → set a `Cell`-backed field (`widget.visible`, `entry.value`, …).
- `RangeReferenceStep` + a single value → overwrite that one element.
- `RangeReferenceStep` + a *vector* → **splice**: replace the half-open element range
  `[start, stop)` with the items (zero-width range = insert, empty vector = delete).
- empty `reference` (only meaningful when `document === nothing`) → **whole-root
  swap**: rebind `editor.document` and drop the cached iomap.

**Builders** package the common shapes (and any cursor follow-up) so the producing
readers stay small:

| Builder | Builds |
|---|---|
| `ReplaceReferencedValueOperation(obj, "field", v)` | a single field write on a carried root |
| `replace_document(path, doc)` | write `doc` at `path`, then move the cursor to `path ⧺ doc.selection` — a `CompoundOperation` |
| `insert_elements(path, i, items[, sel]; root=nothing)` | zero-width splice (insert); with `sel`, append a cursor move |
| `delete_elements(path, i[, n]; root=nothing)` | range-with-empty splice (delete `n` elements) |

`CompoundOperation([op₁, op₂, …])` applies several operations as one editor step;
rerooting maps over the members, so a write and its cursor move stay in sync. This
is how a document replace or a sequence insert-and-select is expressed, and what the
clipboard cut/copy/paste produce.

`CollectedIntentsOperation([intent₁, intent₂, …])` is the other container, and it
follows the same rule for the same reason. It is the answer to a `CollectIntents`
payload — everything available where the question was asked — and rerooting maps
over the operations the intents carry. Applying it does nothing; being an
`Operation` is what lets a listing travel home the ordinary way, arriving already
rooted where its rows can be run. **Any seam that maps a `CompoundOperation`
elementwise must map this one too**, or a listing's operations come back rooted at
the wrong depth.

`ReplaceReferencedValueOperation` and these builders **replace a whole family** of former
single-purpose operations — `ReplaceDocumentOperation`, `HideWidgetOperation`,
`ShowWidgetOperation`, `ScrollWidgetOperation`, `SetScrollBarValueOperation`,
`SetWidgetHoverOperation`, `SetWidgetPressedOperation`, `CollectionInsertOperation`,
`CollectionDeleteOperation`, and the Workbench open/close. **Reach for
`ReplaceReferencedValueOperation` (or a builder) before writing a new operation struct.** See
[`plan/done/consolidate-operations-replace.md`](../../../plan/done/consolidate-operations-replace.md).

## Operations that remain distinct

These do something other than a single-slot write, so they stay their own types:

| Operation | Where it lives | Why it stays |
|---|---|---|
| `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation` | `document/Primitive.jl` | character-range edits on a string/number value; kept distinct because ~19 projection readers dispatch on the type to specialize char-edit handling (span↔flat mapping, control-edit parsing, …) |
| `SelectTabOperation(tabbed_pane, index)` | `visual/widget/Widget.jl` | event-like signal — the workbench overloads it into a document-selection move |
| `ReplaceFocusPartOperation(projection, part)` | `projection/generic/Focusing.jl` | retargets a `FocusingProjection` |
| `MoveRangeOperation(src, a, b, dst, i)` | `projection/higherorder/Dragging.jl` | identity-preserving relocation of `CellVector` elements (carries the `CellVector`s directly) |
| `ToggleCollapseOperation`, `ResizeWindowOperation`, `Open`/`CloseWindowOperation` | `operation/Operations.jl` | view/window state |
| `Toggle{ClipboardSlice,ClipboardCollection}DisplayOperation`, `SetVersionCriterionOperation` | `projection/primitive/{ClipboardToAny,VersioningToAny}.jl` | switch *which child* a projection exposes — a structural change that drops `editor.iomap`, not an in-place cell write (the reactive engine only propagates value changes within a fixed structure) |
| `Load`/`Save`/`ExportDocumentOperation`, `Database*Operation` | `document/*.jl` | file/SQL I/O |
| `WriteOsClipboardOperation` | `clipboard/Clipboard.jl` | side-effecting OS-clipboard write — mirrors a copy/cut/note out to the system clipboard at evaluate time (best-effort; degrades to a no-op when no clipboard tool exists) |
| `InvokeActionOperation(action)` | `visual/widget/Widget.jl` | runs an `Action`'s callback — an effect, not a field write. The one activation operation: every control (button, menu item, toolbar entry, keyboard shortcut) is a view of an `Action` and answers a press with this. It names its own target, so a projection that hosts controls forwards it unchanged rather than re-rooting it |
| assistant/composer & splitter-drag operations | `editor/*`, `visual/widget/Widget.jl` | async turns, multi-field resets, transient drag state |

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
page = editor.document |> d -> first(search_documents(d, x -> x isa WorkbenchPage && !isempty(x.elements)))
evaluate_operation(editor, WorkbenchCloseDocumentOperation(page, 1))
```

This pattern — **`search_documents` / `search_references` → build `Operation` →
`evaluate_operation`** — is general: it works through any wrapper
(`ScreenDocument` → `WindowDocument` → … → the document you want), and the same
three steps apply in every domain. Prefer it over bespoke imperative helpers;
the operation is the durable, composable unit. See the
[finding-and-selecting guide](finding-and-selecting.md) for the search
half, and [`evaluate_operation`'s flow](#reader--operation--evaluate-flow) for
how the editor itself uses it.

This is also how a **timeline** scripts a session: `record_video` (headless) and
`play_live!` ([editor guide](editor.md#scripted-live-playback)) accept timed
entries that are *either* a device `event` (run through the reader) *or* an
`operation` (evaluated directly, exactly the pattern above). Because a
directly-injected operation skips the reader, it is **not** rerooted through
container wrappers automatically — when the document is wrapped (e.g. in a
`ScreenDocument`/`WindowDocument` for live playback), `play_live!` reroots it via
`op_prefix` using `reroot_operation` (see the
[rerooting invariant](#two-invariants-every-operation-must-respect) below). The
search-based pattern above sidesteps this by searching the *live* root, so it
needs no prefix.

## Reader → operation → evaluate flow

```
SDL_EVENT ──read_from_devices──► KeyPress/MousePress/...  ──► Intent(gesture, nothing)
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

The reader threads a [`Intent`](projection-system.md#the-change-the-reader-threads)
(the originating `gesture` plus the `operation` produced so far) and walks the
pipeline last-to-first, calling `read_intent` on each step. The `gesture`
rides along unchanged; the first step that fills in a non-nothing `operation`
short-circuits the walk, and subsequent earlier steps translate that operation
further toward the document's own domain.

Within a single structural projection, the reader recurses the same way the
printer did: it **delegates a raw authoring gesture to the projection of the
selected child** and **lifts** the child's operation back into its own domain by
prepending the step that reaches the child (`reroot_operation`) — handling the
gesture itself (via [`read_gesture`](projection-system.md#domain-owned-geometry-free-gesture-mapping-read_gesture))
only when the child declines. This is what makes `,`/`Tab` reach the *nearest
enclosing* object/array rather than only the root. See
[Recursive gesture reading](projection-system.md#recursive-gesture-reading-delegate-to-the-selected-child-lift-the-operation).

## Adding a new operation

**First ask whether you need one.** If the gesture just writes a value into a slot
(a field, or an element of a sequence), emit a `ReplaceReferencedValueOperation` — or a
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
  updates flow *only* through reactive Cell writes (`print!` reuses
  `editor.iomap` whenever it is non-`nothing`). So an `evaluate_operation` must
  change the document by writing into the Cells that are already wired into the
  projection graph. If an operation instead swaps a whole value/subtree out from
  under the projection (replacing the structure the iomap was built against), it
  must **null `editor.iomap`** to force a fresh `print_document` — exactly what a
  `ReplaceReferencedValueOperation` with an empty reference (the `replace_document` whole-root
  swap) does. An operation that silently rebinds structure without dropping the iomap
  renders stale.
- **A new *reference-carrying* operation must be registered in two places.** If
  your operation embeds a `Reference` that has to cross projection boundaries
  — the generic `ReplaceReferencedValueOperation` (when `document === nothing`), or the
  remaining path-bearing types `ReplaceSelectionOperation` /
  `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`, or a
  `CompoundOperation` of them — it is only retargeted/rerooted automatically if it
  is handled in **both** the default `read_intent`
  ([projection/Projection.jl](../../../source/kernel/projection/Projection.jl)) **and**
  `reroot_operation`
  ([operation/Rerooting.jl](../../../source/kernel/operation/Rerooting.jl)).
  Both enumerate the path-bearing operation types explicitly; an operation missing
  from either is **silently passed through unmapped** — its reference stays in the
  wrong domain with no error. A `ReplaceReferencedValueOperation` that carries its own root
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

## The operation layer

The material above is *how* to reach for and add operations. The rest of this
guide is the layer's **structure** — where the code lives and the two open seams
every path-bearing operation or container document extends.

Layer 10 of the kernel is **changing documents**. An operation is the reified
edit the reader side of the projection pipeline produces and
`evaluate_operation` applies. The layer holds the abstract `Operation`
supertype, the built-in concrete operations, the selection propagation, the
splice helpers, and the **two open seams** below.

The layer lives in [main/operation/](../../../source/kernel/operation/), inside one aggregator
module (`OperationModule`) split across three fragments:

```
OperationModule.jl        (OperationModule)             — the aggregator
        │ imports Cell + Document + Reference; exports every public name
        ├─ Interface.jl        — Operation abstract + evaluate_operation +
        │                        invalidate_projection! generics
        ├─ Operations.jl       — the built-in ops (DoNothing, ReplaceSelection,
        │                        ReplaceReferencedValue, CompoundOperation,
        │                        SelectNextInsertion, Adjust*, Quit,
        │                        ToggleCollapse), splice helpers, selection
        │                        propagation (clear/set/update), and the
        │                        open child_reference_steps seam
        └─ Rerooting.jl        — reroot_reference + the open
                                 reroot_operation seam with its base methods
```

The three files share one namespace because they are only ever imported
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

The `isa CellVector` branch is the smell — an operation-layer file
hard-referencing a concrete document type. The open generic form dissolves it:

```julia
function child_reference_steps end                # declaration in Operations.jl

child_reference_steps(node) = [(FieldReferenceStep(...), val), ...]   # default (fieldnames)

# in base's Collection.jl:
child_reference_steps(node::CellVector) = [(RangeReferenceStep(i-1, i), node[i]), ...]
```

A new container document type adds a `child_reference_steps` method beside its
type definition. The default handles ordinary structs.

**Testing pressure.** `test/operation/TraversalTest.jl` defines a test-local
`@document struct ToyList` and registers its own `child_reference_steps`
method — the exact pressure that keeps the seam honest. If a fresh test-local
type couldn't drive the walk, the seam wouldn't be open.

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
would import `PrimitiveModule` from a lower kernel layer — a wrong-direction
edge. The open generic form avoids it, with the base methods in
`Rerooting.jl`:

```julia
function reroot_operation end
reroot_operation(::Nothing, steps) = nothing
reroot_operation(op, steps) = op                      # catch-all: unchanged
reroot_operation(op::ReplaceSelectionOperation, steps) = ...
reroot_operation(op::ReplaceReferencedValueOperation, steps) = ...
reroot_operation(op::CompoundOperation, steps) = ...
```

The `Primitive` methods live in `document/Primitive.jl` beside the
operation type declarations:

```julia
# document/Primitive.jl:
reroot_operation(op::ReplaceStringRangeOperation, steps) =
    ReplaceStringRangeOperation(reroot_reference(op.reference, steps), op.replacement)
reroot_operation(op::ReplaceNumberRangeOperation, steps) = ...
```

A new path-bearing operation type MUST add a `reroot_operation` method; missing
methods fall through to the catch-all and are returned unchanged, so their
reference is never rerooted. This is one half of the [reference-carrying
registration invariant](#two-invariants-every-operation-must-respect) above (the
other half is the default `read_intent`).

**Testing pressure.** `test/operation/RerootingTest.jl` declares a test-local
`ToyPathOperation <: Operation` and registers its own `reroot_operation` method,
proving the seam is genuinely open — you cannot depend on a concrete
higher-layer type at layer 10.

### Downward edges

- `..CellModule: Cell, AbstractCell`
- `..DocumentModule: Document`
- `..ReferenceModule: Reference, …, extend_reference, evaluate_reference, …, clear_selection!, set_selection!, with_selection`

That is the whole import surface. No projection, no device, no editor. This
is what keeps the operation layer at index 5 in the DAG.
