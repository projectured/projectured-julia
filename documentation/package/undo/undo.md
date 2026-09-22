# Undo

> **Kind:** design · **Status:** current · **Stands on:** [operation.md](../kernel/operation.md), [projection-system.md](../kernel/projection-system.md), [versioning.md](../versioning/versioning.md)

`ProjecturedUndo` gives any document a history. An `UndoBuffer` holds a document and the steps that take it back, and a transparent projection records each operation that passes through it. This document says how a step is recorded while no reader changes anything, how two buffers on one path work together, and what is not recorded.

## How it works

The package has the shape of the clipboard and of versioning: a wrapper document, and a projection whose output is the output of the wrapped document. The difference is on the way back. The projection wraps each operation that it passes up, so applying the operation also records its inverse.

| Part | What it is |
| --- | --- |
| `UndoBuffer` | `content`, the document; `undo_entries`, oldest first; `redo_entries`; `capacity`, 100 by default |
| `UndoEntry` | `label`, a description for a person; `inverse`, the operation that goes back; `selection`, the caret before the step |
| `UndoBufferToAnyProjection(; filter)` | the transparent projection, its reader and its keys |
| `UndoBufferToSyntax` | the history itself, drawn as lines |

An `UndoEntry` is a plain struct with no cell. The buffer is the document, and an entry is a value that it holds. `get_wrapped_document(buffer)` returns the content, so a save writes the document and not the buffer. `replace_wrapped_document!` puts in a new document and clears both lists, because the steps of the old document do not apply to the new one.

### The way back is an operation

`make_inverse_operation(document, operation)` of the kernel returns the operation that takes `document` back, or `nothing` when none exists. Each package declares the inverses of its own operations beside them; [primitive.md](../primitive/primitive.md) shows the inverse of a range edit. Two rules follow:

- **The inverse is taken before the change is applied**, because it reads the state that the change starts from. A field write keeps the current value. A splice of `[start, stop)` with `n` items keeps the current slots and returns a splice of `[start, start + n)` with them.
- **A compound is inverted while it is applied.** The inverse of the second member of a `CompoundOperation` depends on what the first member did, so `evaluate_invertible_operation!` applies and inverts one member at a time. Two deletes of the same index are the smallest case that shows it.

An inverse keeps the slot, not only the value. `get_slot_at` returns the cell of a reactive collection, so an element that comes back is the same object, and whatever followed its cell follows it again; see [collection.md](../collection/collection.md).

Three questions have three separate mechanisms:

| Question | Mechanism |
| --- | --- |
| Does this step belong in the history? | the `filter` of the projection, when the reader runs |
| Can this step be taken back? | `make_inverse_operation`, when the operation is evaluated |
| What happens when it can not? | a **barrier** entry, whose `inverse` is `nothing`; undo stops at it |

`is_undo_step`, the default filter, drops `nothing`, `DoNothingOperation` and a bare `ReplaceSelectionOperation`. A caret move follows almost every key, and a history full of them is not usable. A compound that holds a write stays. An operation that changes no document, such as a file write or a zoom, has the inverse `DoNothingOperation()`, and no entry is added for it. Undo does not step over a barrier, because that would make a document that matches no state the user saw.

### The reader wraps and never records

`PAR-READER-IS-PURE` in [architecture-invariants.md](../../rule/architecture-invariants.md) forbids a reader to change anything. So the reader returns `RecordUndoOperation(buffer, operation)`, and its `evaluate_operation` takes the label and the caret, applies the operation through `evaluate_invertible_operation!` and pushes the entry. A new entry empties `redo_entries` and drops the oldest entry above `capacity`.

`RecordUndoOperation` is a `WrappingOperation`: `get_wrapped_operation` and `rewrap_operation` reach the operation inside it. Every seam that maps a `CompoundOperation` member by member uses these two, so the wrapper needs no special case anywhere. `UndoOperation` and `RedoOperation` hold the buffer itself, so `operation_travels_unchanged` is `true` for both and they need no rerooting.

**The reader reads the content first and its own keys last.** It gives the gesture to the content, reroots the returned operation under `content` and wraps it. Only when the content returns no operation does the reader try Ctrl+Z and the redo keys. The source gives the reason: with a buffer inside a buffer, the inner one must take the key. The reader of `VersioningToAnyProjection` uses the opposite order on purpose; see [versioning.md](../versioning/versioning.md).

### One buffer, or one for each document

A buffer is a document node, so a buffer can hold a buffer, and both arrangements work at the same time:

- A buffer around the **window** records everything. A splitter move, a new tab and a chat draft are edits too, and no buffer of a document sees them.
- A buffer around **each file** gives Ctrl+Z its usual meaning: an undo in one file does not take back an edit in another.

Four rules make the two work together:

