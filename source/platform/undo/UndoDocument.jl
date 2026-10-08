# Fragment of `UndoModule` — the buffer, one entry of its history, the three
# operations that fill and walk it, and the filter that decides what enters.

abstract type UndoDocument <: Document end

# ── One step of the history ──────────────────────────────────────────────────

"""
    UndoEntry(label, inverse, selection[, typing_caret, time])

One step that can be taken back.

- `label` — what the step did, in words, for a person reading the history.
- `inverse` — the operation that takes it back, or `nothing` for a **barrier**:
  a step whose way back nobody could work out. Undo stops at a barrier rather
  than stepping over it, because stepping over it would build a document that
  matches no state the person ever saw.
- `selection` — where the caret was before the step, or `nothing`. It is put
  back after the inverse runs, so undo returns the caret to the edit as well as
  the value.
- `typing_caret` — for a step of typing, the caret of the buffer after the step,
  written as text; `nothing` for any other step. A typed character that finds the
  caret still there joins the step (see `RecordUndoOperation`).
- `time` — when the step was made or last joined, in seconds of `time()`.

An entry is a plain value and holds no cell: the buffer that keeps entries is
the document, and an entry is one of the things it holds.
"""
struct UndoEntry
    label::String
    inverse::Any
    selection::Any
    typing_caret::Union{Nothing,String}
    time::Float64
end

UndoEntry(label, inverse, selection) = UndoEntry(label, inverse, selection, nothing, 0.0)

"""
    is_undo_barrier(entry) -> Bool

Whether the history stops at this entry.
"""
is_undo_barrier(entry::UndoEntry) = entry.inverse === nothing

# ── The buffer ───────────────────────────────────────────────────────────────

"""
    UndoBuffer(content; capacity = 100, selection = nothing)

A document that holds another document and the steps that take it back.

Use it to give a document a history. Put one around a whole window and every
edit in the program can be taken back; put one around each file and `Ctrl+Z`
takes back an edit in the file the person is looking at, which is what a person
means by it. Both at once is the supported arrangement, and the buffer closest
to the focus answers first.

`content` is the document whose edits it records. `undo_entries` holds the steps
that can be taken back, oldest first, and `redo_entries` the steps that were
taken back and can be put back. `capacity` bounds the first list; the oldest
entry is dropped when a new one does not fit. It is a number, or the cell of a
setting, such as `undo_capacity` of `HistorySettings`, which the buffer reads at
each step.

The buffer records nothing by itself. `UndoBufferToAnyProjection` is what wraps
the operations that pass through it.

# Example

    buffer = UndoBuffer(read_document_file("data.json"))

See also `UndoBufferToAnyProjection`, `UndoEntry` and `make_inverse_operation`.
"""
@document struct UndoBuffer <: UndoDocument
    content::Document
    undo_entries::CellVector
    redo_entries::CellVector
    capacity::Int
end

UndoBuffer(content::Document; capacity::Union{Integer, AbstractCell} = 100,
           selection = nothing) =
    UndoBuffer(content, CellVector(), CellVector(),
               capacity isa AbstractCell ? capacity : Int(capacity), selection)

# A buffer is transparent on the screen, and a real node in the tree. Anything
# that reads the tree rather than the picture — saving a file is the case — asks
# for the document it stands for and gets what it holds.
get_wrapped_document(buffer::UndoBuffer) = get_wrapped_document(buffer.content)

# A person edits the document that a history keeps the steps of.
get_edited_field(::UndoBuffer) = :content

# A tab that holds a history is called after the document in it.
get_document_title(buffer::UndoBuffer) = get_document_title(buffer.content)

# A buffer survives its document being replaced, and forgets its history: the
# steps of the old document say nothing about the new one.
function replace_wrapped_document!(buffer::UndoBuffer, document)
    buffer.content = document
    clear_undo_history!(buffer)
    buffer
end

