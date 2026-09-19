# Undo slice

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

A domain-neutral overlay that gives **any** document a history. An `UndoBuffer`
holds another document and the steps that take it back, and a transparent
projection makes the buffer invisible and records what passes through it.

It is the same wrapper-plus-elimination shape the clipboard and the versioning
slice use: a document that holds a payload, and a projection that answers the
payload's own output and re-roots edits back into it. What this one adds is on
the way back — every operation it forwards is wrapped, so applying it also
records the way back.

## What it is made of

| Where | What |
| --- | --- |
| [`source/undo/UndoDocument.jl`](../../../source/undo/UndoDocument.jl) | `UndoBuffer`, `UndoEntry`, the three operations, `is_undo_step` |
| [`source/undo/UndoBufferToAny.jl`](../../../source/undo/UndoBufferToAny.jl) | `UndoBufferToAnyProjection`: the printer, the two reference maps, the reader, the gestures |
| [`source/undo/UndoBufferToSyntax.jl`](../../../source/undo/UndoBufferToSyntax.jl) | `UndoBufferToSyntax`: the history drawn for a person to read |
| [`source/kernel/operation/Inversion.jl`](../../../source/kernel/operation/Inversion.jl) | `make_inverse_operation` and `evaluate_invertible_operation!`, the kernel seams this slice rests on |

## The way back is an operation

`make_inverse_operation(document, operation)` answers the operation that takes
`document` back, or `nothing` when there is none. It is an open generic beside
`reroot_operation`: the kernel answers for the operations it owns, and every
package declares the inverses of its own operations beside their declarations.

Two rules follow from what an inverse is.

**It is taken before the change is applied**, because it reads the state the
change starts from. A field write keeps the value the field holds now; a splice
of `[start, stop)` with `n` items keeps the slots that are there now and answers
a splice of `[start, start + n)` with them.

**A container is inverted while it is applied.** The inverse of the second
member of a `CompoundOperation` depends on what the first member did, so
`evaluate_invertible_operation!` interleaves the two rather than inverting the
whole compound up front. Two deletes of the same index are the smallest case
that shows it.

An inverse captures the **slot**, not the value: `get_slot_at` answers the cell
of a reactive collection, so an element that comes back is the object it was and
whatever followed its cell follows it still.

## Three answers, three mechanisms

They are different questions, and each has one mechanism.

| Question | Mechanism |
| --- | --- |
| Does this step belong in a history at all? | the `filter` of the projection, at read time |
| Can this step be taken back? | `make_inverse_operation`, at evaluate time |
| What happens when it can not? | a **barrier** entry, which undo does not cross |

`is_undo_step` is the default filter. It drops the operations that change
nothing and the bare selection moves, because a caret move follows almost every
key and a history full of them is one a person can not use.

An operation that changes no document — a file that is written, a zoom — answers
`DoNothingOperation()`, so a history steps over it. An operation nobody taught to
invert answers `nothing`, and the entry becomes a barrier. Stepping over a
barrier would build a document that matches no state the person ever saw.

## The reader wraps; it never records

`PAR-READER-IS-PURE` forbids a reader to change anything, and its own text names
undo as a mechanism a mutating reader would break. So the reader answers a
`RecordUndoOperation`, and `evaluate_operation` is what takes the inverse,
applies the change and pushes the entry.

`RecordUndoOperation` is a `WrappingOperation`: it holds one operation and
answers `get_wrapped_operation` and `rewrap_operation`. Every seam that maps a
`CompoundOperation` member by member reaches what a wrapper holds through those
two, so a wrapper needs no branch of its own anywhere. See
[operation.md](../kernel/operation.md).

## One buffer, or one per document

Both, and the mechanism composes them, because a buffer is a document node and a
buffer can hold a buffer.

- A buffer around a **window** is the floor: a splitter move, a tab that opens
  and a chat draft are edits too, and no per-document buffer sees them.
- A buffer around **each file** is what `Ctrl+Z` means to a person: an undo in
  one file must not take back an edit in another.

Four rules make the two work together.

1. **The innermost buffer answers the gesture.** The reader delegates into the
   content first and fires its own bindings last.
2. **Undo and redo are each other's inverses.** The way back from "this buffer
   recorded a step" is that buffer's undo, and the way back from an undo is a
   redo. So an outer buffer never repeats an inner buffer's work: it asks, and
   the inner buffer's own two lists stay right.
3. **A buffer never records its own undo or redo.** It records another
   buffer's.
4. **An outer buffer does not re-decide the filter** for a step an inner buffer
   already recorded. Two levels that disagree lose the order they share, and
   that order is what lets an outer entry name an inner step.

## The keys

| Gesture | What it does |
| --- | --- |
| `Ctrl+Z` | take the last change back |
| `Ctrl+Y`, `Ctrl+Shift+Z` | put it back |

A key with nothing to do answers `nothing` and falls through, so it is not
swallowed.

## What is not recorded

- The operations the editor makes itself — the zoom, the quit. They are made
  after the pipeline declines the gesture, so they never reach a buffer.
- An operation from `post_operation!`. The inbox goes straight to
  `evaluate_operation`, so a driver advancing a simulation does not fill the
  history of the person editing beside it.
- An edit outside the buffer. A buffer records what passes through it, which is
  the point of its being a node.

A tool or a driver that **wants** its change recorded wraps it with
`make_undoable_operation(buffer, operation)`.

## The history drawn

`UndoBufferToSyntax` draws the buffer itself rather than the document it holds:
one line per step, newest at the top, with a marker line for where the document
stands now. What is above the marker can be put back, what is below it can be
taken back, and a barrier says `stop`.

It is read-only, as the gesture log's panel is. A click on an entry would need a
reference map through three stages and an operation that takes several steps back
at once; neither exists yet.

## A model takes a change back

`register_undo_tools!(set)` adds an `undo` and a `redo` tool. Each finds the
buffer with `find_undo_buffer` on the document of the editor it is called
against, and answers what it took back or says there was nothing to take back.

`find_undo_buffer` answers the **outermost** buffer, because a buffer above
another records every step the one below it records: one step back there takes
back the last thing that happened anywhere under it.

The kernel's own tool list does not hold these. It has no reference to a history,
and a program that needs one adds it — the application does it in
`_start_application!`.

Code a model runs through `execute_julia_code` records nothing by itself. It
changes the document the way any code does, and it enters a history only if it
wraps its operation with `make_undoable_operation`.

## Where to see it

- The examples: `undo_example` is the document with a history behind it, and
  `undo_history_example` is the history itself, drawn. Built from
  [`UndoDocumentExample.jl`](../../../example/projectured/UndoDocumentExample.jl)
  and [`UndoProjectionExample.jl`](../../../example/projectured/UndoProjectionExample.jl).
- The suite: `test_undo()`, in
  [`test/undo/UndoBufferTest.jl`](../../../test/undo/UndoBufferTest.jl). It holds
  no domain — the documents are declared in the suite and the content projection
  is the identity — so the slice is tested on its own.