1. **The innermost buffer takes the key**, because the reader reads the content first.
2. **Undo and redo are the inverses of each other.** The inverse of a `RecordUndoOperation` is an `UndoOperation` of that buffer. The inverse of an undo is a redo, and the inverse of a redo is an undo. So an outer buffer takes back an inner step with an `UndoOperation` of the inner buffer. The outer buffer does not repeat the recording of the inner one, and the two lists of the inner buffer stay correct.
3. **A buffer never records its own undo or redo.** It records the undo of another buffer.
4. **An outer buffer does not apply its filter again** to a step that an inner buffer recorded. Two levels that disagree lose the order that they share, and that order is what lets an outer entry name an inner step.

### The keys

| Key | What it does |
| --- | --- |
| Ctrl+Z | take the last step back |
| Ctrl+Y, Ctrl+Shift+Z | put the last step back |

A key with an empty list returns `nothing`, so the key goes on to the next reader. After a step, the caret goes back to the place saved in the entry. A saved path that no longer matches the document is ignored.

### What is not recorded

- An operation that the editor makes itself, such as the zoom or the quit. The editor makes it after the chain returns nothing for the gesture, so no buffer sees it.
- An operation from `post_operation!`. The inbox goes directly to `evaluate_operation`, so a driver that runs a simulation does not fill the history of the person who edits beside it.
- An edit outside the buffer.
- Code that a model runs through `execute_julia_code`. It changes the document as any code does.

A tool, a driver or a script that must record its change wraps it with `make_undoable_operation(buffer, operation)`.

### The history drawn

`UndoBufferToSyntax` prints the buffer itself, not its content: one line for each step, with the newest at the top and a marker line where the document stands now. The lines above the marker can be put back, and the lines below it can be taken back. A barrier line says `stop` in its own colour. The lines come from a `ComputedCellVector` that reads both lists, so the panel changes with each step. The font is DejaVu Sans Mono, which has a glyph for the empty reference, so the columns stay aligned.

### A model takes a change back

`register_undo_tools!(set)` adds an `undo` and a `redo` tool. Each one finds the buffer with `find_undo_buffer` on the document of the editor, runs the step and returns a sentence about what it did. `find_undo_buffer` returns the **outermost** buffer: an outer buffer records every step of the buffers below it, so one step back there takes back the last change anywhere below. The kernel tool set does not hold these tools; the application adds them in `_start_application!`.

## How it fits

`ProjecturedUndo` depends on the kernel, `ProjecturedCollection` for the two lists, `ProjecturedProjection`, and `ProjecturedSyntax`, `ProjecturedText`, `ProjecturedGraphics` and `ProjecturedStyle` for the history panel. It rests on one kernel seam, `source/kernel/operation/Inversion.jl`, which holds `make_inverse_operation` and `evaluate_invertible_operation!`. No other package depends on it; an application puts a buffer into its document and a `UndoBuffer => UndoBufferToAnyProjection()` row into its dispatch table.

It registers nothing at load time. The keys are a `get_projection_gesture_bindings` table of the projection, and the tools are added only by a program that calls `register_undo_tools!`.

## Design decisions

- **A history is a document node, not a field of the editor.** A window can then have one history and each file another. See `plan/done/undo-and-redo.md`.
- **The evaluation records, the reader does not.** A reader that changes state is invisible to undo, playback and scripting, so recording is an operation.
- **The inverse is taken before the change.** It must read the state that the change starts from, and a compound is inverted member by member for the same reason.
- **A barrier stops the history.** Stepping over a step that has no inverse would make a state that never existed.
- **An outer buffer undoes through the inner one.** The chain of inverses from record to undo to redo lets a buffer record another buffer without a special case.
- **The inner buffer takes the key first.** This is the reverse of the reader order of versioning, and the comment at the head of `source/undo/UndoBufferToAny.jl` says so.

## Usage

```julia
buffer     = UndoBuffer(read_document_file("data.json"); capacity = 200)
projection = TypeDispatchingProjection(UndoBuffer => UndoBufferToAnyProjection(),
                                       JsonObject => JsonObjectToSyntaxNode())
every_move = UndoBufferToAnyProjection(filter = (gesture, operation) -> operation !== nothing)
find_undo_buffer(editor.document)
make_undoable_operation(buffer, operation)          # record a change made outside the readers
register_undo_tools!(editor.tools)
```

- Examples: `undo_example`, a JSON document with a history behind it, and `undo_history_example`, the history drawn. The factories are in `example/projectured/UndoDocumentExample.jl` and `UndoProjectionExample.jl`. Both examples are outside the `examples` registry, because a sweep would leave a history for the next test.
- Tests: `test_undo()` in `test/undo/UndoSuite.jl` runs the layering guard and `test_undo_buffer()`. Its documents are declared in the suite and the content projection is the identity, so no domain is needed. `test_undo_round_trip()` in `test/projectured/projection/UndoRoundTripTest.jl` edits `undo_example` at sampled carets and undoes each edit.

## Limits

- `test_undo_round_trip()` marks `@test_broken` each sampled gesture whose operation has no inverse, and logs the gesture. Such a step becomes a barrier.
- The history panel is read-only. A click on a line would need a reference map through three stages and an operation that takes several steps back at once; neither exists.
