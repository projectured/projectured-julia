# Fragment of `DraggingModule`.
#
# A higher-order projection that dispatches on `DraggingState` documents and adds
# drag-and-drop reordering to the wrapped `content`.
#
# **Printer** — transparent: projects `state.content` through the outer recursion
# and returns its output (the `DraggingState` itself contributes nothing visible),
# modelled on `TooltipDecoratorProjection`.
#
# **Reader** — the state is the part whose drag is on. A `MouseDown(:left)` keeps
# the press in the state, with the element under the pointer as the source: the
# path that the mouse target of the content names, or the selection. Once a move
# with the button held travels past `threshold` pixels, the state starts its drag
# (`StartDragOperation`), and the drag wrapper sends it `DragEnd` or `DragCancel`
# by its path. `DragEnd` moves the source to the element under the pointer, which
# the mouse target of the content names at the release (`find_drop_zone`), with a
# `MoveRangeOperation`. A press that is released before crossing the threshold
# falls through, so the normal click-to-select path runs. The state of the drag
# is view state of the document, so the projection holds none.

# ── Projection ────────────────────────────────────────────────────────────

"""
    DraggingProjection()

Projection over `DraggingState`. The `threshold` of the state is the pixel
distance a held press must travel before it becomes a drag.
"""
struct DraggingProjection <: Projection end

# `output` forwards the reconciled content child's output reactively, so the
# IoMap keeps its identity while the inner projection re-derives, and a content
# swap rebuilds the child (PAR-STABLE-IOMAP-IDENTITY); `iomap.inner_iomap` reads
# the current child.
@iomap struct DraggingIoMap
    projection::Any
    input::Any          # DraggingState
    output::Any         # whatever content projects to
    inner_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::DraggingProjection, recursion, input::DraggingState, ctx)
    inner = make_reconciled_child_iomap_cell(() -> input.content, c -> print_child(recursion, c, ctx))
    output = Cell(@computation inner[].output)
    DraggingIoMap(p, input, output, inner)
end

# ── Operation ─────────────────────────────────────────────────────────────

"""
    MoveRangeOperation(source, source_start, source_stop, destination, destination_index)

Move the elements `source_start:source_stop` (1-based, inclusive) of the
`source` `CellVector` to position `destination_index` (1-based; the moved block
ends up starting there) of the `destination` `CellVector`. The raw `Cell`s are
relocated, so element identity is preserved.

The `CellVector`s are carried by the operation directly (resolved by the reader
from the live `content`), rather than as `editor.document`-rooted paths — this
mirrors how the split-pane operations carry the `WidgetSplitPane` itself, and
sidesteps re-rooting the reference up through the projections above
`DraggingProjection`.
"""
struct MoveRangeOperation <: Operation
    source::CellVector
    source_start::Int
    source_stop::Int
    destination::CellVector
    destination_index::Int
end

function evaluate_operation(editor, op::MoveRangeOperation)
    src = op.source
    dst = op.destination
    a, b = op.source_start, op.source_stop
    (a < 1 || b > length(src) || a > b) && return
    n = b - a + 1

    # Lift the raw cells (preserve identity), then remove them from the source.
    moved = [get_cell_at(src, i) for i in a:b]
    for _ in 1:n
        deleteat!(src, a)
    end

    # Fix up the insertion index: when moving inside one collection, removing the
    # block shifts everything after `a` left by `n`.
    insert_at = op.destination_index
    if src === dst && insert_at > b
        insert_at -= n
    end
    insert_at = clamp(insert_at, 1, length(dst) + 1)

    # No-op move (dropped back onto its own start) — re-insert in place.
    for (k, cell) in enumerate(moved)
        insert!(dst, insert_at + k - 1, cell)
    end
end

