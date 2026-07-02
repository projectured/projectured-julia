"""
    DraggingProjectionModule

A higher-order projection that dispatches on `DraggingState` documents and adds
drag-and-drop reordering to the wrapped `content`.

**Printer** — transparent: projects `state.content` through the outer recursion
and returns its output (the `DraggingState` itself contributes nothing visible),
modelled on `TooltipDecoratorProjection`.

**Reader** — a press → drag → drop state machine. A `MouseDown(:left)` on the
currently-selected element arms a *pending* drag; once the cursor moves past
`threshold` pixels the drag becomes *active*; the `MouseUp` that ends an active
drag resolves a drop target and emits a `MoveRangeOperation` reordering the
elements. A press that is released before crossing the threshold falls through
unchanged so the normal click-to-select path runs.

The drop *target* reference is read out of the operation the inner (downstream)
reader produces for the ending `MouseUp` — i.e. the graphics layer's hit-test of
that event. Until the graphics layer hit-tests `MouseUp` (see the plan's Phase 1),
a live drop produces no target and the drag is a no-op; the reader logic itself
is exercised by `DraggingTest` with a synthetic hit-test operation.

Transient gesture state (phase, grab coords, source reference) lives on the
projection instance — there is only ever one drag in flight — mirroring how
`TooltipDecoratorProjection` keeps its state on the projection rather than the
document.
"""
module DraggingProjectionModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ChangeModule: Change, as_change
import ..IoMapApiModule: IoMap
import ..ReactiveModule: Cell
import ..CollectionModule: CellVector, cell_at
import ..ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath,
                          RangeReference, FieldReference, is_element_reference, evaluate_reference,
                          head, tail
import ..DraggingDocumentModule: DraggingState
import ..OperationModule: ReplaceSelectionOperation
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationRerootingModule: prepend_steps_to_op
import ..MouseModule: MouseDown, MouseUp, MouseMove, MousePress
import ..ModifiersModule: Modifiers

export DraggingProjection, DraggingProjectionIoMap, MoveRangeOperation

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
    source::Union{ReferencePath, Nothing}
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

struct DraggingProjectionIoMap <: IoMap
    projection::Any
    input::Any          # DraggingState
    output::Any         # whatever content projects to
    inner_iomap::Any
end

# ── Printer (transparent) ─────────────────────────────────────────────────

function projection_print(p::DraggingProjection, recursion, input::DraggingState, ctx)
    inner = projection_printer_recurse(recursion, input.content, ctx)
    DraggingProjectionIoMap(p, input, inner.output, inner)
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
    moved = [cell_at(src, i) for i in a:b]
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

function projection_read(p::DraggingProjection, recursion, change::Change, iomap::DraggingProjectionIoMap)
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
        return Change(change.gesture, nothing)            # absorb the press

    elseif gesture isa MouseMove && st.phase === :pending
        if hypot(gesture.x - st.x0, gesture.y - st.y0) >= threshold
            st.phase = :dragging
        end
        return Change(change.gesture, nothing)            # absorb motion

    elseif gesture isa MouseMove && st.phase === :dragging
        return Change(change.gesture, nothing)            # absorb motion

    elseif gesture isa MouseUp && st.phase === :pending
        st.phase = :idle                                  # sub-threshold: a click —
        return Change(change.gesture, nothing)            # let the synthesised MousePress select

    elseif gesture isa MouseUp && st.phase === :dragging
        st.phase = :idle
        source = st.source
        st.source = nothing
        # Resolve the drop target by hit-testing the release point through the
        # inner chain (the same path a real click would take).
        target = _locate_point(p, recursion, iomap, gesture.x, gesture.y, gesture.modifiers)
        return Change(change.gesture, _make_move(content, source, target))

    else
        # Delegate everything else (real clicks, key events, …) to the inner
        # chain, then re-root the resulting *content-domain* operation up through
        # the `content` field so its reference is valid against the DraggingState
        # — the same lift `map_reference_backward` performs. Without this,
        # `set_selection!` can't descend into `content` and the cursor never
        # re-renders (and walk-right / repl round-trips stall). nothing /
        # ToggleCollapseOperation pass through `prepend_steps_to_op` unchanged.
        inner = projection_read(iomap.inner_iomap.projection, recursion, change, iomap.inner_iomap)
        inner_op = inner isa Change ? inner.operation : inner
        return Change(change.gesture, prepend_steps_to_op(inner_op, (FieldReference("content"),)))
    end
end

# 3-arg compatibility shim (legacy reader entry point).
projection_read(p::DraggingProjection, iomap::DraggingProjectionIoMap, payload) =
    projection_read(p, nothing, as_change(payload), iomap).operation

# Hit-test a window pixel `(x, y)` by synthesising a left `MousePress` there and
# delegating it to the inner chain — exactly the path a real click takes through
# the graphics layer down to the content domain. The resulting operation is only
# *read* (never applied), so this is a side-effect-free query for the
# content-domain reference under the point. Returns the reference, or nothing
# when the point resolves to no selectable element (or to a non-selection op,
# e.g. a collapse-marker toggle).
function _locate_point(p::DraggingProjection, recursion, iomap::DraggingProjectionIoMap, x::Int, y::Int, mods)
    probe = Change(MousePress(:left, x, y, mods), nothing)
    inner = projection_read(iomap.inner_iomap.projection, recursion, probe, iomap.inner_iomap)
    op = inner isa Change ? inner.operation : inner
    op isa ReplaceSelectionOperation ? op.path : nothing
end

# Build a MoveRangeOperation from the source/destination references, or nothing
# when either cannot be resolved to a (collection, element index).
function _make_move(content, source::Union{ReferencePath,Nothing}, target::Union{ReferencePath,Nothing})
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
# the path at its last element `RangeReference`; the prefix resolves (via
# `evaluate_reference`) to the owning collection. Returns nothing when the prefix
# does not land on a CellVector.
function _locate_collection_index(content, path::ReferencePath)
    steps = Any[]
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, head(cur))
        cur = tail(cur)
    end
    # Find the last element RangeReference.
    last_elem = 0
    for i in length(steps):-1:1
        s = steps[i]
        if s isa RangeReference && is_element_reference(s)
            last_elem = i
            break
        end
    end
    last_elem == 0 && return nothing
    prefix = EmptyReferencePath()
    for i in (last_elem - 1):-1:1
        prefix = ConcreteReferencePath(steps[i], prefix)
    end
    coll = try
        evaluate_reference(content, prefix)
    catch
        return nothing
    end
    coll isa CellVector || return nothing
    (coll, (steps[last_elem]::RangeReference).start + 1)
end

# ── Reference mapping (transparent, via the "content" field) ───────────────

function map_reference_forward(::DraggingProjection, iomap::DraggingProjectionIoMap, reference)
    # Skip canonical TypeReference checkpoints before reading the `content` step.
    reference = reference
    if reference isa ConcreteReferencePath
        h = head(reference)
        if h isa FieldReference && h.name == "content"
            return map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, tail(reference))
        end
        return nothing
    end
    return reference
end

function map_reference_backward(::DraggingProjection, iomap::DraggingProjectionIoMap, reference)
    inner = map_reference_backward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
    inner === nothing && return nothing
    ConcreteReferencePath(FieldReference("content"), inner)
end

end # module
