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
function evaluate_operation(op::Operation, document) end   # generic function
```

## The two built-in selection operations

### `ReplaceSelectionOperation(path)`

Carries a `ReferencePath` and is produced by every reader translating a
cursor-navigation gesture. Its evaluation:

```julia
function evaluate_operation(op::ReplaceSelectionOperation, document)
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

Operation modules are the right place to look when wiring a new gesture:
the operation declares its semantics once, projections that emit it stay
small, and the editor's `evaluate!` dispatches on type.

## Reader → operation → evaluate flow

```
SDL_EVENT ──read_from_devices──► KeyPress/MouseClick/...
                                          │
                                          ▼
                       projection_read(projection, iomap, event)
                                          │
                                          ▼
                               Operation or nothing
                                          │
                                          ▼
                       evaluate_operation(op, document)
                                          │
                                          ▼
                             cells written → invalidated
                                          │
                                          ▼
                       projection_print refreshes the iomap lazily
```

The reader walks the pipeline last-to-first, calling `projection_read` on
each step. The first step that returns a non-nothing value short-circuits
the walk; subsequent earlier steps translate the operation further toward
the document's own domain.

## Adding a new operation

1. **Declare it.** `struct MyOp <: Operation; ...; end` in the most natural
   module (the domain that owns the affected document, or `OperationModule`
   for cross-domain operations).
2. **Define `evaluate_operation(::MyOp, document)`**. Use the existing
   primitives — `replace_selection!`, mutating reactive cells, throwing
   `QuitEditorException` — rather than reaching directly into private state.
3. **Have a projection produce it.** Add a `projection_read` method on the
   projection that owns the gesture; return `MyOp(...)` instead of
   `nothing` when the event applies.
4. **(Optional) Translate it upstream.** If the operation needs to flow
   through more projections before reaching the document, give the
   upstream projections matching `projection_read` methods that consume the
   downstream operation and emit an equivalent operation in their own
   input domain.

## The fall-through cases

```julia
evaluate_operation(::Nothing, document) = nothing
evaluate_operation(op, document)        = nothing  # any other type
```

These exist so the reader can return whatever it likes (including raw
events that nothing knows how to handle) without crashing the editor —
unknown values simply produce no effect.
