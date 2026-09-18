# Undo and redo

**Status (2026-09-18): PENDING.** Nothing of this plan is implemented. The
editor has no undo and no redo today, and
[concepts.md](../../documentation/design/concepts.md) says so.

**Goal:** a person edits a document, presses `Ctrl+Z`, and the document returns
to the state before the edit. `Ctrl+Y` puts the edit back. The history is a
document of its own, so a person can see it, and a projection can show it. The
mechanism is domain-free: it works for JSON, for a state machine, for a widget
tree, and for a domain that does not exist yet.

**Repositories:** projectured-julia only. The plan changes no sealed file. It
changes files of kernel layer 10 (`operation/`) and one file of kernel layer 13
(`projection/ProjectionDefaults.jl`). [SEALING.md](../../SEALING.md) marks every
one of them `⬜`.

## 1. The request and the rulings

> create a new plan for undo/redo operations
>
> so there should be an API which creates an undo operation for a given
> operation when the undo/redo buffer document and its projection wraps a
> document it wraps the operations in a way which when the operation gets
> executed puts the reverse operation on the undo buffer. This projection can
> implement the usual undo/redo gestures. we should have support for filtering
> operations (e.g. selection changes may or may not be undone), some operations
> may not support generating an undo operation, e.g. saving a file.

> it's not neccessary to use the undo/redo in all examples, this should be
> demonstrated and tested on its own and then included in the final projectured
> binary
>
> it's unclear if we need one undo/redo buffer per application or we need one
> per file document or both

U17 answers the second question: **both**, and U17 says what makes the two
compose. U18 and U19 answer the first.

The words mean this in the code:

| Word | Meaning |
| --- | --- |
| undo/redo buffer document | `UndoBuffer`, a `Document` that holds another document and two lists of entries |
| its projection | `UndoBufferToAnyProjection`, which prints the held document and answers its output, the way `VersioningToAnyProjection` answers the selected version's output |
| wraps the operation | the projection's reader puts the operation the inner reader made inside a `RecordUndoOperation`, which carries the buffer |
| the API | `make_inverse_operation(document, operation)`, an open generic that answers the operation that takes the document back |
| the reverse operation | the inverse. The same function serves undo and redo, so the plan calls it the inverse, not the undo operation |
| filter | a predicate on the projection that decides which operations enter the history at all |
| an operation with no undo | an operation for which `make_inverse_operation` answers `nothing` |

## 2. What exists

### The operation layer (kernel layer 10)

[source/kernel/operation/](../../source/kernel/operation/) holds `Operation`,
`evaluate_operation(editor, op)`, the cross-domain operations, and two open
seams. The layer is not sealed.