"""
    push_undo_entry!(buffer, entry) -> buffer

Put one step on the history, and forget what could be put back.

An ordinary edit makes what was taken back unreachable: the document has moved
past it. The oldest entry is dropped when the history is at its capacity.
"""
function push_undo_entry!(buffer::UndoBuffer, entry::UndoEntry)
    push!(buffer.undo_entries, entry)
    _empty_entries!(buffer.redo_entries)
    _trim_entries!(buffer.undo_entries, buffer.capacity)
    buffer
end

"""
    clear_undo_history!(buffer) -> buffer

Forget every step, in both directions.

Call it when the document is replaced rather than edited — a file re-read from
disk, say — because the steps of the old document say nothing about the new one.
"""
function clear_undo_history!(buffer::UndoBuffer)
    _empty_entries!(buffer.undo_entries)
    _empty_entries!(buffer.redo_entries)
    buffer
end

# Deleting from the front, one at a time, is how the gesture log bounds its own
# buffer: a `CellVector` write is what the readers of the collection follow.
function _empty_entries!(entries)
    while length(entries) > 0
        deleteat!(entries, 1)
    end
    entries
end

function _trim_entries!(entries, capacity::Integer)
    while length(entries) > capacity
        deleteat!(entries, 1)
    end
    entries
end

"""
    is_undo_step(gesture, operation) -> Bool

Whether this operation belongs in a history: the filter a buffer uses when
nobody names another one.

It drops the operations that change nothing, the selection moves, the moves of
the part under the pointer, the folds, the writes of view state and the timers. A caret move follows almost every key and almost every
click, and a history full of caret moves is one a person can not use. A hover or
a held button is marked as view state by the reader that writes it, and is no
edit at all. A `ToggleCollapseOperation` is the flip of a fold that a reader made
of a click on a chevron, so it is view state by its kind. A compound that carries
a write is kept; a compound of nothing but these is dropped.

Pass `(gesture, operation) -> operation !== nothing` to a buffer to record the
caret moves as well.
"""
is_undo_step(gesture, operation) = !(operation === nothing || _is_no_edit(operation))

# An operation that edits no document: one that does nothing, a move of the
# selection or of the part under the pointer, a fold, a write of view state, a
# timer, and a compound of nothing else. A compound that holds one real write is
# an edit.
_is_no_edit(operation) =
    operation isa Union{DoNothingOperation, ReplacePathOperation,
                        SelectNextInsertionOperation, ToggleCollapseOperation,
                        ReplaceViewStateOperation, SetTimerOperation} ||
    (operation isa CompoundOperation && !isempty(operation.operations) &&
     all(_is_no_edit, operation.operations))

# ── The three operations ─────────────────────────────────────────────────────

"""
    RecordUndoOperation(buffer, operation[, run])

Apply `operation` and put the way back on `buffer`.

It is what the projection of a buffer answers in place of the operation the
reader below it made. The recording is an operation and not something the reader
does itself, because a reader never changes anything: it names the change and
the editor applies it.

The way back is taken **before** the change is applied, because an inverse reads
the state the change starts from. A change nobody could invert becomes a barrier
entry, so the history stops there instead of lying about it.

`run` says whether the step is typing. A run of typed characters is one step, so
a history of a hundred steps is not filled by a hundred characters:

- `:none` — any other step;
- `:starts` — a typed character that begins a run;
- `:continues` — a typed character that joins the run of the last step.

A caret move, a key that is not a character and a pause of `TYPING_PAUSE`
seconds end a run. The projection of a buffer decides it when it reads the
step; see `UndoBufferToAnyProjection`.
"""
struct RecordUndoOperation <: WrappingOperation
    buffer::UndoBuffer
    operation::Any
    run::Symbol
end

RecordUndoOperation(buffer::UndoBuffer, operation) = RecordUndoOperation(buffer, operation, :none)

