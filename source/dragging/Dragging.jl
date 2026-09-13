# ──────────────────────────────────────────────────────────────────────────
# Folded in from Dragging.jl.
# ── Transient gesture state ───────────────────────────────────────────────

"""
    _DragState

Mutable per-projection drag state. `phase` is `:idle`, `:pending` (button held,
not yet past the threshold), or `:dragging` (threshold crossed). `x0`/`y0` are
the grab coordinates; `source` is the content-domain reference of the element
being dragged (captured from `content.selection` at grab time).
"""
mutable struct _DragState
    phase::Symbol
    x0::Int
    y0::Int
    source::Union{Reference, Nothing}
end

_DragState() = _DragState(:idle, 0, 0, nothing)

# ── Projection ────────────────────────────────────────────────────────────

"""
    DraggingProjection(; threshold=5)

Projection over `DraggingState`. `threshold` (overridden by the wrapped
`DraggingState.threshold` at read time) is the pixel distance a held press must
travel before it becomes a drag.
"""
struct DraggingProjection <: Projection
    state::_DragState
end

DraggingProjection(; kw...) = DraggingProjection(_DragState())

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
    inner = reconcile_child_iomap(() -> input.content, c -> print_child(recursion, c, ctx))
    output = ComputedCell(() -> inner[].output)
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

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::DraggingProjection, recursion, change::Intent, iomap::DraggingIoMap)
    gesture = change.gesture
    state = iomap.input::DraggingState
    content = state.content
    st = p.state
    threshold = state.threshold

    if gesture isa MouseDown && gesture.button === :left && st.phase === :idle
        # Resolve the grab target by hit-testing the press point through the inner
        # chain; fall back to the current selection if the point hits nothing.
        st.source = _locate_point(p, recursion, iomap, gesture.x, gesture.y, gesture.modifiers)
        st.source === nothing && (st.source = _selection_path(content))
        st.phase = :pending
        st.x0 = gesture.x
        st.y0 = gesture.y
        return Intent(change.gesture, nothing)            # absorb the press

    elseif gesture isa MouseMove && st.phase === :pending
        if hypot(gesture.x - st.x0, gesture.y - st.y0) >= threshold
            st.phase = :dragging
        end
        return Intent(change.gesture, nothing)            # absorb motion

    elseif gesture isa MouseMove && st.phase === :dragging
        return Intent(change.gesture, nothing)            # absorb motion

    elseif gesture isa MouseUp && st.phase === :pending
        st.phase = :idle                                  # sub-threshold: a click —
        return Intent(change.gesture, nothing)            # let the synthesised MousePress select

    elseif gesture isa MouseUp && st.phase === :dragging
        st.phase = :idle
        source = st.source
        st.source = nothing
        # Resolve the drop target by hit-testing the release point through the
        # inner chain (the same path a real click would take).
        target = _locate_point(p, recursion, iomap, gesture.x, gesture.y, gesture.modifiers)
        return Intent(change.gesture, _make_move(content, source, target))

    else
        # Delegate everything else (real clicks, key events, …) to the inner
        # chain, then re-root the resulting *content-domain* operation up through
        # the `content` field so its reference is valid against the DraggingState
        # — the same lift `map_reference_backward` performs. Without this,
        # `set_selection!` can't descend into `content` and the cursor never
        # re-renders (and walk-right / repl round-trips stall). nothing /
        # ToggleCollapseOperation pass through `reroot_operation` unchanged.
        inner = read_intent(iomap.inner_iomap.projection, recursion, change, iomap.inner_iomap)
        inner_op = inner isa Intent ? inner.operation : inner
        return Intent(change.gesture, reroot_operation(inner_op, (FieldReferenceStep("content"),)))
    end
end

# 3-arg payload form (reader entry point).
read_intent(p::DraggingProjection, iomap::DraggingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Hit-test a window pixel `(x, y)` by synthesising a left `MousePress` there and
# delegating it to the inner chain — exactly the path a real click takes through
# the graphics layer down to the content domain. The resulting operation is only
# *read* (never applied), so this is a side-effect-free query for the
# content-domain reference under the point. Returns the reference, or nothing
# when the point resolves to no selectable element (or to a non-selection op,
# e.g. a collapse-marker toggle).
function _locate_point(p::DraggingProjection, recursion, iomap::DraggingIoMap, x::Int, y::Int, mods)
    probe = Intent(MousePress(:left, x, y, mods), nothing)
    inner = read_intent(iomap.inner_iomap.projection, recursion, probe, iomap.inner_iomap)
    op = inner isa Intent ? inner.operation : inner
    op isa ReplaceSelectionOperation ? op.path : nothing
end

# Build a MoveRangeOperation from the source/destination references, or nothing
# when either cannot be resolved to a (collection, element index).
function _make_move(content, source::Union{Reference,Nothing}, target::Union{Reference,Nothing})
    (source === nothing || target === nothing) && return nothing
    src = _locate_collection_index(content, source)
    dst = _locate_collection_index(content, target)
    (src === nothing || dst === nothing) && return nothing
    (src_cv, src_idx) = src
    (dst_cv, dst_idx) = dst
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
        push!(steps, head(cur))
        cur = tail(cur)
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
    # Skip canonical TypeReferenceStep checkpoints before reading the `content` step.
    reference = reference
    if reference isa ConcreteReference
        h = head(reference)
        if h isa FieldReferenceStep && h.name == "content"
            return map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, tail(reference))
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