- `evaluate_operation` is duck-typed on `editor`. Its docstring says the editor
  is "whatever object holds the mutable runtime state the operation needs, with
  `editor.document` carrying the root document". Production code already passes
  a shim: `PaneHost` in [PaneSurgery.jl:149](../../source/pane/PaneSurgery.jl#L149).
- `ReplaceReferencedValueOperation` carries the whole family of writes: a field
  write, an element overwrite, a range splice, and a whole-root swap. Most edits
  of every domain are one of these.
- `CompoundOperation` applies several operations as one editor step.
- `reroot_operation(op, steps)` prepends steps to the reference inside an
  operation. It is the seam a container reader uses when it forwards an
  operation from a child.
- The default `read_intent` in
  [ProjectionDefaults.jl:117](../../source/kernel/projection/ProjectionDefaults.jl#L117)
  maps an operation from a projection's output domain to its input domain.

`PAR-REGISTER-NEW-OPERATION` says a new reference-carrying operation must be
registered in both places, or its reference is silently left in the wrong
domain.

### The rule that shapes the design

`PAR-READER-IS-PURE` says a reader never mutates; it returns an operation. Its
own text names undo as one of the mechanisms that a mutating reader would break:

> A reader that mutates is invisible to every mechanism built on the operation
> stream — undo, playback, scripting, logging, an agent driving the editor —
> because the edit never becomes an operation.

So the history must not be written by a reader. The reader names the effect as
an operation, and `evaluate_operation` applies it.

### Two near relatives

**`VersioningToAnyProjection`**
([source/versioning/VersioningToAny.jl](../../source/versioning/VersioningToAny.jl))
is the shape the undo projection copies. A `VersionedObject` wraps a value; the
projection prints the selected value through `print_child` and answers its
output, so the wrapper vanishes from the screen. The reader delegates into the
child IoMap and prefixes the steps that reach the child. Its own gestures come
from `get_projection_gesture_bindings`.

**`GestureLogRecordingProjection`**
([source/gesturelog/GestureLogRecording.jl](../../source/gesturelog/GestureLogRecording.jl))
is a transparent decorator that records what the reader chain below it decides.
It shows that a decorator can see every operation, and it holds the filter idea
(`default_gesture_log_filter`) and the human rendering of an operation
(`describe_operation`). It records **inside the reader**, which breaks
`PAR-READER-IS-PURE`. The undo buffer must not copy that half.

Neither is a restorable history. `GestureLog` stores strings, not operations.
`VersionedObject` stores whole deep copies, one per manual gesture.

### The frame

`run_frame!` calls `read!` and then `evaluate!`, one operation at a time, at
most 32 times before it repaints. `drain_operations!` applies whatever
`post_operation!` put in the inbox, before the frame reads anything. The editor
makes the zoom and the quit operations itself, after the pipeline declines the
gesture.

## 3. Decisions

The decisions are numbered U1 to U19.

### The shape

#### U1. The buffer is a document, and its projection is transparent

```julia
abstract type UndoDocument <: Document end

@document struct UndoBuffer <: UndoDocument
    content::Document      # the document whose edits this buffer records
    undo_entries::CellVector   # oldest first; the last one is the next undo
    redo_entries::CellVector   # oldest first; the last one is the next redo
    capacity::Int = 100
end
```

`UndoBufferToAnyProjection` prints `content` through `print_child` and answers
the child's output. The wrapper draws nothing of its own, exactly as
`VersioningToAnyProjection` draws nothing of its own. `map_reference_forward`
peels the `content` step; `map_reference_backward` prepends it.

A buffer is a node of the document tree, so a workbench can give each tab its
own history, and a nested application keeps its own. This is why the buffer is a
document and not a field of the editor.

#### U2. The reader wraps the operation; it never records

The reader answers `RecordUndoOperation(buffer, operation)`. Nothing is written
until `evaluate_operation` runs. This is `PAR-READER-IS-PURE`, and it is what
makes the same history work for an edit that a tool made (U15) rather than a
key press.

```julia
struct RecordUndoOperation <: WrappingOperation
    buffer::UndoBuffer
    operation::Any
end
```

`evaluate_operation(editor, op::RecordUndoOperation)` does two things:

1. `inverse = evaluate_invertible_operation!(editor, op.operation)` — ask for the
   way back **and** apply, in that order (U6).
2. Push one entry on `buffer.undo_entries` and empty `buffer.redo_entries`.

The inverse is taken before the change, because an inverse needs the state the
change starts from. That ordering is the whole reason the recording is an
operation and not a decorator around `evaluate_operation`.

### The API

#### U3. `make_inverse_operation(document, operation)`

This is the API the request asks for. It is an open generic in the kernel
operation layer, beside `reroot_operation`:

```julia
"""
    make_inverse_operation(document, operation) -> operation or nothing

The operation that takes `document` back to the state it is in now, after
`operation` is applied to it. `nothing` when this operation has no way back.
"""
function make_inverse_operation end

make_inverse_operation(document, operation) = nothing   # the default: no way back
```

The name says "inverse" and not "undo" because the same function serves both
directions: a redo entry is the inverse of an undo entry (U8).

The base methods, in `source/kernel/operation/Inversion.jl`:

| Operation | The inverse |
| --- | --- |
| `DoNothingOperation` | itself |
| `ReplaceSelectionOperation` | `ReplaceSelectionOperation` of the selection the document holds now, or `DoNothingOperation()` when it holds none |
| `ReplaceReferencedValueOperation`, terminal `FieldReferenceStep` | the same operation with the value the field holds now |
| the same, terminal `RangeReferenceStep`, one value | the same operation with the element the container holds at that index now |
| the same, terminal `RangeReferenceStep`, a vector of `n` items | a splice of `[start, start + n)` with the **cells** the container holds in `[start, stop)` now |
| the same, empty reference (a whole-root swap) | the same operation carrying the current root |
| `ToggleCollapseOperation` with a concrete target | itself |
| `SelectNextInsertionOperation` | `ReplaceSelectionOperation` of the selection the document holds now |
| `CompoundOperation` | see U6 |
| `AdjustZoomOperation`, `AdjustFontZoomOperation`, `QuitEditorOperation` | `DoNothingOperation()` |

The splice inverse captures **cells**, not values, through `get_cell_at`. A redo
then puts the same cell objects back, so identity survives a round trip and the
widgets that hold them survive with it.

Methods for an operation of a higher package live beside that operation's own
declaration, exactly as `reroot_operation` does today:

| Operation | File | The inverse |
| --- | --- | --- |
| `ReplaceStringRangeOperation` | [source/primitive/PrimitiveDocument.jl](../../source/primitive/PrimitiveDocument.jl) | replace `[start, start + length(replacement))` with the text that is there now |
| `ReplaceNumberRangeOperation` | the same file | the same, over the textual form of the number |
| `MoveRangeOperation` | [source/dragging/Dragging.jl](../../source/dragging/Dragging.jl) | the move that puts the range back |
| `SaveDocumentOperation`, `ExportDocumentOperation`, `WriteOsClipboardOperation` | their own files | `DoNothingOperation()` — they change no document, so there is nothing to take back |
| `RecordUndoOperation`, `UndoOperation`, `RedoOperation` | the undo slice | the three methods of R2 in U17, which are what makes one buffer hold another |

Every other operation keeps the default and has no inverse. That is the honest
answer, and U5 says what the buffer does with it.

#### U4. Three questions, three mechanisms

The request names two of these. They are different questions and each gets its
own mechanism.

| Question | Mechanism | Where it is answered |
| --- | --- | --- |
| Does this step belong in the history at all? | the filter, a field of the projection | at read time, before the wrapper is built |
| Can this step be taken back? | `make_inverse_operation` | at evaluate time |
| What happens when it can not? | a barrier entry | at evaluate time |

A save passes the filter or does not, as the user configures. Either way it
answers `DoNothingOperation()`, so an undo that reaches it steps over it. An
operation nobody taught to invert answers `nothing`, and the buffer records a
barrier.

#### U5. An operation with no inverse is a barrier

An entry whose `inverse` is `nothing` is a barrier. Undo refuses to go past it
and says why. The alternative — step over it and undo the entry before it —
produces a document that matches no state the person ever saw.

A barrier is not an error. A domain that adds an operation and forgets the
inverse gets a history that stops at that operation, which is visible, rather
than a history that quietly lies.

#### U6. A container is inverted while it is applied

The inverse of `CompoundOperation([a, b])` is not
`CompoundOperation([inverse(b), inverse(a)])` computed up front: the inverse of
`b` depends on the state after `a` ran. Two deletes of `elements[2]` show it
at once.

So the recorder does not compute the whole inverse and then apply. It uses a
second open generic that does both in the right order:

```julia
"""
    evaluate_invertible_operation!(editor, operation) -> operation or nothing

Apply `operation` and answer the way back. `nothing` when there is none.
"""
evaluate_invertible_operation!(editor, operation) =
    (inverse = make_inverse_operation(editor.document, operation);
     evaluate_operation(editor, operation);
     inverse)

function evaluate_invertible_operation!(editor, op::CompoundOperation)
    inverses = Any[]
    for member in op.operations
        inverse = evaluate_invertible_operation!(editor, member)
        inverse === nothing && return nothing      # the whole step is a barrier
        pushfirst!(inverses, inverse)
    end
    CompoundOperation(inverses)
end
```

The loop applies each member and inverts it against the state that member sees.
The generic is open, so a container operation of a higher package adds its own
method. A member that answers `nothing` makes the whole step a barrier, and the
members that already ran stay applied — the document is correct, and only the
way back is gone.

#### U7. An entry holds a label, an inverse and a selection

```julia
struct UndoEntry           # a plain struct, like GestureLogEntry
    label::String          # describe_operation of the forward operation
    inverse::Any           # the way back, or nothing for a barrier
    selection::Any         # the selection before the step, or nothing
end
```

The selection is what makes undo feel right: after the inverse runs, the caret
returns to where the edit happened. Without it the value comes back and the
caret stays where it drifted to. The restore is guarded — `replace_selection!`
throws `SelectionMismatchException` on a path the document no longer matches, so
the restore is tried and a miss is ignored.

`describe_operation` renders the label. It lives in the gesture-log slice today,
so U12 moves it.

#### U8. Redo is the inverse of the undo

`UndoOperation(buffer)` pops the last undo entry, applies its inverse through
`evaluate_invertible_operation!`, and pushes what that answers on
`redo_entries`, with the same label. `RedoOperation(buffer)` does the mirror
image. So there is one recording mechanism and no second, forward-facing one.

A recorded edit empties `redo_entries`. That is the usual rule, and it keeps a
redo from putting back a change that the document has moved past.

Both operations carry the buffer by identity, so they are self-contained:
`operation_travels_unchanged` answers `true` for them and no seam has to reroot
them.

### The kernel seam

#### U9. `WrappingOperation` — one seam, not one special case per site

`RecordUndoOperation` holds another operation. Every place that maps a
`CompoundOperation` member by member has to map a wrapper's inner operation the
same way, or the inner reference is left at the wrong depth with no error. The
operation guide already states the rule for `CollectedIntentsOperation`:

> **Any seam that maps a `CompoundOperation` elementwise must map this one too.**

Rather than name `RecordUndoOperation` at each site, the kernel gets one open
protocol and the sites learn it once:

```julia
abstract type WrappingOperation <: Operation end

get_wrapped_operation(op::WrappingOperation)        # the inner operation
rewrap_operation(op::WrappingOperation, inner)      # op with a new inner operation
```

One method in `Rerooting.jl` then serves every wrapper that will ever exist:

```julia
reroot_operation(op::WrappingOperation, steps::Tuple) =
    rewrap_operation(op, reroot_operation(get_wrapped_operation(op), steps))
```

The eight sites that map a compound member by member each get one branch:

| File | What it is |
| --- | --- |
| [source/kernel/projection/ProjectionDefaults.jl:150](../../source/kernel/projection/ProjectionDefaults.jl#L150) | the default `read_intent` |
| [source/kernel/operation/Rerooting.jl:53](../../source/kernel/operation/Rerooting.jl#L53) | `reroot_operation` |
| [source/versioning/VersioningToAny.jl:236](../../source/versioning/VersioningToAny.jl#L236) | `_prefix_op` |
| [source/workbench/WorkbenchToWidget.jl:645](../../source/workbench/WorkbenchToWidget.jl#L645) and [:813](../../source/workbench/WorkbenchToWidget.jl#L813) | two prefix helpers |
| [source/widget/WidgetToGraphics.jl:881](../../source/widget/WidgetToGraphics.jl#L881) | the widget prefix helper |
| [source/screen/WindowManaging.jl:106](../../source/screen/WindowManaging.jl#L106) | the window prefix helper |
| [source/screen/ScreenToScreen.jl:198](../../source/screen/ScreenToScreen.jl#L198) | the screen prefix helper |
| [source/assistant/AssistantToWidget.jl:272](../../source/assistant/AssistantToWidget.jl#L272) | the assistant prefix helper |
| [source/layout/LayoutToGraphics.jl:281](../../source/layout/LayoutToGraphics.jl#L281) | `_annotate_operation` |

This is the same work as a special case at each site, done once for every
wrapper that follows: a transaction, a macro recorder, a trace.

`CompoundOperation` and `CollectedIntentsOperation` stay as they are. They hold
many operations, not one, so they are not wrappers.

### The gestures and the filter

#### U10. The projection owns the gestures

`get_projection_gesture_bindings(p::UndoBufferToAnyProjection, iomap)` declares
them, so the gesture help shows them beside every other rule:

| Gesture | Operation |
| --- | --- |
| `Ctrl+Z` | `UndoOperation(buffer)` |
| `Ctrl+Y`, `Ctrl+Shift+Z` | `RedoOperation(buffer)` |

The reader **delegates first and fires its own bindings last**, which is R1 of
U17: with two buffers on one path, the one closest to the focus must answer. The
binding matches on `change.gesture`, which the reader chain threads unchanged,
so it works even when a lower stage already turned the key into an operation of
its own.

An undo with an empty stack answers `nothing` and falls through to the inner
reader. It does not consume the key.

#### U11. The filter is a plain field, and the default drops a bare selection move

```julia
UndoBufferToAnyProjection(; filter = is_undo_step)

is_undo_step(gesture, operation) =
    !(operation === nothing ||
      operation isa DoNothingOperation ||
      operation isa ReplaceSelectionOperation)
```

A caret move follows almost every key and almost every click, and a history full
of caret moves is a history a person can not use. A compound that contains a
write is kept, because the filter sees the whole operation and only a bare
`ReplaceSelectionOperation` matches. A person who wants caret moves undone
passes `(gesture, operation) -> operation !== nothing`.

The field is a plain field of a plain struct, not a reactive field. A `Function`
in a reactive field becomes a thunk, and the reader would call it with no
arguments. `GestureLogRecordingProjection` carries the same warning.

#### U12. `describe_operation` moves down to the operation layer

It renders an operation for a human, it depends only on `operation_reference`
and on reference printing, and two slices now need it. It moves from
[source/gesturelog/GestureLogDocument.jl](../../source/gesturelog/GestureLogDocument.jl)
to a new fragment `source/kernel/operation/Description.jl`, with its three
private helpers. `describe_gesture` stays where it is: it belongs to the event
vocabulary, not to operations. The gesture log then imports the name. No other
file uses it today, so the move is one import line.

### Where the entries point

#### U13. An entry is buffer-relative, so the buffer survives a move

The inverse that `make_inverse_operation` computes is rooted at
`editor.document`, because that is the frame the operation reaches the editor
in. A path rooted at the editor goes stale when the buffer moves: a tab is
dragged, a pane is split, a window is closed. The stored entry then points at
another document's slot.

So `RecordUndoOperation`, `UndoOperation` and `RedoOperation` each carry the
prefix that leads from the editor's root to the buffer:

```julia
struct RecordUndoOperation <: WrappingOperation
    buffer::UndoBuffer
    operation::Any
    prefix::Reference      # the steps that reach the buffer, root first
end
```

The projection builds it with its own `content` step. Every reroot prepends the
same steps to the prefix that it prepends to the inner operation, so at evaluate
time the prefix is exactly the path from the root to `buffer.content`. The
recorder strips it from the inverse before it stores the entry, and undo
prepends the prefix it carries **at that moment** before it applies. The stored
entry therefore never names anything above the buffer.

Comparison strips type checkpoints first: a stored reference carries them and a
freshly built prefix may not. An inverse whose reference does not start with the
prefix — a restored selection that pointed outside the buffer — becomes a
barrier rather than a wrong write.

This is step 6, not step 4. Undo works at the root of the editor without it, and
the prefix is what makes it correct in a workbench.

### The rest

#### U14. What is not recorded, and why

| Not recorded | Why |
| --- | --- |
| the operations the editor makes itself (zoom, quit) | they are made after the pipeline declines the gesture, so they never reach the projection |
| an operation from `post_operation!` | the inbox goes straight to `evaluate_operation`; a driver that advances a simulation must not fill the history of the person editing beside it |
| an edit outside the buffer | a buffer records only what passes through it. This is the point of a buffer being a node |

A driver or a tool that **wants** its change undone wraps it itself, with
`make_undoable_operation(buffer, operation)`. That function is the one public
way to opt in from outside the reader.

#### U15. The assistant edits through the same door

The tool set changes documents through `evaluate_operation`. Step 8 routes the
document-changing tools through `make_undoable_operation`, and adds an `undo`
and a `redo` tool. Then a change by a model and a change by a person are the
same kind of thing in the history too, which is what
[concepts.md](../../documentation/design/concepts.md) promises about edits.

#### U16. The history is a document, so it has a view

Step 8 adds `UndoBufferToSyntax`, which makes a list of the entries with the
newest first, the position marked, and a barrier drawn as a line the history can
not cross. It is the direct analogue of `GestureLogToSyntax`. A click on an
entry undoes to there. This step is what turns "the history is data" from a
claim into something a person can see.

### How many buffers, and where

#### U17. Both: one per application, and one per file document

The two are not alternatives. They answer different needs, and the mechanism
composes them, because a buffer is a node of the document tree and a buffer can
hold another buffer.

| Buffer | What it covers | What it is for |
| --- | --- | --- |
| the application buffer, around the window content | every step, in the order it happened, including a step an inner buffer recorded and a step that belongs to no file | the floor. A splitter move, a tab that opens, a configuration change and a chat draft are edits too, and no file buffer sees them |
| a file buffer, around the content of each file editor | the steps inside that one file | what `Ctrl+Z` means to a person. An undo in one file must not take back an edit in another |

Four rules make the two coherent.

**R1. The innermost buffer answers the gesture.** The reader delegates into the
child **first** and fires its own bindings only when the child declined. So the
buffer closest to the focus answers `Ctrl+Z`, which is what a person expects.
This is the opposite of `VersioningToAnyProjection`, which fires its own
bindings first; the undo buffer takes the other order, on purpose.

**R2. Undo and redo are each other's inverses.** Three methods, and the nesting
works:

```julia
make_inverse_operation(document, op::RecordUndoOperation) = UndoOperation(op.buffer)
make_inverse_operation(document, op::UndoOperation)       = RedoOperation(op.buffer)
make_inverse_operation(document, op::RedoOperation)       = UndoOperation(op.buffer)
```

An outer buffer therefore never repeats the work of an inner one. It records
"this inner buffer took one step", and it takes that step back by asking the
inner buffer to undo — which keeps the inner buffer's own two stacks correct at
the same time. An undo a person makes at the inner level is itself an edit, and
the outer buffer records it as one, with `RedoOperation` as its way back.

This holds because every push on an inner buffer is matched by a push on the
outer buffer, in the same order. The top of the outer stack therefore always
corresponds to the top of the inner stack it names. Two file buffers under one
application buffer keep the property, because each outer entry names the buffer
it belongs to.

**R3. A buffer never records its own undo or redo.** It records another
buffer's.

**R4. An outer buffer does not re-decide the filter.** When it sees a
`RecordUndoOperation` from an inner buffer, it records it, whatever its own
filter says. The inner buffer already decided, and a filter that differs between
two levels breaks the correspondence of R2.

**Deliver the application buffer first.** One buffer around the window content
makes every edit undoable, needs none of R1 to R4, and is testable on its own.
The file buffers come after, with the four rules, and they are what makes
`Ctrl+Z` local. Both halves are step 7, in that order.

#### U18. No example installs a buffer, and the application installs two

A buffer is opt-in. No domain chain and no example of a domain gets one: the
undo slice has its own example, which demonstrates it, and its own test package,
which tests it. Nothing else changes.

The application is the one program that installs a buffer, and it installs both
kinds:

| Where | What | The file |
| --- | --- | --- |
| around the window content | the application buffer | `make_application_document` in [example/projectured/Application.jl](../../example/projectured/Application.jl) |
| around the content of every file editor | a file buffer | `make_workbench_file_editor` in [source/workbench/WorkbenchFile.jl:68](../../source/workbench/WorkbenchFile.jl#L68) — one line, and every file the navigator opens gets one, because `OpenWorkspaceFileOperation` calls the same function |
| the projections | `UndoBuffer => UndoBufferToAnyProjection()` in `make_application_content_projections`, and in the first stage of the window projection for the application buffer | the same `Application.jl` |

`WorkbenchEditor.content` then holds a buffer rather than the domain document,
so three places in `WorkbenchFile.jl` must look through it: the save
([line 27](../../source/workbench/WorkbenchFile.jl#L27)), the reload
([line 44](../../source/workbench/WorkbenchFile.jl#L44)) and the group finder
([line 117](../../source/workbench/WorkbenchFile.jl#L117)). They call one
generic, `get_wrapped_document(node)`, declared in `ProjecturedDomain` with the
identity as its default; the undo slice adds the method for `UndoBuffer`. The
workbench therefore names no undo type.

A reload replaces the content from disk. The way back is gone, so the reload
pushes a barrier (U5) rather than keeping a history that no longer fits.

#### U19. `ProjecturedUndo` sits above the domains, not in the substrate

The tier decides how many files name the package.

- A **substrate** package is one of the twenty-eight that every domain sits on,
  so every domain's `Example` and `Test` package lists it. `ProjecturedVersioning`
  is one, and about a hundred files name it.
- An **application** package is one that only a program above the domains uses.
  `ProjecturedWorkbench`, `ProjecturedAssistant` and `ProjecturedConversation`
  are there. About ten files name each.

One grep shows the difference: `package/ProjecturedJsonTest/Project.toml` names
`ProjecturedVersioning`, and it names `ProjecturedWorkbench` nowhere.

Nothing below an application depends on undo, and U18 says no example does
either, so undo belongs in the application tier. `ProjecturedUndo` goes at the
end of the `_SOURCES` tuple in
[source/projectured/Projectured.jl](../../source/projectured/Projectured.jl),
beside `ProjecturedWorkbench`, and **not** in the `SUBSTRATE` list of
`test/projectured/PackageGraphTest.jl`. `using Projectured` still gives
`UndoBuffer`, because the umbrella names it.

The slice gets three packages, which is what "demonstrated and tested on its
own" needs: `ProjecturedUndo`, `ProjecturedUndoExample` and
`ProjecturedUndoTest`. `test_undo()` then runs in an environment that holds only
what undo needs.

### Why not otherwise

**A root decorator, like `GestureLogRecordingProjection`.** One recorder at the
top of the composed projection sees every operation with no rerooting at all,
and needs no `WrappingOperation` seam. It gives one history for the whole
editor. It can not give a tab its own history, it can not say which region an
edit belonged to, and the history is not a document, so nothing can show it,
save it or edit it. The buffer as a node gives all of those, and U9 pays for
them once.

**A snapshot per edit, like `VersionedObject`.** A deep copy per key press costs
the whole document per entry, loses the identity of every cell, and therefore
loses every widget that holds one. An inverse operation costs one old value.

**Record in the reader.** It is shorter and it is what the gesture log does. It
breaks `PAR-READER-IS-PURE`, and it records an edit that the editor may never
apply.

## 4. Deferred

- **Coalescing.** Typing five characters makes five entries and needs five
  presses of `Ctrl+Z`. A later step merges consecutive range edits on the same
  reference inside a time window, behind one predicate, `can_merge_undo_entries`.
- **A third level of buffers.** U17 states the rules for two levels and the
  correspondence they rest on. Three levels should follow from the same rules,
  and nothing tests it.
- **An outer undo that crosses a filter difference.** R4 forbids the case rather
  than handling it. A buffer whose filter differs from the buffer above it is
  not a supported arrangement.
- **A history that outlives the session.** An entry holds a live operation, and
  an operation is not serializable today. The cell serializer is value-only.
- **Undo of an external effect.** A file that is written, a clipboard that is
  set. They answer `DoNothingOperation()`, so a history steps over them.
- **A shared history across two panes that show one document.** Each buffer
  records only what passes through it.

## 5. Steps

Do the work in a worktree beside the checkout. Commit once per step. Mark each
box here as it is done, and write into this file what the step decided that this
plan did not foresee.

### Step 0 — baselines and probes

- [x] The baseline of `test_kernel()` on the branch point (`c5dfb9b7`):
      **1915 pass, 3 fail, 3 error, 23.0 s**. The three failures and three
      errors are the known ones: five Rule C assertions of
      `DocumentMacroTest.jl` and `MEvalBranch` of `ReferenceEvalTest.jl`. The
      other three suites are measured in the step that first touches them —
      `test_substrate()` and `test_workbench()` in step 4 and step 7 — because
      a worktree pays a precompile for each environment it uses.
      **A fresh worktree needs `Pkg.resolve()` before its first run**; a bare
      `julia --project=package/ProjecturedKernelTest` says `ProjecturedKernel is
      required but does not seem to be installed`.
- [ ] Write the probe that proves the ordering claim of U6: two deletes of
      `elements[2]` in one `CompoundOperation`, and the inverse that a
      computed-up-front implementation would produce. Keep it as a test.

### Step 1 — the `WrappingOperation` seam (kernel and eight sites)

- [x] `WrappingOperation`, `get_wrapped_operation` and `rewrap_operation` in
      `source/kernel/operation/Interface.jl`; export them from
      `OperationModule.jl`.
- [x] The one `reroot_operation` method in `Rerooting.jl`.
- [x] One branch in the default `read_intent` of `ProjectionDefaults.jl`, beside
      the `CompoundOperation` branch: map the inner operation, and answer
      `nothing` when it does not map.
- [x] One branch at each of the domain sites of the table in U9. **Six sites,
      not seven**, and `WorkbenchToWidget.jl` holds two of them.
      `WindowManaging.jl` is not one: it does not prefix an operation, it
      unpacks a window operation out of a compound and applies it. A wrapper
      reaches it from below and must pass through whole, because unpacking a
      window operation out of a record would change what the record records.
- [x] `test/kernel/operation/RerootingTest.jl` gets a test-local
      `ToyWrapperOperation <: WrappingOperation` with its two methods, and
      asserts that a reroot reaches the inner operation. This is the same
      testing pressure `ToyPathOperation` already applies to the seam.
- [x] Update `PAR-REGISTER-NEW-OPERATION` in
      [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)
      and the seam list in
      [operation.md](../../documentation/package/kernel/operation.md) with the
      third case: a wrapper.
- [x] Test: `test_kernel()` is 1922 / 3 / 3, seven passes above the baseline and
      the same three failures and three errors. `test_substrate()` runs in
      step 4, where the slice that needs it exists.

### Step 2 — `make_inverse_operation` and `evaluate_invertible_operation!`

- [x] The two generics and the base methods in a new fragment
      `source/kernel/operation/Inversion.jl`, included from
      `OperationModule.jl` after `Rerooting.jl`. The U3 table is the method
      list.
- [x] **A new seam the plan did not foresee: `get_slot_at(container, index)`.**
      The kernel can not name `CellVector` — it lives in a package above — so it
      can not call `get_cell_at` to capture the cells of a splice. It declares
      `get_slot_at` with the value as its default, and `ProjecturedCollection`
      answers with the cell. Without it a redo would rebuild every slot cell and
      orphan whatever followed one.
- [x] **`copy_reference` moves into the reference layer.** The selection chain is
      live: the start and the stop of a terminal range step are rewritten in
      place as the caret moves, so a captured selection must be rebuilt from the
      numbers it reads now. It is public in `ReferenceEvaluation.jl`, because it
      is a fact about a reference and not about an operation.
- [x] The methods that belong to a higher package, each beside its operation:
      the two primitive range operations, `MoveRangeOperation`, and the
      `DoNothingOperation()` answers of the three effect-only operations.
      **`ReplaceTextRangeOperation` of the text slice has none yet**: its range
      can cross spans and lines, so its way back needs the text slice's own
      splice. Until then a text-domain range edit is a barrier, and step 5 is
      where that shows.
- [x] A new `test/kernel/operation/InversionTest.jl` with
      `test_inversion()`: one testset per row of the U3 table, each of the form
      "apply, invert, apply the inverse, the document is what it was". Registered
      in `package/ProjecturedKernelTest/src/ProjecturedKernelTest.jl` and in
      `test/kernel/KernelSuite.jl` beside `test_rerooting()`.
- [x] The compound ordering probe of step 0 passes: two deletes of the same index
      in one `CompoundOperation` round-trip.
- [x] Test: `test_kernel()` 1961 / 3 / 3, thirty-nine above step 1.

### Step 3 — `describe_operation` moves to the operation layer

- [x] Moved `describe_operation` and its private helpers to
      `source/kernel/operation/Description.jl`; exported from
      `OperationModule`. It gains one method: a wrapper is described as what it
      holds.
- [x] `GestureLogDocument.jl` keeps `describe_gesture` and re-exports the
      operation one, so a caller that named it there still finds it.
- [x] Test: `test_kernel()`. The gesture-log test runs with the rest of the
      substrate in step 4. **Steps 2 and 3 are one commit**: both change the
      include list of `OperationModule.jl`, so splitting them would put a commit
      in the history that does not load.

### Step 4 — the undo slice

- [x] `source/undo/` with `UndoModule.jl`, `UndoDocument.jl` (the buffer, the
      entry, `push_undo_entry!`, `clear_undo_history!`, `is_undo_step`,
      `is_undo_barrier`, the three operations and their `evaluate_operation` and
      `make_inverse_operation` methods, `make_undoable_operation`) and
      `UndoBufferToAny.jl` (the projection, the two reference maps, the reader
      and the gesture table).
- [x] `package/ProjecturedUndo/` with a `Project.toml` and
      `src/ProjecturedUndo.jl`, in the shape of `ProjecturedVersioning`. It
      declares **two** dependencies and not four: it names nothing of
      `ProjecturedDomain` and nothing of `ProjecturedPrimitive`, and the package
      graph guard asserts that a package declares exactly what it names.
- [x] `package/ProjecturedUndoTest/`, which is what lets `test_undo()` run on
      its own. **No `ProjecturedUndoExample`**: the example needs a domain to be
      worth looking at, so its bodies live in `example/projectured/` inside
      `ProjecturedExample`, exactly where the versioning example's live.
- [x] The wiring, in the **application** tier (U19).
      `package/Projectured/Project.toml` (`[deps]` and `[sources]`),
      `package/Projectured/src/Projectured.jl`,
      `source/projectured/Projectured.jl` (the end of `_SOURCES`),
      `environment/all/Project.toml`, `package/ProjecturedTest/Project.toml`
      and `test/projectured/ProjecturedSuite.jl`. Then `Pkg.resolve()` rewrote
      `environment/all/Manifest.toml`.
      **`ProjecturedExample` and `ProjecturedTest` declare no dependency on
      `ProjecturedUndo`.** Both reach its names through `using Projectured` and
      `using ProjecturedUndoTest`, and a package that declares what it never
      names fails the graph guard.
- [x] The four rules of U17. R1 is the order of the reader; R2 is the three
      `make_inverse_operation` methods beside the three operation types; R3 and
      R4 are two guards in `_record_operation`. Two nested buffers are tested
      here, not only in step 7.
- [x] `test/undo/UndoBufferTest.jl` with `test_undo()`: **69 assertions, all
      passing.** It covers the bounded history, the filter, a barrier, the
      printer, the two maps, the delegation, an undo, a redo, a delete that
      comes back in the cell it left, the caret that goes back to the edit, two
      nested buffers, and `make_undoable_operation`.
- [x] `example/projectured/UndoDocumentExample.jl` and
      `example/projectured/UndoProjectionExample.jl` — a JSON object inside an
      `UndoBuffer`, and the JSON chain with
      `UndoBuffer => UndoBufferToAnyProjection()` at the top of the dispatcher.
      `undo_example` is in `domain_examples` but out of the `examples` registry,
      for the reason `versioning_example` is: a sweep shares one document, and a
      buffer records what the sweep does. **No other example changes** (U18).
- [x] `documentation/package/undo/undo.md`, the guide of the slice.
- [x] Test: `test_undo()` 69 / 69, from its own environment and from the
      umbrella. `test_printer(undo_example)` 760 / 760 and
      `test_reader(undo_example)` 225 / 225 — the buffer is transparent through
      the whole chain. `test_package_graph()` 616 / 3; the three are the
      pre-existing domain-edge rows of `ProjecturedConversation`,
      `ProjecturedFormula` and `ProjecturedWorkbench`, and no row names an undo
      package.

### Step 5 — the round trip is a property, not an example

- [x] `test/projectured/projection/UndoRoundTripTest.jl` with
      `test_undo_round_trip()`, registered in `ProjecturedSuite.jl`. It runs the
      whole reader battery against `undo_example` — a real JSON document in a
      buffer, through the real chain — and for every gesture that makes a
      recorded change it asserts: apply, take it back, and the document is the
      text it was.
- [x] **It compares text, not the printed output.** The snapshot is a chain that
      ends in `TextToString`. A printed graphics tree carries sizes and
      identities that say nothing about whether the value came back, and a text
      rendering says exactly that and reads well in a failure message.
- [x] **Only the umbrella can hold it.** It needs the example registry, so it is
      an umbrella test beside the other example sweeps, not part of
      `test_undo()`. A gesture with no way back is marked `@test_broken` with the
      label of the step, so a missing inverse is visible rather than silent.

### Step 6 — the buffer survives a move (U13)

**The design changed here, and it is simpler than U13.** U13 proposed a `prefix`
that every reroot extends, stripped on record and re-applied on undo. Writing the
inverses showed a better way: **an inverse names the object it writes into, not a
path from the editor's root.**

The inverse had to resolve the parent anyway, to read the old value.
`ReplaceReferencedValueOperation` already has a carried-root form — the form the
guide says to prefer — so the inverse answers that form. There is no path to go
stale, so nothing has to be stripped or re-applied, and the prefix field, the
three reroot methods it needed and the dual of `reroot_operation` all disappear.

It is also more truthful than a path. A history is taken back newest first, so by
the time an entry is applied every later entry has been applied, and those
restored the very objects this one names.

- [x] Every write inverse carries its root: a field write carries the owner, an
      element overwrite and a splice carry the container.
- [x] The two primitive range operations answer a **whole-field write** on the
      carried owner rather than another range edit. That is what the field held
      before, so it is the same result; it carries its object; and it covers
      every representation a text field can hold — a string, a cleared field, a
      number, a styled span — because it puts the value back rather than
      splicing characters into whatever is there.
- [x] Two exceptions, both named rather than hidden. A **whole-root swap** stays
      rooted at the editor, because that is what it targets. A **restored
      selection** stays a path, because a selection is a path; it is applied
      through a guard, so a caret that no longer fits is dropped and the value
      still comes back.
- [x] Tests: the kernel asserts an inverse applies against an editor that has
      never seen the document; the undo suite asserts a buffer still takes a step
      back from an editor whose document is another tree entirely.

### Step 7 — the application installs the buffers (U17, U18)

- [x] The application buffer: `make_application_document` wraps the window
      content, and `_with_window_history` puts the dispatcher **outermost** —
      outside the gesture help and the command palette, because the document it
      is handed is the buffer and the step it records must be the one the whole
      chain settled on.
- [x] **The focus is seated again after the wrap.** A selection is a chain every
      node on the path holds a piece of, and the content was given its focus
      before the buffer held it, so the buffer would hold none.
- [x] **Two generics, not one, and both in the kernel document layer, not in
      `ProjecturedDomain`.** `ProjecturedWorkbench` does not depend on
      `ProjecturedDomain`, and it is the package that must look through a
      wrapper. `get_wrapped_document(node)` answers the document a node stands
      for; `replace_wrapped_document!(node, document)` puts a new document where
      the old one stood and answers what belongs there now. A reload uses the
      second, and the buffer's method keeps its place and forgets its history.
- [x] The file buffers: `make_workbench_file_editor(path, wrap)` and
      `OpenWorkspaceFileOperation(path; wrap)` take the overlay from the caller,
      so the workbench names no undo type and no workbench example grows a
      history. The application passes `UndoBuffer` to both.
- [x] Four places look through a wrapper: the save and the reload in
      `WorkbenchFile.jl`, `_get_window_content` there, and `get_window_tree` in
      `PaneProgram.jl`, which already had a hand-written method for the
      clipboard and now answers any wrapper.
- [x] **A step whose way back is to do nothing is not recorded.** A save and a
      zoom pass through the buffer and answer `DoNothingOperation()`; an entry
      for one would be a line in the history that undoes nothing.
- [x] `ApplicationTest.jl` says that the application has a history: two helpers,
      `_app_window` and `_app_plain`, and the assertions stay about what they
      were about. The application's own baseline was `test_application()`
      72 / 0 / 0 on clean main, so this is measured, not assumed.
- [x] Test: `test_application()` back to green, `test_undo()` 71 / 71,
      `test_undo_round_trip()` 132 / 132, `test_workbench()` 144 / 3 / 2 and
      `test_substrate()` unchanged. `test_workbench_file_keys()` is 38 / 3 / 2 / 1
      on the branch **and on clean main** — pre-existing, and now baselined.

### Step 8 — the history is a document (U16)

- [ ] `UndoBufferToSyntax`, in the shape of `GestureLogToSyntax`.
- [ ] A click on an entry undoes to there.
- [ ] An example that shows the document and its history side by side.

### Step 9 — the assistant and the tool set (U15)

- [ ] The document-changing tools wrap through `make_undoable_operation`.
- [ ] An `undo` and a `redo` tool.
- [ ] A test that an edit a tool made is undone by `Ctrl+Z`.

### Step 10 — guides, and close

- [ ] [concepts.md](../../documentation/design/concepts.md): "There is no undo
      and no redo" goes; say what there is.
- [ ] [system-anatomy.md](../../documentation/design/system-anatomy.md): the two
      `Undo / redo | ❌` rows.
- [ ] [operation.md](../../documentation/package/kernel/operation.md): the two
      new generics, the wrapper seam, and the rule that a new operation declares
      its inverse.
- [ ] [mcp-guide.md](../../documentation/guide/mcp-guide.md) and
      [own-project-guide.md](../../documentation/guide/own-project-guide.md):
      both say "There is no undo" today.
- [ ] `documentation/package/undo/undo.md`, in the shape of
      `documentation/package/versioning/versioning.md`.
- [ ] [keyboard-and-mouse-guide.md](../../documentation/guide/keyboard-and-mouse-guide.md)
      and the roadmap.
- [ ] `git mv plan/pending/undo-and-redo.md plan/done/`.

## 6. Risks

**A seam is missed.** An operation whose inner reference is not rerooted writes
at the wrong depth, with no error. This is the failure `PAR-REGISTER-NEW-OPERATION`
exists for. Step 1 makes it one seam instead of one case per site, and step 4
tests the buffer inside a workbench, which is the deepest container chain the
repository has.

**An inverse is wrong rather than missing.** A wrong inverse is worse than none:
it writes a state the person never saw. Step 2 tests every base method by round
trip, and step 5 tests the whole set against real gestures.

**Identity is lost on a redo.** A splice inverse that stores values rather than
cells rebuilds the cells on the way back, and every widget that held one is
orphaned. The U3 rule is to capture cells. Step 5 catches a miss, because the
printed output differs.

**A restored selection does not match.** `replace_selection!` throws on a path
the document no longer matches. Every restore is guarded and a miss is ignored.

**The tier of the package is wrong.** U19 puts `ProjecturedUndo` above the
domains, which keeps the plumbing at about ten files. If it later has to move
into the substrate — because a domain wants a buffer of its own — the move costs
about ninety more files, two lines each. It is mechanical and checkable with one
grep, but it is a decision to take now rather than to drift into.

**The application buffer and a file buffer disagree.** R2 rests on every inner
push being matched by an outer push, in the same order. A filter difference
(R4), an edit that reaches one buffer and not the other, or a buffer added while
a history already exists all break it, and an outer undo then takes back the
wrong step. Step 7 tests the two-buffer arrangement directly, and a mismatch
must fail loudly rather than write.

**The reference of an entry is stale.** The parent of the slot was deleted by a
later edit, so `evaluate_reference` throws. Resolve with `try_evaluate_reference`
and turn a miss into a barrier at apply time, so an undo of a history that no
longer fits stops instead of crashing the editor.
