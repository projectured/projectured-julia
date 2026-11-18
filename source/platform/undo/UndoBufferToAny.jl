# Fragment of `UndoModule` — the projection that makes a buffer invisible and
# records what passes through it.
#
# **Printer** — transparent, the way `VersioningToAnyProjection` is transparent:
# it prints `content` through `print_child` and answers that output, so the
# buffer draws nothing of its own and a buffer can be put around any document
# without changing what the person sees.
#
# **Reader** — it delegates into the content first and wraps what comes back in a
# `RecordUndoOperation`. It fires its own `Ctrl+Z` and `Ctrl+Y` bindings LAST, so
# with two buffers on one path the one closest to the focus answers. That is the
# opposite order to `VersioningToAnyProjection`, on purpose.

"""
    UndoBufferToAnyProjection(; filter = is_undo_step)

Projects an `UndoBuffer`. The output is the projection of the document it holds;
the buffer vanishes.

It projects an `UndoBufferView` in the same way. The output is then the projection
of the view of the document, so the caret stays in the views. A document that has
no view prints as the buffer prints it, at the path `.viewed.content` of the view.
The reader records each edit on the buffer of the view, and it reads the run of
typing at the caret of the view.

`filter(gesture, operation)` decides which operations enter the history. The
default drops the bare selection moves — see `is_undo_step`.

# Example

    TypeDispatchingProjection(UndoBuffer => UndoBufferToAnyProjection(),
                              JsonObject => JsonObjectToSyntaxNode())

See also `UndoBuffer`, `RecordUndoOperation` and `is_undo_step`.
"""
struct UndoBufferToAnyProjection <: Projection
    filter::Any
end

# The filter is a plain field of a plain struct and not a reactive one: a
# `Function` in a reactive field becomes a thunk, and the reader would call it
# with no arguments.
UndoBufferToAnyProjection(; filter = is_undo_step) = UndoBufferToAnyProjection(filter)

@iomap struct UndoBufferToAnyIoMap
    projection::Any
    input::Any           # the UndoBuffer, or the UndoBufferView
    output::Any          # computed: the content's own output
    content_iomap::Any   # computed: the content's child IoMap
end

# The one step from the buffer to what it holds. Every reference that crosses
# this projection gains or loses it, and every operation the content answers is
# rerooted through it.
const _CONTENT_STEPS = (FieldReferenceStep("content"),)

# The steps from the view of a buffer to a document that has no view: the buffer,
# and its document.
const _VIEWED_CONTENT_STEPS = (FieldReferenceStep("viewed"), FieldReferenceStep("content"))

# What the projection prints: a buffer, or the view of a buffer.
const _ShownBuffer = Union{UndoBuffer, UndoBufferView}

_get_buffer(buffer::UndoBuffer) = buffer
_get_buffer(view::UndoBufferView) = view.viewed

# What the input shows: the document of a buffer. A view shows the view of that
# document, or the document when it has no view.
_get_shown_content(buffer::UndoBuffer) = buffer.content
_get_shown_content(view::UndoBufferView) =
    (shown = view.content; shown === nothing ? view.viewed.content : shown)

# The steps from the input to what it shows.
_get_content_steps(::UndoBuffer) = _CONTENT_STEPS
_get_content_steps(view::UndoBufferView) = view.content === nothing ? _VIEWED_CONTENT_STEPS : _CONTENT_STEPS

# The context of the print of `shown`, what `input` shows. A view of a buffer holds
# the place of the view that it shows: the document of that view is in the field
# `content` of the buffer, and the reader writes it there.
function _make_content_context(ctx, input, shown)
    child = make_child_context(ctx, _get_content_steps(input)...)
    (input isa UndoBufferView && shown isa ContentView && shown === input.content) ?
        with_view_place_holder(child) : child
end

# An answer of what `input` shows, in the frame of `input`, as an edit of the content
# when `input` is a view: a write of the node of the view that it shows goes to the
# field `content` of the buffer.
_make_shown_edit(::UndoBuffer, operation) = operation
_make_shown_edit(view::UndoBufferView, operation) =
    operation isa Operation ? make_content_edit(view, operation) : operation

# `reference` without the steps from `input` to what it shows, or `nothing` when it
# does not start with them.
function _drop_content_steps(input, reference)
    for step in _get_content_steps(input)
        reference isa ConcreteReference || return nothing
        head = get_reference_head(reference)
        (head isa FieldReferenceStep && head.name == step.name) || return nothing
        reference = get_reference_tail(reference)
    end
    reference
