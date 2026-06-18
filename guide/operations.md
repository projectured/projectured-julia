# Operations

An **operation** is a user gesture expressed in the document's own terms,
decoupled from the raw device event that triggered it. The reader side of
the projection pipeline produces operations; the editor applies them via
`evaluate_operation`.

The abstract supertype lives in
[api/Operation.jl](../program/src/api/Operation.jl) and the built-in operations
in [common/Operation.jl](../program/src/common/Operation.jl).

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

## Other domain operations

| Operation | Where it lives | Effect |
|---|---|---|
| `HideWidgetOperation(widget)` | `document/Widget.jl` | sets `widget.visible = false` |
| `ShowWidgetOperation(widget)` | `document/Widget.jl` | sets `widget.visible = true` |
| `ScrollWidgetOperation(scroll_pane, dx, dy)` | `document/Widget.jl` | adjusts scroll offsets |
| `SelectTabOperation(tabbed_pane, index)` | `document/Widget.jl` | switches the active tab |
| `SetScrollBarValueOperation(bar, value)` | `document/Widget.jl` | sets scroll-bar position |
| `NumberReplaceRangeOperation(...)` | `document/Primitive.jl` | edits a `PrimitiveNumber` |
| `StringReplaceRangeOperation(...)` | `document/Primitive.jl` | edits a `PrimitiveString` |
| `ReplaceFocusPartOperation(projection, part)` | `projection/generic/Focusing.jl` | retargets a `FocusingProjection` |
| `WorkbenchOpenDocumentOperation(page, entry)` | `document/Workbench.jl` | appends `entry` to `page.elements` (open a tab) |
| `WorkbenchCloseDocumentOperation(page, index)` | `document/Workbench.jl` | removes `page.elements[index]` (close a tab) |

Operation modules are the right place to look when wiring a new gesture:
the operation declares its semantics once, projections that emit it stay
small, and the editor's `evaluate!` dispatches on type.

Note that these operations **carry their own target** (a widget, a
`WorkbenchPage`, a reference path), so applying one never depends on where the
document sits in the tree — there is no "find the workbench from the editor"
step baked into them. That is what makes the programmatic path below general.

## Driving operations programmatically (scripting the editor)

`evaluate_operation(editor, op)` is the **one way** to change the document, and
you can call it yourself — it is the same step the editor loop runs after a
gesture. So to script the editor (e.g. from `execute_julia_code`, or the REPL),
do exactly what a reader does: find the target, build the operation, evaluate it.

```julia
# Move the selection: find the node's path, then select it.
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

## The fall-through cases

```julia
evaluate_operation(editor, ::Nothing) = nothing
evaluate_operation(editor, op)        = nothing  # any other type
```

These exist so the reader can return whatever it likes (including raw
events that nothing knows how to handle) without crashing the editor —
unknown values simply produce no effect.
