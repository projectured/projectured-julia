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
    input::Any           # the UndoBuffer
    output::Any          # computed: the content's own output
    content_iomap::Any   # the content's child IoMap
end

# The one step from the buffer to what it holds. Every reference that crosses
# this projection gains or loses it, and every operation the content answers is
# rerooted through it.
const _CONTENT_STEPS = (FieldReferenceStep("content"),)

# ── Printer ──────────────────────────────────────────────────────────────────

function print_document(p::UndoBufferToAnyProjection, recursion, input::UndoBuffer, ctx)
    content_iomap = print_child(recursion, input.content,
                                make_child_context(ctx, FieldReferenceStep("content")))
    UndoBufferToAnyIoMap(p, input, Cell(@computation content_iomap.output), content_iomap)
end

# ── Reference mapping ────────────────────────────────────────────────────────
#
# The output is the content's output, so the maps are asymmetric: forward peels
# the one step that reaches the content, backward puts it back.

function map_reference_forward(::UndoBufferToAnyProjection, iomap::UndoBufferToAnyIoMap, reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    (head isa FieldReferenceStep && head.name == "content") || return nothing
    child = iomap.content_iomap
    map_reference_forward(child.projection, child, get_reference_tail(reference))
end

function map_reference_backward(::UndoBufferToAnyProjection, iomap::UndoBufferToAnyIoMap, reference)
    child = iomap.content_iomap
    mapped = map_reference_backward(child.projection, child, reference)
    mapped === nothing && return nothing
    ConcreteReference(FieldReferenceStep("content"), mapped)
end

# ── Gestures ─────────────────────────────────────────────────────────────────

"""
    get_projection_gesture_bindings(p::UndoBufferToAnyProjection, iomap)

`Ctrl+Z` takes one step back, `Ctrl+Y` and `Ctrl+Shift+Z` put one back.

A binding answers `nothing` when its list is empty, so a key with nothing to do
falls through instead of being swallowed.
"""
function get_projection_gesture_bindings(p::UndoBufferToAnyProjection, iomap)
    buffer = iomap.input
    undo = (document, event) -> length(buffer.undo_entries) == 0 ? nothing : UndoOperation(buffer)
    redo = (document, event) -> length(buffer.redo_entries) == 0 ? nothing : RedoOperation(buffer)
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

function read_intent(p::UndoBufferToAnyProjection, recursion, change::Intent,
                     iomap::UndoBufferToAnyIoMap)
    child = iomap.content_iomap
    # Routing one gesture stops at the first answer; a collection takes every
    # answer, with the content's rerooted exactly as its operations are.
    if change.gesture isa CollectIntents
        inner = reroot_operation(read_intent(child.projection, recursion, change, child).operation,
                                 _CONTENT_STEPS)
        own = read_projection_gesture(p, iomap, change.gesture)
        return Intent(change.gesture,
                      merge_collected_intents(_collected_intents(inner), _collected_intents(own)))
    end
    # An operation with a route goes to the content, and comes back recorded as
    # the content's answer to a gesture does.
    if change.route !== nothing
        routed = follow_intent_route(change, _CONTENT_STEPS...)
        routed === nothing && return Intent(change.gesture, nothing)
        answer = reroot_operation(read_routed_intent(child.projection, recursion, routed, child).operation,
                                  _CONTENT_STEPS)
        answer isa Operation || return Intent(change.gesture, nothing)
        return Intent(change.gesture, _record_operation(p, iomap, change.gesture, answer))
    end
    inner = read_intent(child.projection, recursion, change, child)
    answer = reroot_operation(inner.operation, _CONTENT_STEPS)
    # Only a real operation is a change to record. A reader that declines answers
    # `nothing`, or hands the gesture back untranslated, and neither is a change.
    answer isa Operation &&
        return Intent(change.gesture, _record_operation(p, iomap, change.gesture, answer))
    # The content had nothing to say, so the buffer's own keys answer. Last, not
    # first: with a buffer inside a buffer, the inner one must win.
    own = read_projection_gesture(p, iomap, change.gesture)
    own === nothing || return Intent(change.gesture, own)
    # Neither of us: hand back what the content answered, so a layer above still
    # sees the gesture it declined.
    Intent(change.gesture, answer)
end

# 3-arg payload form, for a test and for a parent that hands a bare payload.
read_intent(p::UndoBufferToAnyProjection, iomap::UndoBufferToAnyIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Whether this buffer records this operation, and how.
function _record_operation(p::UndoBufferToAnyProjection, iomap::UndoBufferToAnyIoMap,
                           gesture, operation)
    buffer = iomap.input
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
        return RecordUndoOperation(buffer, inner, run)
    end
    # A buffer never records its own undo or redo.
    _is_own_history_step(buffer, operation) && return operation
    p.filter(gesture, operation) || return operation
    RecordUndoOperation(buffer, operation, _compute_typing_run(buffer, gesture))
end

# Whether a step is typing, and whether it joins the run of the last step. A
# `KeyPress` is a character; a key that is not one arrives as a `KeyDown`, and it
# makes a step of its own.
_compute_typing_run(buffer::UndoBuffer, gesture) =
    !(gesture isa KeyPress) ? :none : _is_typing_run_open(buffer) ? :continues : :starts

# A run is open while its last step is typing and has a way back, nothing was
# taken back since, the caret is where the run left it, and the pause since is
# shorter than `TYPING_PAUSE`.
function _is_typing_run_open(buffer::UndoBuffer)
    entries = buffer.undo_entries
    (length(entries) > 0 && length(buffer.redo_entries) == 0) || return false
    last = entries[end]
    last.typing_caret !== nothing && !is_undo_barrier(last) &&
        time() - last.time < TYPING_PAUSE && last.typing_caret == get_typing_caret(buffer)
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

# Only a real collection merges; anything else a reader answered is not one.
_collected_intents(op::CollectedIntentsOperation) = op
_collected_intents(::Any) = nothing

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
# @positional: the arity of the wrapper seam of the kernel.
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