end

# ── Printer ──────────────────────────────────────────────────────────────────

function print_document(p::UndoBufferToAnyProjection, recursion, input::_ShownBuffer, ctx)
    # The child follows the `content` field by identity: a replacement of the document
    # that the buffer holds (`replace_wrapped_document!`) prints the new document, and
    # the same document keeps its print. The child of a view is the view of that
    # document, which follows the document too.
    child = make_reconciled_child_iomap_cell(
        () -> _get_shown_content(input),
        v -> print_child(recursion, v, _make_content_context(ctx, input, v)))
    UndoBufferToAnyIoMap(p, input, Cell(@computation child[].output), Cell(@computation child[]))
end

# ── Reference mapping ────────────────────────────────────────────────────────
#
# The output is the content's output, so the maps are asymmetric: forward peels
# the one step that reaches the content, backward puts it back.

function map_reference_forward(::UndoBufferToAnyProjection, iomap::UndoBufferToAnyIoMap, reference)
    reference isa ConcreteReference || return reference
    rest = _drop_content_steps(iomap.input, reference)
    rest === nothing && return nothing
    child = iomap.content_iomap
    map_reference_forward(child.projection, child, rest)
end

function map_reference_backward(::UndoBufferToAnyProjection, iomap::UndoBufferToAnyIoMap, reference)
    child = iomap.content_iomap
    mapped = map_reference_backward(child.projection, child, reference)
    mapped === nothing && return nothing
    foldr(ConcreteReference, _get_content_steps(iomap.input); init = mapped)
end

# ── Gestures ─────────────────────────────────────────────────────────────────

"""
    get_projection_gesture_bindings(p::UndoBufferToAnyProjection, iomap)

`Ctrl+Z` takes one step back, `Ctrl+Y` and `Ctrl+Shift+Z` put one back.

A binding answers `nothing` when its list is empty, so a key with nothing to do
falls through instead of being swallowed.
"""
function get_projection_gesture_bindings(p::UndoBufferToAnyProjection, iomap)
    buffer = _get_buffer(iomap.input)
    undo = (document, event, _) -> length(buffer.undo_entries) == 0 ? nothing : UndoOperation(buffer)
    redo = (document, event, _) -> length(buffer.redo_entries) == 0 ? nothing : RedoOperation(buffer)
    GestureBinding[
        GestureBinding(KeyDownPattern(:z; modifiers = [:ctrl]), undo;
                       description = "Undo the last change", domain = "undo", name = "Undo"),
        GestureBinding(KeyDownPattern(:y; modifiers = [:ctrl]), redo;
                       description = "Redo the last change that was undone",
                       domain = "undo", name = "Redo"),
        GestureBinding(KeyDownPattern(:z; modifiers = [:ctrl, :shift]), redo;
                       description = "Redo the last change that was undone",
                       domain = "undo", name = "Redo"),
    ]
end

# ── Reader ───────────────────────────────────────────────────────────────────

# The content reads a change first, and the keys of the buffer answer what the
# content declines: the passing fires the table of the buffer last, so with a buffer
# inside a buffer, the inner one wins. The answer through the view of a buffer is an
# edit of the content (`_make_shown_edit`). The buffer records each operation that
# it answers, except the answer to a collection (`_record_operation`).
function read_intent(p::UndoBufferToAnyProjection, recursion, change::Intent,
                     iomap::UndoBufferToAnyIoMap)
    answer = read_child_intent(p, recursion, change, iomap, iomap.content_iomap,
                               _get_content_steps(iomap.input))
    shown = _make_shown_edit(iomap.input, answer.operation)
    shown === answer.operation ||
        (answer = Intent(answer.gesture, shown, answer.description, answer.domain))
    (change.gesture isa CollectIntents || !(answer.operation isa Operation)) && return answer
    Intent(change.gesture, _record_operation(p, iomap, change.gesture, answer.operation),
           answer.description, answer.domain)
end