get_wrapped_operation(op::RecordUndoOperation) = op.operation
rewrap_operation(op::RecordUndoOperation, inner) = RecordUndoOperation(op.buffer, inner, op.run)

"""
    TYPING_PAUSE

The seconds without a typed character that end a run of typing, so that the next
character begins a step of its own.
"""
const TYPING_PAUSE = 1.0

"""
    UndoOperation(buffer)

Take back the last step of `buffer`, and put it on what can be redone.

It carries the buffer itself, so it travels up the reader chain unchanged and
needs no rerooting.
"""
struct UndoOperation <: Operation
    buffer::UndoBuffer
end

"""
    RedoOperation(buffer)

Put back the last step that `UndoOperation` took back.
"""
struct RedoOperation <: Operation
    buffer::UndoBuffer
end

is_self_contained_operation(::UndoOperation) = true
is_self_contained_operation(::RedoOperation) = true

"""
    make_undoable_operation(buffer, operation) -> operation

`operation`, recorded on `buffer` when it runs.

Use it to put a change into a history from outside the reader chain: a tool that
a model calls, a driver that posts its work, a script. A reader needs it only
through the projection, which wraps what it reads.
"""
make_undoable_operation(buffer::UndoBuffer, operation) =
    operation === nothing ? nothing : RecordUndoOperation(buffer, operation)

# ── What the three do ────────────────────────────────────────────────────────

function evaluate_operation(editor, op::RecordUndoOperation)
    label = describe_operation(op.operation)
    before = copy_reference(get_selection(editor.document))
    inverse = evaluate_invertible_operation!(editor, op.operation)
    # A step whose way back is to do nothing changed no document — a file that was
    # written, a zoom. It is not a step, so the history does not grow for it.
    inverse isa DoNothingOperation && return nothing
    caret = op.run === :none ? nothing : get_typing_caret(op.buffer)
    buffer = op.buffer
    if op.run === :continues && _is_joinable(buffer)
        # The run grows: its way back takes back this character first, and it keeps
        # the caret from before its first character. A character with no way back
        # makes the whole run a barrier, so a buffer above, whose copy joins too,
        # keeps one step for it as well.
        last = buffer.undo_entries[end]
        joined = inverse === nothing ? nothing : _join_inverses(inverse, last.inverse)
        buffer.undo_entries[end] = UndoEntry(last.label, joined, last.selection, caret, time())
        _empty_entries!(buffer.redo_entries)
    else
        push_undo_entry!(buffer, UndoEntry(label, inverse, before, caret, time()))
    end
    nothing
end

"""
    get_typing_caret(buffer) -> String

The caret of `buffer` as text: what a step of typing keeps, and what the next
typed character is compared with.
"""
get_typing_caret(buffer::UndoBuffer) = repr(strip_reference_types(get_selection(buffer)))

# Whether a step can join the last entry: there is one, and it is not a barrier.
_is_joinable(buffer::UndoBuffer) =
    length(buffer.undo_entries) > 0 && !is_undo_barrier(buffer.undo_entries[end])

# The way back of a run that grows by one step. A copy of an inner buffer's step
# is taken back by one undo of that buffer, which joined its own run too, so the
# copy keeps its way back. Any other run takes back the new step first.
_join_inverses(new::UndoOperation, old::UndoOperation) =
    new.buffer === old.buffer ? old : CompoundOperation(Any[new, old])
_join_inverses(new, old) = CompoundOperation(Any[new, old])

evaluate_operation(editor, op::UndoOperation) =
    _step_undo_history!(editor, op.buffer.undo_entries, op.buffer.redo_entries)

evaluate_operation(editor, op::RedoOperation) =
    _step_undo_history!(editor, op.buffer.redo_entries, op.buffer.undo_entries)

