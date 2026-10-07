# Undo

> **Kind:** design · **Status:** current · **Stands on:** [operation.md](../../kernel/operation.md), [projection-system.md](../../kernel/projection-system.md), [versioning.md](../versioning/versioning.md)

The undo slice of `ProjecturedPlatform` gives any document a history. An `UndoBuffer` holds a document and the steps that take it back, and a transparent projection records each operation that passes through it. This document says how a step is recorded while no reader changes anything, how two buffers on one path work together, and what is not recorded.

## How it works

The package has the shape of the clipboard and of versioning: a wrapper document, and a projection whose output is the output of the wrapped document. The difference is on the way back. The projection wraps each operation that it passes up, so applying the operation also records its inverse.

| Part | What it is |
| --- | --- |
| `UndoBuffer` | `content`, the document; `undo_entries`, oldest first; `redo_entries`; `capacity`, 100 by default |
| `UndoEntry` | `label`, a description for a person; `inverse`, the operation that goes back; `selection`, the caret before the step; `typing_caret`, the caret after a typed step, as text; `time`, when the step was made or last grew |
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

`is_undo_step`, the default filter, drops `nothing`, `DoNothingOperation`, a move of the selection or of the part under the pointer (`ReplacePathOperation`, `SelectNextInsertionOperation`), a fold (`ToggleCollapseOperation`), a write marked `ReplaceViewStateOperation`, and a compound of nothing else. A caret move follows almost every key, and a hover follows almost every move of the pointer, so a history full of them is not usable. A compound that holds one write stays. An operation that changes no document, such as a file write or a zoom of the window, has the inverse `DoNothingOperation()`, and no entry is added for it. Undo does not step over a barrier, because that would make a document that matches no state the user saw.

**The reader that reads a gesture decides whether its write is view state.** A field is not view state by its type. When the widget renderer draws a tree, a click on a chevron uses the tree as a control, and the write of `collapsed` is view state; a projection that shows the same tree as data writes `collapsed` as an edit. So the mark is made where the gesture is read:

| Reader | Writes marked as view state |
| --- | --- |
| widgets | `pressed`, `dragging`; a scroll (`scroll_position`, `follow_end`, `tab_scroll`, `transform`); a tree fold (`collapsed`); an accordion section (`expanded`) |
| split pane, pane tree | the grab, each move and the release of a divider; the `drag` of a tab |
| configuring projection | the `visible` of the control bar |
| chart, sequence chart | the zoom window (`view`), the lane offset (`cross_offset`), the pointer (`cursor`), the rubber band (`drag_anchor`, `drag_rect`) |

A fold is dropped by its kind instead: `ToggleCollapseOperation` is the flip of a fold that a reader made of a click on a chevron. `test_history_sweep()` presses the gestures that change no document in the application window and moves the pointer over every example, and it fails when a history grows.

### A run of typing is one step

A history holds `capacity` steps, 100 by default, so a step for each character would push every other step out after 100 characters. A run of typed characters is therefore one step. A `KeyPress` is a character, and a `KeyPress` that makes a recorded step is typing; a key that is not a character arrives as a `KeyDown`.

The reader decides when it reads the step, and `RecordUndoOperation` carries the answer in `run`: `:none`, `:starts` or `:continues`. A run is open while its last step is typing and has a way back, nothing was taken back since, the caret of the buffer is where the run left it (`typing_caret`), and less than `TYPING_PAUSE`, one second, passed. So a caret move, a key that is not a character, an undo and a pause each end a run. A step that joins the run keeps the caret from before the first character, and its way back takes back the newest character first.

A buffer above a buffer keeps a copy of each step below. A run joins in both or in neither: the copy of a run is taken back by one undo of the buffer below, which joined its own run too. When the outer buffer recorded a step of its own since, such as a tab that opens, its reader turns `:continues` into `:starts`, and the next character begins a new run in both. A typed character with no way back makes the joined run a barrier, so the two buffers keep the same number of steps.

### The reader wraps and never records