# 3-arg payload form, for a test and for a parent that hands a bare payload.
read_intent(p::UndoBufferToAnyProjection, iomap::UndoBufferToAnyIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Whether this buffer records this operation, and how.
function _record_operation(p::UndoBufferToAnyProjection, iomap::UndoBufferToAnyIoMap,
                           gesture, operation)
    buffer = _get_buffer(iomap.input)
    # A step a buffer below already recorded is recorded here whatever this
    # filter says. That buffer decided, and two levels that disagree lose the
    # order they share — which is what lets an outer step name an inner one.
    #
    # A typed character joins a run in both buffers or in neither: this buffer's
    # copy of the run is taken back by one undo of the buffer below. So when this
    # buffer recorded something else since, the character begins a new run below
    # as well.
    if operation isa RecordUndoOperation
        run = operation.run
        (run === :continues && !_is_copy_of_last_step(buffer, operation.buffer)) && (run = :starts)
        inner = run === operation.run ? operation :
                RecordUndoOperation(operation.buffer, operation.operation, run)
        return RecordUndoOperation(buffer, inner, run, iomap.input)
    end
    # A buffer never records its own undo or redo.
    _is_own_history_step(buffer, operation) && return operation
    p.filter(gesture, operation) || return operation
    RecordUndoOperation(buffer, operation, _compute_typing_run(buffer, iomap.input, gesture), iomap.input)
end

# Whether a step is typing, and whether it joins the run of the last step. A
# `KeyPress` of a printable character is typing. Return and Tab, which type a
# character that shows nothing, and a key that types nothing make a step of their
# own.
_compute_typing_run(buffer::UndoBuffer, caret_holder, gesture) =
    !(gesture isa KeyPress) || any(iscntrl, gesture.text) ? :none :
    _is_typing_run_open(buffer, caret_holder) ? :continues : :starts

# A run is open while its last step is typing and has a way back, nothing was
# taken back since, the caret is where the run left it, and the pause since is
# shorter than `TYPING_PAUSE`. The caret is the caret of `caret_holder`: the buffer,
# or the view of the buffer that the projection printed.
function _is_typing_run_open(buffer::UndoBuffer, caret_holder)
    entries = buffer.undo_entries
    (length(entries) > 0 && length(buffer.redo_entries) == 0) || return false
    last = entries[end]
    last.typing_caret !== nothing && !is_undo_barrier(last) &&
        time() - last.time < TYPING_PAUSE && last.typing_caret == get_typing_caret(caret_holder)
end

# Whether the last step of `buffer` is its copy of a step of `inner`.
function _is_copy_of_last_step(buffer::UndoBuffer, inner::UndoBuffer)
    entries = buffer.undo_entries
    (length(entries) > 0 && length(buffer.redo_entries) == 0) || return false
    inverse = entries[end].inverse
    inverse isa UndoOperation && inverse.buffer === inner
end

_is_own_history_step(buffer::UndoBuffer, operation::UndoOperation) = operation.buffer === buffer
_is_own_history_step(buffer::UndoBuffer, operation::RedoOperation) = operation.buffer === buffer
_is_own_history_step(buffer::UndoBuffer, operation) = false

# ── The undo of a window, as a wrapper of `build_editor` ─────────────────────

"""
    undo = true

The wrapper of `build_editor` that gives a window an undo of its own. It puts the
root document, such as the pane tree of the `tabs` wrapper, in an `UndoBuffer`,
drawn with [`UndoBufferToAnyProjection`](@ref), so `Ctrl+Z` takes back a change
that belongs to no file: a splitter that moves, a tab that opens or closes, a
draft. A document inside it that has a buffer of its own, such as a file tab,
answers `Ctrl+Z` first while it has the focus. It is off by default. It acts
around the tabs and inside the chrome of the `shell` wrapper.

A root that is a buffer already keeps it. The buffer holds the selection that the
root holds, rooted at the buffer. It keeps as many steps as the `HistorySettings`
of the `settings` wrapper of the same editor say, when that wrapper is on.
"""
function wrap_editor!(::Val{:undo}, layer::Symbol, argument, parts::EditorParts)
    parts.document isa UndoBuffer && return parts
    content = parts.document
    settings = get(parts.arguments, :settings, nothing)
    buffer = settings isa Settings ?
        UndoBuffer(content; capacity = get_setting_cell(
            get_settings_group!(settings, HistorySettings), :undo_capacity)) :
        UndoBuffer(content)
    inner = get_selection(content)
    inner === nothing || replace_selection!(buffer,
        concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                          strip_reference_types(inner)))
    parts.document = buffer
    parts.projection = RecursiveProjection(TypeDispatchingProjection(
        UndoBuffer => UndoBufferToAnyProjection(), Any => parts.projection))
    parts
end

get_wrapper_layers(::Val{:undo}) = (:container => 5,)