# One step of the history, in either direction. Undo and redo differ only in
# which list a step is taken from and which one it goes to, because the way back
# from a way back is the way there.
#
# The caret is read before anything is applied, so the entry that goes on the
# other list carries the place the reverse step starts from — the same rule the
# entry being applied follows.
function _step_undo_history!(editor, from, to)
    length(from) == 0 && return nothing
    entry = from[end]
    is_undo_barrier(entry) && return nothing
    here = copy_reference(get_selection(editor.document))
    back = evaluate_invertible_operation!(editor, entry.inverse)
    deleteat!(from, length(from))
    push!(to, UndoEntry(entry.label, back, here))
    entry.selection === nothing || _restore_selection!(editor.document, entry.selection)
    nothing
end

# A path that no longer matches the document is not an error here: an undo puts a
# value back, and where the caret lands is a convenience on top of that.
function _restore_selection!(document, path)
    try
        replace_selection!(document, path)
    catch exception
        exception isa SelectionMismatchException || rethrow()
    end
    nothing
end

# ── The way back from the three ──────────────────────────────────────────────
#
# These three methods are what let one buffer hold another. An outer buffer
# records "this inner buffer took one step" and takes that step back by asking
# the inner buffer to undo — so it never repeats the inner buffer's work, and the
# inner buffer's own two lists stay right. An undo a person makes inside is an
# edit like any other, and its way back is a redo.

make_inverse_operation(document, op::RecordUndoOperation) = UndoOperation(op.buffer)
make_inverse_operation(document, op::UndoOperation) = RedoOperation(op.buffer)
make_inverse_operation(document, op::RedoOperation) = UndoOperation(op.buffer)

# ── Reaching a buffer from outside ───────────────────────────────────────────

"""
    find_undo_buffer(document) -> buffer or nothing

The buffer that records everything under `document`: the outermost one, which is
the first `UndoBuffer` of a walk from the root. `nothing` when there is none.

Use it where a caller has the editor's document and no buffer in hand — a tool a
model calls, a script. The outermost buffer is the right one to ask, because a
buffer above another records every step the one below it records, so taking one
step back there takes back the last thing that happened anywhere under it.
"""
function find_undo_buffer(document)
    document isa UndoBuffer && return document
    buffers = search_documents(document, node -> node isa UndoBuffer)
    isempty(buffers) ? nothing : first(buffers)
end

"""
    register_undo_tools!(set) -> set

Add the `undo` and the `redo` tool to `set`.

Each finds the buffer with [`find_undo_buffer`](@ref) on the document of the
editor it is called against, so a model takes a step back the way a person does.
A program that installs no buffer registers no tools: there would be nothing for
them to do.

The kernel's own tool list does not hold these. It knows nothing of a history,
and a program that wants one says so.
"""
function register_undo_tools!(set)
    register_tool!(set, Tool(
        "undo";
        description =
            "Take the last change back. It is the change anyone made — a person, or " *
            "you — and it is taken back exactly as Ctrl+Z takes it back. Answers what " *
            "was taken back, or says that there was nothing to take back.",
        parameters = NamedTuple[],
        handler = (target, args) ->
            _run_undo_tool(target, UndoOperation, :undo_entries, "take back")))
    register_tool!(set, Tool(
        "redo";
        description =
            "Put back the last change that `undo` took back. Answers what was put " *
            "back, or says that there was nothing to put back.",
        parameters = NamedTuple[],
        handler = (target, args) ->
            _run_undo_tool(target, RedoOperation, :redo_entries, "put back")))
    set
end

function _run_undo_tool(target, make, field, verb)
    buffer = find_undo_buffer(getfield(target, :document))
    buffer === nothing && return "This editor keeps no history."
    entries = getproperty(buffer, field)
    length(entries) == 0 && return "There is nothing to $verb."
    entry = entries[end]
    is_undo_barrier(entry) &&
        return "The history stops here: nobody could work out the way back from " *
               entry.label * "."
    evaluate_operation(target, make(buffer))
    "Did $verb: " * entry.label
end