`PAR-READER-IS-PURE` in [architecture-invariants.md](../../../rule/architecture-invariants.md) forbids a reader to change anything. So the reader returns `RecordUndoOperation(buffer, operation)`, and its `evaluate_operation` takes the label and the caret, applies the operation through `evaluate_invertible_operation!` and pushes the entry. A new entry empties `redo_entries` and drops the oldest entry above `capacity`.

`RecordUndoOperation` is a `WrappingOperation`: `get_wrapped_operation` and `rewrap_operation` reach the operation inside it. Every seam that maps a `CompoundOperation` member by member uses these two, so the wrapper needs no special case anywhere. `UndoOperation` and `RedoOperation` hold the buffer itself, so `is_self_contained_operation` is `true` for both and they need no rerooting.

**The reader reads the content first and its own keys last.** It gives the gesture to the content, reroots the returned operation under `content` and wraps it. Only when the content returns no operation does the reader try Ctrl+Z and the redo keys. The source gives the reason: with a buffer inside a buffer, the inner one must take the key. The reader of `VersioningToAnyProjection` uses the opposite order on purpose; see [versioning.md](../versioning/versioning.md).

### One buffer, or one for each document

A buffer is a document node, so a buffer can hold a buffer, and both arrangements work at the same time:

- A buffer around the **window** records everything. A splitter move, a new tab and a chat draft are edits too, and no buffer of a document sees them.
- A buffer around **each file** gives Ctrl+Z its usual meaning: an undo in one file does not take back an edit in another.

Four rules make the two work together, and a run of typing keeps them (see above):

1. **The innermost buffer takes the key**, because the reader reads the content first.
2. **Undo and redo are the inverses of each other.** The inverse of a `RecordUndoOperation` is an `UndoOperation` of that buffer. The inverse of an undo is a redo, and the inverse of a redo is an undo. So an outer buffer takes back an inner step with an `UndoOperation` of the inner buffer. The outer buffer does not repeat the recording of the inner one, and the two lists of the inner buffer stay correct.
3. **A buffer never records its own undo or redo.** It records the undo of another buffer.
4. **An outer buffer does not apply its filter again** to a step that an inner buffer recorded. Two levels that disagree lose the order that they share, and that order is what lets an outer entry name an inner step.

### The history of an opened file

`make_history_wrap(settings)` puts a document into a buffer whose capacity is the cell of `undo_capacity` of `HistorySettings`. When the editor has settings, the evaluation of the open of a file gives the file such a history, whatever started the open (the Files pane, the menu Open, a link): around the part that the opener puts around the file document, such as a navigator, so the buffer records every edit of that part, and else around the content inside the file, as a file tab of the application has it.

### The keys

| Key | What it does |
| --- | --- |
| Ctrl+Z | take the last step back |
| Ctrl+Y, Ctrl+Shift+Z | put the last step back |

A key with an empty list returns `nothing`, so the key goes on to the next reader. After a step, the caret goes back to the place saved in the entry. A saved path that no longer matches the document is ignored.

### What is not recorded

- An operation that the editor makes itself, such as the zoom or the quit. The editor makes it after the chain returns nothing for the gesture, so no buffer sees it.
- A popup that a widget opens. Its opener marks the `OpenPopupOperation` with `ReplaceViewStateOperation`, so `is_undo_step` drops it, as it drops a hover.
- An operation from `post_operation!`. The inbox goes directly to `evaluate_operation`, so a driver that runs a simulation does not fill the history of the person who edits beside it.
- An edit outside the buffer.
- Code that a model runs through `execute_julia_code`. It changes the document as any code does.

A tool, a driver or a script that must record its change wraps it with `make_undoable_operation(buffer, operation)`.

### The history drawn

`UndoBufferToSyntax` prints the buffer itself, not its content: one line for each step, with the newest at the top and a marker line where the document stands now. The lines above the marker can be put back, and the lines below it can be taken back. A barrier line says `stop` in its own colour. The lines come from a computed `CellVector` that reads both lists, so the panel changes with each step. The font is DejaVu Sans Mono, which has a glyph for the empty reference, so the columns stay aligned.

### A model takes a change back

`register_undo_tools!(set)` adds an `undo` and a `redo` tool. Each one finds the buffer with `find_undo_buffer` on the document of the editor, runs the step and returns a sentence about what it did. `find_undo_buffer` returns the **outermost** buffer: an outer buffer records every step of the buffers below it, so one step back there takes back the last change anywhere below. The kernel tool set does not hold these tools; the application adds them in `start_application!`.