# The way back is the move that puts the block where it came from. Both ends are
# worked out from the numbers the move starts with, because an inverse is taken
# before the move runs.
#
# The index the block goes back to needs the same correction the move itself
# makes: inside one collection, lifting the block shifts everything after it left
# by its length. A block that moved LEFT is therefore put back at `a + n`, which
# the correction turns into `a`; a block that moved right, or moved between two
# collections, goes back at `a` unchanged.
function make_inverse_operation(document, op::MoveRangeOperation)
    source, destination = op.source, op.destination
    a, b = op.source_start, op.source_stop
    # The move itself declines these, so there is nothing to take back.
    (a < 1 || b > length(source) || a > b) && return DoNothingOperation()
    count = b - a + 1
    landed = op.destination_index
    if source === destination && landed > b
        landed -= count
    end
    limit = (source === destination ? length(destination) - count : length(destination)) + 1
    landed = clamp(landed, 1, limit)
    back = source === destination && landed < a ? a + count : a
    MoveRangeOperation(destination, landed, landed + count - 1, source, back)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::DraggingProjection, recursion, change::Intent, iomap::DraggingIoMap)
    gesture = change.gesture
    state = iomap.input::DraggingState
    press = state.press
    content = state.content
    # The parts of the drag come by the path of the state. The mouse target of the
    # content follows the pointer, so a move needs no answer of its own.
    if press !== nothing && gesture isa Union{DragMove, DragEnd, DragCancel}
        gesture isa DragMove && return Intent(gesture, nothing)
        gesture isa DragCancel && return Intent(gesture, _write_press(state, nothing))
        landing = find_drop_zone(state, press.source, get_mouse_target(content))
        return Intent(gesture, _join_drag_operations(_make_move(content, press.source, landing),
                                                     _write_press(state, nothing)))
    end
    if gesture isa MouseDown && gesture.button === :left && press === nothing
        source = get_mouse_target(content)
        source === nothing && (source = _selection_path(content))
        source === nothing ||
            return Intent(gesture, _write_press(state, (x = gesture.x, y = gesture.y,
                                                        source = source, started = false)))
    end
    if press !== nothing && !press.started && gesture isa MouseUp
        # Released before the threshold: a click, which the `MouseClick` selects.
        return Intent(gesture, _write_press(state, nothing))
    end
    # Everything else, the moves too, goes on to the inner chain, and the answer
    # is re-rooted up through the `content` field so its reference is valid
    # against the `DraggingState`. So the mouse target of the content follows the
    # pointer, also during a drag.
    inner = read_intent(iomap.inner_iomap.projection, recursion, change, iomap.inner_iomap)
    inner_op = inner isa Intent ? inner.operation : inner
    answer = reroot_operation(inner_op, (FieldReferenceStep("content"),))
    if press !== nothing && !press.started && gesture isa MouseMove &&
       !is_move_without_button(gesture) &&
       hypot(gesture.x - press.x, gesture.y - press.y) >= state.threshold
        answer = _join_drag_operations(
            _write_press(state, merge(press, (started = true,))),
            StartDragOperation(EmptyReference(), press.source), answer)
    end
    Intent(gesture, answer)
end

# 3-arg payload form (reader entry point).
read_intent(p::DraggingProjection, iomap::DraggingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# A write of the press of the state, which a history does not record.
_write_press(state::DraggingState, press) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(state, "press", press))

# The operations in order, without the ones that are `nothing`, as one operation.
function _join_drag_operations(operations...)
    kept = Any[operation for operation in operations if operation !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

# A list in the content takes an element at the element under the pointer: the
# zone is that list and the place of that element in it. The state knows the
# pointer by the mouse target of its content, the path of the part under it.
find_drop_zone(state::DraggingState, dragged, point) =
    point isa Reference ? _locate_collection_index(state.content, point) : nothing

# A `MoveRangeOperation` of the element at `source` to `landing`, a list and a
# place in it, or nothing when either cannot be resolved.
function _make_move(content, source, landing)
    (source === nothing || landing === nothing) && return nothing
    src = _locate_collection_index(content, source)
    src === nothing && return nothing
    (src_cv, src_idx) = src
    (dst_cv, dst_idx) = landing
    MoveRangeOperation(src_cv, src_idx, src_idx, dst_cv, dst_idx)
end

_selection_path(content) =
    hasproperty(content, :selection) ? getfield(content, :selection)[] : nothing

# Resolve a reference path to (owning CellVector, 1-based element index). Splits
# the path at its last element `RangeReferenceStep`; the prefix resolves (via
# `evaluate_reference`) to the owning collection. Returns nothing when the prefix
# does not land on a CellVector.
function _locate_collection_index(content, path::Reference)
    steps = Any[]
    cur = path
    while cur isa ConcreteReference
        push!(steps, get_reference_head(cur))
        cur = get_reference_tail(cur)
    end
    # Find the last element RangeReferenceStep.
    last_elem = 0
    for i in length(steps):-1:1
        s = steps[i]
        if s isa RangeReferenceStep && is_element_reference_step(s)
            last_elem = i
            break
        end
    end
    last_elem == 0 && return nothing
    prefix = EmptyReference()
    for i in (last_elem - 1):-1:1
        prefix = ConcreteReference(steps[i], prefix)
    end
    coll = try
        evaluate_reference(content, prefix)
    catch
        return nothing
    end
    coll isa CellVector || return nothing
    (coll, (steps[last_elem]::RangeReferenceStep).start + 1)
end

# ── Reference mapping (transparent, via the "content" field) ───────────────

function map_reference_forward(::DraggingProjection, iomap::DraggingIoMap, reference)
    reference = reference
    if reference isa ConcreteReference
        h = get_reference_head(reference)
        if h isa FieldReferenceStep && h.name == "content"
            return map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, get_reference_tail(reference))
        end
        return nothing
    end
    return reference
end

function map_reference_backward(::DraggingProjection, iomap::DraggingIoMap, reference)
    inner = map_reference_backward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
    inner === nothing && return nothing
    ConcreteReference(FieldReferenceStep("content"), inner)
end