### The `undo` wrapper of `build_editor`

`undo = true` is the wrapper of `build_editor` that gives a window an undo of its own. It puts the root document, such as the pane tree that the `tabs` wrapper makes, in an `UndoBuffer`, drawn with `UndoBufferToAnyProjection`, so Ctrl+Z takes back a change that belongs to no file: a splitter that moves, a tab that opens or closes, a draft. It is off by default. It acts in the layer `:container` with the number 5, next to the tabs and inside the chrome of the `shell` wrapper. A root that is a buffer already keeps it, and the buffer holds the selection that the root held, rooted at the buffer.

### The theme

`UndoTheme` holds the text of the index, a step, a step ahead, the marker of the present place, a barrier, and an empty history. Each value has the default that the slice draws with no
appearance. `UndoBufferToSyntax` holds its styles and no theme. `make_undo_projection(; theme)`
fills them with `get_undo_style`, from an `UndoTheme` scaled or not, or the default values for
`nothing`. The history has no view in the application, so a builder that has a theme calls it.

## How it fits

The undo slice depends on the kernel, the collection slice for the two lists, the projection slice, and the syntax, text, graphics and style slices for the history panel. It rests on one kernel seam, `source/kernel/operation/Inversion.jl`, which holds `make_inverse_operation` and `evaluate_invertible_operation!`. No other slice depends on it; an application puts a buffer into its document and a `UndoBuffer => UndoBufferToAnyProjection()` row into its dispatch table.

It registers nothing at load time. The keys are a `get_projection_gesture_bindings` table of the projection, and the tools are added only by a program that calls `register_undo_tools!`.

## Design decisions

- **A history is a document node, not a field of the editor.** A window can then have one history and each file another. See [plan/done/undo-and-redo.md](../../../../plan/done/undo-and-redo.md).
- **The evaluation records, the reader does not.** A reader that changes state is invisible to undo, playback and scripting, so recording is an operation.
- **The inverse is taken before the change.** It must read the state that the change starts from, and a compound is inverted member by member for the same reason.
- **A barrier stops the history.** Stepping over a step that has no inverse would make a state that never existed.
- **An outer buffer undoes through the inner one.** The chain of inverses from record to undo to redo lets a buffer record another buffer without a special case.
- **The reader that reads a gesture marks view state.** A field can be view state under one projection and content under another, so no list of fields exists. See [plan/done/the-history-records-edits-and-not-view-state.md](../../../../plan/done/the-history-records-edits-and-not-view-state.md).
- **A run of typing is one step, in each buffer on the path.** Otherwise typing pushes every other step out, and an outer copy would no longer name exactly one inner step.
- **The inner buffer takes the key first.** This is the reverse of the reader order of versioning, and the comment at the head of `source/platform/undo/UndoBufferToAny.jl` says so.

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
- Tests: `test_undo()` in `test/platform/undo/UndoSuite.jl` runs the layering guard and `test_undo_buffer()`. Its documents are declared in the suite and the content projection is the identity, so no domain is needed. `test_undo_round_trip()` in `test/projectured/projection/UndoRoundTripTest.jl` edits `undo_example` at sampled carets and undoes each edit. `test_history_sweep()` in `test/projectured/editor/HistorySweepTest.jl` asserts that a gesture that changes no document adds no step, and that a run of 150 typed characters is one step in the file and in the window.

## Limits

- `test_undo_round_trip()` marks `@test_broken` each sampled gesture whose operation has no inverse, and logs the gesture. Such a step becomes a barrier.
- A buffer records only the edits that pass through its own reader. A navigator prints its page directly, so an edit on a page below the root of the content of a navigator bypasses a buffer inside that content, as in the tab that "Open in a new tab" makes from a file tab. A history that records every edit of its document from any view is the plan [a-history-records-every-edit-of-its-document.md](../../../../plan/pending/a-history-records-every-edit-of-its-document.md).
- The history panel is read-only. A click on a line would need a reference map through three stages and an operation that takes several steps back at once; neither exists.
