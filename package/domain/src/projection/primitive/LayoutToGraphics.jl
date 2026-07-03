"""
    LayoutToGraphicsModule

Projections from layout documents (`HorizontalLayout`, `VerticalLayout`,
`GridLayout`, `FlowLayout`, `StackLayout`) to `GraphicsCanvas`.

Every projection follows the same two-phase shape:

1. Recurse into each child to obtain a `GraphicsCanvas`.
2. Read each child canvas's `w` / `h` cells and wire computed cells
   for per-child `(x, y)` and the outer canvas's `(w, h)`.

Each child canvas is wrapped in an outer `GraphicsCanvas` at its
computed `(x, y)`. The resulting per-child position cells are reactive:
an edit that changes a child's intrinsic extent invalidates only the
downstream position/extent cells, no re-projection of the layout.
"""
module LayoutToGraphicsModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: print_document, print_child, read_intent,
                               map_reference_forward, map_reference_backward, Projection
import ..DocumentApiModule: Document
import ..LayoutModule: HorizontalLayout, VerticalLayout, GridLayout, FlowLayout, StackLayout,
                       LayoutConstraint, ConstraintLayout, LayoutRelation, LayoutAnchor,
                       allocate_axis,
                       layout_min, layout_max, layout_preferred, layout_weight
import ..ConstraintSolverModule: SolverAnchor, SolverRelation, solve_constraint_layout,
                                 ConstraintSolver, FallbackConstraintSolver
import ..CollectionModule: CellVector
import ..GraphicsModule: GraphicsCanvas, GraphicsDocument, graphics_size, layout_none, hit_element_at
import ..IoMapModule: SimpleIoMap, ChildrenIoMap, ContentIoMap
import ..IoMapApiModule: IoMap
import ..MouseModule: MouseScroll, MousePress, MouseMove, MouseEnter, MouseLeave
import ..EventCaseModule: var"@event_case"
import ..OperationApiModule: Operation
import ..OperationRerootingModule: reroot_operation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference, PointReference
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown
# Focus-path helpers live in the document-layer WidgetModule, included before this
# module, so layout containers can share Tab traversal with the widget readers.
import ..WidgetModule: first_focusable_path, last_focusable_path, _next_focusable_in
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: make_child_context, with_available_size
export HorizontalLayoutToGraphicsCanvas, VerticalLayoutToGraphicsCanvas,
       GridLayoutToGraphicsCanvas, FlowLayoutToGraphicsCanvas,
       StackLayoutToGraphicsCanvas, LayoutConstraintToGraphicsCanvas,
       ConstraintLayoutToGraphicsCanvas,
       LayoutToGraphics, GridLayoutIoMap

# ── Projection structs ─────────────────────────────────────────────────────

struct HorizontalLayoutToGraphicsCanvas <: Projection end
struct VerticalLayoutToGraphicsCanvas   <: Projection end
struct GridLayoutToGraphicsCanvas       <: Projection end
struct FlowLayoutToGraphicsCanvas       <: Projection end
struct StackLayoutToGraphicsCanvas      <: Projection end
struct LayoutConstraintToGraphicsCanvas <: Projection end

"""
    ConstraintLayoutToGraphicsCanvas(; solver = FallbackConstraintSolver())

Projects a `ConstraintLayout` by solving its relations with `solver`. The
default `FallbackConstraintSolver` (core, dependency-free) stacks children at
the origin; pass a `TulipConstraintSolver` (opt-in `ProjecturedTulip` package)
for real LP-based constraint solving — same injection pattern as
`GraphGraphToGraphLayout`'s `engine`.
"""
struct ConstraintLayoutToGraphicsCanvas <: Projection
    solver::ConstraintSolver
end

ConstraintLayoutToGraphicsCanvas(; solver::ConstraintSolver=FallbackConstraintSolver()) =
    ConstraintLayoutToGraphicsCanvas(solver)

# ── GridLayout iomap (geometry-bearing) ─────────────────────────────────────

"""
    GridLayoutIoMap

Like `ChildrenIoMap` (it carries the same `projection` / `input` / `output` and
the per-child routing entries in `child_iomaps`), plus the grid *geometry*
exposed so a parent renderer can draw decorations without GridLayout knowing
anything about tables ("layout is just layout").

The geometry cells:

- `col_x::Vector{Cell}` — cumulative left edges, one per column (length = columns).
- `row_y::Vector{Cell}` — cumulative top edges, one per row (length = rows).
- `col_w::Vector{Cell}` / `row_h::Vector{Cell}` — per-column width / per-row height
  (max over the children in that column / row).
- `columns::Cell` — the grid's column count.
- `row_count::Cell` — the number of rows (`ceil(n / columns)`).
- `horizontal_gap` / `vertical_gap` — the inter-cell gaps.
- `w::Cell` / `h::Cell` — the outer canvas extent.

All cells are reactive: an edit that changes a child's intrinsic extent
invalidates only the downstream geometry cells.
"""
struct GridLayoutIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    child_iomaps::Cell
    col_x::Vector{Cell}
    row_y::Vector{Cell}
    col_w::Vector{Cell}
    row_h::Vector{Cell}
    columns::Cell
    row_count::Cell
    horizontal_gap::Cell
    vertical_gap::Cell
    w::Cell
    h::Cell
end

# Routing / forward helpers below read only `iomap.child_iomaps`; both iomap
# shapes carry that field, so they accept either.
const _LayoutChildrenIoMap = Union{ChildrenIoMap, GridLayoutIoMap}

# ── Helpers ────────────────────────────────────────────────────────────────

_empty_canvas() = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0),
                                 CellVector(), layout_none, true, Cell(nothing))

"""
Wrap a child graphics document at the (x, y) given by two cells. The wrapper is
a fresh canvas at (x, y) whose single element is the child — usually a
`GraphicsCanvas`, but any `GraphicsDocument` (a bare primitive) works too, so a
primitive can be positioned directly. Same pattern as `_make_canvas` in
`WidgetToGraphics`.
"""
function _wrap_child(child::GraphicsDocument, x_cell::Cell, y_cell::Cell)
    GraphicsCanvas(x_cell, y_cell,
                   Cell(Int32(0)), Cell(Int32(0)),
                   CellVector(Cell[Cell(child)]),
                   layout_none, true, Cell(nothing))
end

"""
Hit-test a coordinate event against each child wrapper canvas; returns
`(op, i)` for the first child that produced a non-`nothing` result.
`child_entries` is a vector of `(x_cell, y_cell, cim)` triples — the
same shape this module stores on `ChildrenIoMap`.
"""
function _route_to_children(child_entries::Vector, x::Int, y::Int, make_evt)
    for (i, entry) in enumerate(child_entries)
        entry === nothing && continue
        (ox_cell, oy_cell, cim) = entry::Tuple{Cell,Cell,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        ox = Int(ox_cell[])
        oy = Int(oy_cell[])
        lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
        # Bound the hit to this child's own box. `GraphicsText` carries no width
        # (the backend measures it at draw time), so `hit_element_at` leaves a
        # text element's right/bottom edge open — which in a row layout lets the
        # leftmost child greedily capture every click to its right. The child
        # canvas's `w`/`h` give the missing bound, so each child owns exactly its
        # laid-out box and a click resolves to the child actually under it.
        cw, ch = Int(canvas.w[]), Int(canvas.h[])
        (0 <= lx < cw && 0 <= ly < ch) || continue
        hit_element_at(canvas, lx, ly) === nothing && continue
        result = read_intent(cim.projection, cim, make_evt(lx, ly))
        result !== nothing && return (result, i)
    end
    nothing
end

_route_scroll(entries, evt::MouseScroll) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))

_route_click(entries, evt::MousePress) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> MousePress(evt.button, x, y, evt.modifiers))

# Pointer motion / crossings carry coordinates, so they hit-test the laid-out
# children exactly like a click — routing to the child *under the pointer*, not the
# selected one. Without this a hovered child inside a layout never sees the
# MouseEnter/MouseMove/MouseLeave the hover tracker synthesises. Mirrors
# WidgetComposite's crossing routing.
_route_move(entries, evt::MouseMove) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers))

_route_crossing(entries, evt) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> evt isa MouseEnter ? MouseEnter(x, y, evt.buttons, evt.modifiers) :
                                       MouseLeave(x, y, evt.buttons, evt.modifiers))

# Forward a coordless event to the single child the layout's selection points at.
function _forward_layout_event_slot(entries::Vector, evt, slot::Int)
    (1 <= slot <= length(entries)) || return nothing
    entry = entries[slot]
    entry === nothing && return nothing
    (_, _, cim) = entry::Tuple{Cell,Cell,Any}
    result = read_intent(cim.projection, cim, evt)
    result isa Operation ? (result, slot) : nothing
end

# Which child slot the layout's `selection` points at (a leading `children[i]`
# step), or 0 if none — mirror of `_selected_composite_slot` for the `children`
# field every layout document carries.
function _selected_layout_slot(doc, n::Int)
    hasproperty(doc, :selection) || return 0
    sel = getfield(doc, :selection)[]
    sel = sel
    sel isa ConcreteReferencePath || return 0
    (sel.head isa FieldReference && sel.head.name == "children") || return 0
    t = sel.tail
    (t isa ConcreteReferencePath && t.head isa RangeReference) || return 0
    slot = t.head.start + 1
    1 <= slot <= n ? slot : 0
end

# Edit-transparent routing shared by every *LayoutToGraphicsCanvas reader:
# mouse clicks/scrolls hit-test the laid-out children; coordless events go to
# the selected child (or are tried against each). The child's op is re-rooted by
# prepending `children[i]`, matching `_children_forward`'s convention so forward
# mapping and reads agree. Identity-bearing ops pass through unchanged.
# Tab traversal for a layout container (Stage 2), mirroring the composite reader:
# delegate Tab to the selected child; on decline advance my selection to the next
# focusable sibling (entering its first leaf); decline if none so the parent
# advances. A Tab with no child slot selected (∅ on me) bootstraps into my first
# (last) leaf. Selection move is relative to me; the parent's prepend re-roots it.
function _layout_tab(w, entries::Vector, evt)
    n = length(entries)
    reverse = evt.modifiers.shift
    i = _selected_layout_slot(w, n)
    if i == 0
        sub = reverse ? last_focusable_path(w) : first_focusable_path(w)
        return sub === nothing ? nothing : ReplaceSelectionOperation(sub)
    end
    deleg = _forward_layout_event_slot(entries, evt, i)
    if deleg !== nothing
        op, slot = deleg
        return reroot_operation(op, (FieldReference("children"), RangeReference(slot - 1, slot)))
    end
    j = _next_focusable_in(w.children, i, reverse)
    j == 0 && return nothing
    sub = reverse ? last_focusable_path(w.children[j]) : first_focusable_path(w.children[j])
    sub === nothing && return nothing
    ReplaceSelectionOperation(ConcreteReferencePath(FieldReference("children"),
        ConcreteReferencePath(RangeReference(j - 1, j), sub)))
end

function _route_layout_event(iomap::_LayoutChildrenIoMap, evt)
    entries = iomap.child_iomaps[]::Vector
    # Tab traversal: distributed focus advance, handled before the selection-only
    # coordless routing (so a declined Tab advances my own selection).
    if evt isa KeyDown && evt.key === :tab
        return _layout_tab(iomap.input, entries, evt)
    end
    res = @event_case evt begin
        MousePress  => _route_click(entries, evt)
        MouseScroll => _route_scroll(entries, evt)
        MouseMove   => _route_move(entries, evt)
        MouseEnter  => _route_crossing(entries, evt)
        MouseLeave  => _route_crossing(entries, evt)
        _ => begin
            # Selection-only: route the coordless event to the child the
            # selection points at, or nowhere (no broadcast fallback) — selection
            # is authoritative. See documentation/document/widget.md.
            slot = _selected_layout_slot(iomap.input, length(entries))
            slot == 0 ? nothing :
                        _forward_layout_event_slot(entries, evt, slot)
        end
    end
    res === nothing && return nothing
    op, i = res
    reroot_operation(op, (FieldReference("children"), RangeReference(i - 1, i)))
end

"""
Recurse into a child document via the dispatcher.
"""
function _recurse_child(recursion, child, ref)
    recursion === nothing && return SimpleIoMap(nothing, child, child)
    return print_child(recursion, child, ref)
end

"""
Read `w` from a child iomap's output. Returns 0 when the output isn't
a `GraphicsCanvas` (defensive — the layout still works, just collapses
to the children that are canvases).
"""
# A child's intrinsic extent. A laid-out child is normally a `GraphicsCanvas`
# (its `w`/`h` are the authored size). A bare graphics primitive
# (`GraphicsCircle`, `GraphicsLine`, …) reports its size generically via
# `graphics_size`, so it can be a layout child directly without being wrapped in
# a sized canvas.
function _child_w(cim)
    c = cim.output
    c isa GraphicsCanvas && return Int(c.w[])
    c isa GraphicsDocument && return graphics_size(c)[1]
    0
end

function _child_h(cim)
    c = cim.output
    c isa GraphicsCanvas && return Int(c.h[])
    c isa GraphicsDocument && return graphics_size(c)[2]
    0
end

# ── Allocation cell helpers ────────────────────────────────────────────────

"""
Build a `Cell{Vector{Int}}` that lazily computes the per-child allocation
for one axis. The cell depends reactively on the available-extent cell,
the gap cell, each child's intrinsic extent (via its canvas), and each
constraint field read via `getproperty`.
"""
function _alloc_cell(available_cell::Cell, child_iomaps::Vector, child_docs::Vector,
                     gap_cell::Cell, axis::Symbol)
    n = length(child_iomaps)
    Cell(function ()
        avail = Int(available_cell[])
        mins  = Vector{Int}(undef, n)
        maxs  = Vector{Int}(undef, n)
        prefs = Vector{Int}(undef, n)
        wts   = Vector{Float64}(undef, n)
        for i in 1:n
            doc = child_docs[i]
            intrinsic = axis === :x ? _child_w(child_iomaps[i]) : _child_h(child_iomaps[i])
            mins[i]   = layout_min(doc, axis, intrinsic)
            maxs[i]   = layout_max(doc, axis, intrinsic)
            prefs[i]  = layout_preferred(doc, axis, intrinsic)
            wts[i]    = layout_weight(doc, axis)
        end
        gap = Int(gap_cell[])
        allocate_axis(avail, mins, maxs, prefs, wts, gap, n)
    end)
end

# ── LayoutConstraint projection (trivial forwarder) ───────────────────────

"""
    LayoutConstraintToGraphicsCanvas

Recurse into the wrapped child with the parent-provided context unchanged
and forward the child's canvas as this projection's output. The constraint
values are not consumed here — they are read by the *parent* layout when
it allocates space across its children.
"""
function print_document(p::LayoutConstraintToGraphicsCanvas,
                          recursion, doc::LayoutConstraint, ctx)
    child = doc.child
    inner = recursion === nothing ?
            SimpleIoMap(nothing, child, child) :
            print_child(recursion, child,
                             make_child_context(ctx, @reference ^(ctx.reference).child))
    output = inner.output isa GraphicsDocument ? inner.output : _empty_canvas()
    ContentIoMap(p, doc, output, inner)
end

function map_reference_forward(::LayoutConstraintToGraphicsCanvas, iomap::ContentIoMap, reference)
    reference = reference
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "child" || return nothing
    map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, reference.tail)
end

function map_reference_backward(::LayoutConstraintToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::LayoutConstraintToGraphicsCanvas, iomap::ContentIoMap, evt)
    inner = iomap.inner_iomap
    inner === nothing && return nothing
    read_intent(inner.projection, inner, evt)
end

_off(v) = Int(v isa Cell ? v[] : v)

# Shift a child's forwarded image by where THIS container placed the child —
# but only when the image is a coordinate (`PointReference`). A structural path
# image passes through unchanged. (coordinates accumulate, paths stay paths — see
# `map_reference_forward`'s docstring.) The child canvas sits at the entry offset
# `(off_x, off_y)` the container wrapped it at PLUS the child canvas's own origin.
function _shift_child_image(child, off_x, off_y, cim)
    child isa PointReference || return child
    out = cim.output
    out isa GraphicsCanvas || return child
    PointReference(_off(off_x) + Int(out.x[]) + Int(child.x[]),
                   _off(off_y) + Int(out.y[]) + Int(child.y[]))
end

# Peel a `field[i]/rest` reference into the i-th child entry `(off_x, off_y, cim)`,
# forward-map the tail through the child's own mapper, and shift a coordinate
# result by this container's placement. Shared by every container that addresses
# children by an indexed field (`children` for layouts, `elements` for composite).
function _forward_descend(entries::Vector, field::String, reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    (h isa FieldReference && h.name == field) || return nothing
    rest = reference.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    idx = h2.start + 1
    1 <= idx <= length(entries) || return nothing
    (off_x, off_y, cim) = entries[idx]
    child = map_reference_forward(cim.projection, cim, rest.tail)
    _shift_child_image(child, off_x, off_y, cim)
end

"""
A reference of the form `children[i]/...` routes to the i-th child iomap's
forward mapping, shifting a coordinate image by the child's laid-out offset.
"""
_children_forward(iomap::_LayoutChildrenIoMap, reference) =
    _forward_descend(iomap.child_iomaps[]::Vector, "children", reference)

# ── Per-cell helpers (extracted to avoid begin/end inside comprehensions) ──

function _hl_child_x_cell(i::Int, child_iomaps::Vector, gap_cell::Cell)
    Cell(function ()
        x = 0
        for j in 1:(i-1)
            x += _child_w(child_iomaps[j]) + gap_cell[]
        end
        Int32(x)
    end)
end

"""Position helper for the main axis when extrinsic allocation is in effect."""
function _hl_alloc_child_x_cell(i::Int, actual_w_cells::Vector{Cell}, gap_cell::Cell)
    Cell(function ()
        x = 0
        for j in 1:(i-1)
            x += Int(actual_w_cells[j][]) + gap_cell[]
        end
        Int32(x)
    end)
end

"""Position helper for the main axis (y) of a VerticalLayout under extrinsic allocation."""
function _vl_alloc_child_y_cell(i::Int, actual_h_cells::Vector{Cell}, gap_cell::Cell)
    Cell(function ()
        y = 0
        for j in 1:(i-1)
            y += Int(actual_h_cells[j][]) + gap_cell[]
        end
        Int32(y)
    end)
end

function _hl_child_y_cell(i::Int, child_iomaps::Vector, outer_h::Cell, align_cell::Cell)
    Cell(function ()
        ch = _child_h(child_iomaps[i])
        oh = outer_h[]
        a  = align_cell[]
        y = a === :center ? div(oh - ch, 2) :
            a === :bottom ? oh - ch         :
                            0
        Int32(y)
    end)
end

function _vl_child_y_cell(i::Int, child_iomaps::Vector, gap_cell::Cell)
    Cell(function ()
        y = 0
        for j in 1:(i-1)
            y += _child_h(child_iomaps[j]) + gap_cell[]
        end
        Int32(y)
    end)
end

function _vl_child_x_cell(i::Int, child_iomaps::Vector, outer_w::Cell, align_cell::Cell)
    Cell(function ()
        cw = _child_w(child_iomaps[i])
        ow = outer_w[]
        a  = align_cell[]
        x = a === :center ? div(ow - cw, 2) :
            a === :right  ? ow - cw         :
                            0
        Int32(x)
    end)
end

# ── HorizontalLayout ───────────────────────────────────────────────────────

# Recompute the whole laid-out horizontal row. Like `_vl_build`, reads
# `doc.children` so the enclosing `build` cell re-runs on structural changes,
# while the per-child size/position cells stay lazy.
function _hl_build(recursion, doc, ctx)
    gap_cell   = getfield(doc, :gap)
    align_cell = getfield(doc, :vertical_align)
    n = length(doc.children)

    # Symmetric to VerticalLayout: propagate the available extent on the CROSS
    # axis (height) so children can fill the row's allocation, but strip it on
    # the MAIN axis (width) — a horizontal row sizes its width from the sum of
    # its children, so a child must not carry an `available_width` that
    # ultimately reads this layout's own outer width (a feedback loop that
    # stack-overflows). Keeping only the cross axis is cycle-free: `outer_h`
    # reads child heights while each child reads the parent-supplied
    # `available_height` cell, never `outer_h`.
    child_iomaps = Any[]
    for i in 1:n
        cctx = make_child_context(ctx, @reference ^(ctx.reference).children[i])
        cctx = with_available_size(cctx; width=nothing)
        push!(child_iomaps, _recurse_child(recursion, doc.children[i], cctx))
    end

    outer_h = Cell(function ()
        h = 0
        for cim in child_iomaps
            ch = _child_h(cim)
            ch > h && (h = ch)
        end
        h
    end)

    outer_w = Cell(function ()
        n2 = length(child_iomaps)
        n2 == 0 && return 0
        total = 0
        for cim in child_iomaps
            total += _child_w(cim)
        end
        total + (n2 - 1) * gap_cell[]
    end)

    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        push!(child_x, _hl_child_x_cell(i, child_iomaps, gap_cell))
        push!(child_y, _hl_child_y_cell(i, child_iomaps, outer_h, align_cell))
    end

    wrapped = Any[]
    for i in 1:n
        c = child_iomaps[i].output
        c isa GraphicsDocument || continue
        push!(wrapped, _wrap_child(c, child_x[i], child_y[i]))
    end

    entries = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(entries, (child_x[i], child_y[i], child_iomaps[i]))
    end

    (wrapped = wrapped, w = outer_w, h = outer_h, entries = entries)
end

function print_document(p::HorizontalLayoutToGraphicsCanvas,
                          recursion, doc::HorizontalLayout, ctx)
    build = Cell(() -> _hl_build(recursion, doc, ctx))
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(() -> Int32(build[].w[])),
                           Cell(() -> Int32(build[].h[])),
                           CellVector(() -> build[].wrapped),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, doc, outer, Cell(() -> build[].entries))
end

function map_reference_forward(::HorizontalLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::HorizontalLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::HorizontalLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_layout_event(iomap, evt)
end

# ── VerticalLayout ─────────────────────────────────────────────────────────

# Recompute the whole laid-out vertical stack. Reads `doc.children` (length +
# each child), so the enclosing `build` cell re-runs when the children list
# changes (a part is added/swapped) — that is what makes structure reactive. The
# per-child size/position cells it constructs stay lazy, so a child merely
# *growing* recomputes those cells without rebuilding the stack.
function _vl_build(recursion, doc, ctx)
    gap_cell   = getfield(doc, :gap)
    align_cell = getfield(doc, :horizontal_align)
    n = length(doc.children)

    # Propagate the available extent on the CROSS axis (width) so children can
    # fill the layout's allocation (responsive cards/text), but strip it on the
    # MAIN axis (height): a vertical stack sizes its height from the sum of its
    # children, so a child must not carry an `available_height` that ultimately
    # reads this layout's own outer height — that closes a feedback loop and
    # stack-overflows when the reactive cell evaluates. Keeping only the cross
    # axis is cycle-free because `outer_w` (below) reads child widths while each
    # child reads the *parent-supplied* `available_width` cell, never `outer_w`.
    child_iomaps = Any[]
    for i in 1:n
        cctx = make_child_context(ctx, @reference ^(ctx.reference).children[i])
        cctx = with_available_size(cctx; height=nothing)
        push!(child_iomaps, _recurse_child(recursion, doc.children[i], cctx))
    end

    outer_w = Cell(function ()
        w = 0
        for cim in child_iomaps
            cw = _child_w(cim)
            cw > w && (w = cw)
        end
        w
    end)

    outer_h = Cell(function ()
        n2 = length(child_iomaps)
        n2 == 0 && return 0
        total = 0
        for cim in child_iomaps
            total += _child_h(cim)
        end
        total + (n2 - 1) * gap_cell[]
    end)

    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        push!(child_x, _vl_child_x_cell(i, child_iomaps, outer_w, align_cell))
        push!(child_y, _vl_child_y_cell(i, child_iomaps, gap_cell))
    end

    wrapped = Any[]
    for i in 1:n
        c = child_iomaps[i].output
        c isa GraphicsDocument || continue
        push!(wrapped, _wrap_child(c, child_x[i], child_y[i]))
    end

    entries = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(entries, (child_x[i], child_y[i], child_iomaps[i]))
    end

    (wrapped = wrapped, w = outer_w, h = outer_h, entries = entries)
end

function print_document(p::VerticalLayoutToGraphicsCanvas,
                          recursion, doc::VerticalLayout, ctx)
    # A single cell holding the laid-out stack, recomputed when `doc.children`
    # changes. The output canvas, its element list, and the child-routing
    # entries are all derived reactively from it, so adding/removing a child
    # repaints without reprinting the projection (and without `iomap = nothing`).
    build = Cell(() -> _vl_build(recursion, doc, ctx))
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(() -> Int32(build[].w[])),
                           Cell(() -> Int32(build[].h[])),
                           CellVector(() -> build[].wrapped),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, doc, outer, Cell(() -> build[].entries))
end

function map_reference_forward(::VerticalLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::VerticalLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::VerticalLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_layout_event(iomap, evt)
end

# ── GridLayout ─────────────────────────────────────────────────────────────

_grid_row(i::Int, c::Int) = div(i - 1, c) + 1
_grid_col(i::Int, c::Int) = mod(i - 1, c) + 1

function _gl_col_w_cell(col::Int, n::Int, child_iomaps::Vector, cols_cell::Cell)
    Cell(function ()
        c = cols_cell[]
        col > c && return 0
        w = 0
        for k in 1:n
            if _grid_col(k, c) == col
                cw = _child_w(child_iomaps[k])
                cw > w && (w = cw)
            end
        end
        w
    end)
end

function _gl_row_h_cell(row::Int, n::Int, child_iomaps::Vector, cols_cell::Cell)
    Cell(function ()
        c = cols_cell[]
        nrows = div(n + c - 1, c)
        row > nrows && return 0
        h = 0
        for k in 1:n
            if _grid_row(k, c) == row
                ch = _child_h(child_iomaps[k])
                ch > h && (h = ch)
            end
        end
        h
    end)
end

function _gl_col_x_cell(col::Int, col_w::Vector{Cell}, hgap::Cell)
    Cell(function ()
        x = 0
        for cc in 1:(col-1)
            x += col_w[cc][] + hgap[]
        end
        x
    end)
end

function _gl_row_y_cell(row::Int, row_h::Vector{Cell}, vgap::Cell)
    Cell(function ()
        y = 0
        for rr in 1:(row-1)
            y += row_h[rr][] + vgap[]
        end
        y
    end)
end

# Per-column stretch weight / alignment (Stage 6 grid generalization). Empty
# vectors fall back to today's behaviour (no stretch, the single `horizontal_align`).
_col_stretch(v, col::Int) = (v isa AbstractVector && 1 <= col <= length(v)) ? Int(v[col]) : 0
_col_align(v, col::Int, default::Symbol) =
    (v isa AbstractVector && 1 <= col <= length(v)) ? Symbol(v[col]) : default

# A column's laid-out width: its content max, plus — when the parent seeded an
# `available_width` and this column has a positive stretch weight — its share of
# the leftover space (`available − Σcontent − gaps`) by weight.
function _gl_stretched_col_w_cell(col::Int, content_col_w::Vector{Cell}, cols_cell::Cell,
                                  hgap::Cell, stretch_cell::Cell, avail_w)
    Cell(function ()
        base = content_col_w[col][]
        avail_w === nothing && return base
        c = cols_cell[]
        (col > c) && return base
        sv = stretch_cell[]
        sc = _col_stretch(sv, col)
        sc == 0 && return base
        total_stretch = 0; total_content = 0
        for cc in 1:c
            total_stretch += _col_stretch(sv, cc)
            total_content += content_col_w[cc][]
        end
        total_stretch == 0 && return base
        gaps = max(0, c - 1) * hgap[]
        leftover = max(0, Int(avail_w[]) - total_content - gaps)
        base + (leftover * sc) ÷ total_stretch
    end)
end

function _gl_child_x(i::Int, child_iomaps::Vector,
                    cols_cell::Cell, col_w::Vector{Cell}, col_x::Vector{Cell},
                    halign::Cell, column_align_cell::Cell)
    Cell(function ()
        c = cols_cell[]
        cw = _child_w(child_iomaps[i])
        col = _grid_col(i, c)
        cellw = col_w[col][]
        a = _col_align(column_align_cell[], col, halign[])
        off = a === :center ? div(cellw - cw, 2) :
              a === :right  ? cellw - cw         :
                              0
        Int32(col_x[col][] + off)
    end)
end

function _gl_child_y(i::Int, child_iomaps::Vector,
                    cols_cell::Cell, row_h::Vector{Cell}, row_y::Vector{Cell},
                    valign::Cell)
    Cell(function ()
        c = cols_cell[]
        ch = _child_h(child_iomaps[i])
        row = _grid_row(i, c)
        cellh = row_h[row][]
        a = valign[]
        off = a === :center ? div(cellh - ch, 2) :
              a === :bottom ? cellh - ch         :
                              0
        Int32(row_y[row][] + off)
    end)
end

function print_document(p::GridLayoutToGraphicsCanvas,
                          recursion, doc::GridLayout, ctx)
    n = length(doc.children)
    if n == 0
        return GridLayoutIoMap(p, doc, _empty_canvas(), Cell(Tuple{Cell,Cell,Any}[]),
                               Cell[], Cell[], Cell[], Cell[],
                               getfield(doc, :columns), Cell(0),
                               getfield(doc, :horizontal_gap), getfield(doc, :vertical_gap),
                               Cell(Int32(0)), Cell(Int32(0)))
    end

    child_iomaps = Any[]
    for i in 1:n
        cim = _recurse_child(recursion, doc.children[i],
                             make_child_context(ctx, @reference ^(ctx.reference).children[i]))
        push!(child_iomaps, cim)
    end

    cols_cell = getfield(doc, :columns)
    hgap      = getfield(doc, :horizontal_gap)
    vgap      = getfield(doc, :vertical_gap)
    halign    = getfield(doc, :horizontal_align)
    valign    = getfield(doc, :vertical_align)
    column_align_cell   = getfield(doc, :column_align)
    column_stretch_cell = getfield(doc, :column_stretch)
    avail_w = ctx === nothing ? nothing : ctx.available_width

    # Pre-allocate up to n column / row extents — at most n columns
    # (one child per column, n rows of 1) or n rows (one column). `col_w` adds a
    # per-column stretch share over the content max (Stage 6 generalization).
    content_col_w = Cell[]
    col_w = Cell[]
    row_h = Cell[]
    for k in 1:n
        push!(content_col_w, _gl_col_w_cell(k, n, child_iomaps, cols_cell))
        push!(row_h, _gl_row_h_cell(k, n, child_iomaps, cols_cell))
    end
    for k in 1:n
        push!(col_w, _gl_stretched_col_w_cell(k, content_col_w, cols_cell, hgap, column_stretch_cell, avail_w))
    end

    col_x = Cell[]
    row_y = Cell[]
    for k in 1:n
        push!(col_x, _gl_col_x_cell(k, col_w, hgap))
        push!(row_y, _gl_row_y_cell(k, row_h, vgap))
    end

    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        push!(child_x, _gl_child_x(i, child_iomaps, cols_cell, col_w, col_x, halign, column_align_cell))
        push!(child_y, _gl_child_y(i, child_iomaps, cols_cell, row_h, row_y, valign))
    end

    outer_w = Cell(function ()
        c = cols_cell[]
        total = 0
        for cc in 1:c
            total += col_w[cc][]
        end
        total + max(0, c - 1) * hgap[]
    end)

    outer_h = Cell(function ()
        c = cols_cell[]
        nrows = div(n + c - 1, c)
        total = 0
        for rr in 1:nrows
            total += row_h[rr][]
        end
        total + max(0, nrows - 1) * vgap[]
    end)

    wrapped = Any[]
    for i in 1:n
        c = child_iomaps[i].output
        c isa GraphicsDocument || continue
        push!(wrapped, _wrap_child(c, child_x[i], child_y[i]))
    end

    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(() -> Int32(outer_w[])),
                           Cell(() -> Int32(outer_h[])),
                           CellVector(Cell[Cell(e) for e in wrapped]),
                           layout_none, true, Cell(nothing))

    entries = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(entries, (child_x[i], child_y[i], child_iomaps[i]))
    end

    row_count = Cell(function ()
        c = cols_cell[]
        c <= 0 ? 0 : div(n + c - 1, c)
    end)

    GridLayoutIoMap(p, doc, outer, Cell(entries),
                    col_x, row_y, col_w, row_h,
                    cols_cell, row_count, hgap, vgap,
                    Cell(() -> Int32(outer_w[])), Cell(() -> Int32(outer_h[])))
end

function map_reference_forward(::GridLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::GridLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::GridLayoutToGraphicsCanvas, iomap::GridLayoutIoMap, evt)
    _route_layout_event(iomap, evt)
end

# ── FlowLayout ─────────────────────────────────────────────────────────────

function _fl_line_plan(n::Int, child_iomaps::Vector, max_w_cell::Cell, hgap_cell::Cell)
    Cell(function ()
        mw = max_w_cell[]
        hg = hgap_cell[]
        plan = Tuple{Int,Int}[]
        line   = 1
        cursor = 0
        for k in 1:n
            w = _child_w(child_iomaps[k])
            x_in_line = cursor == 0 ? 0 : cursor + hg
            next_cursor = x_in_line + w
            if cursor > 0 && next_cursor > mw
                line += 1
                x_in_line = 0
                next_cursor = w
            end
            push!(plan, (line, x_in_line))
            cursor = next_cursor
        end
        plan
    end)
end

function _fl_line_h(ln::Int, n::Int, child_iomaps::Vector, line_plan::Cell)
    Cell(function ()
        h = 0
        plan = line_plan[]
        for k in 1:n
            plan[k][1] == ln || continue
            ch = _child_h(child_iomaps[k])
            ch > h && (h = ch)
        end
        h
    end)
end

function _fl_line_y(ln::Int, line_h::Vector{Cell}, vgap::Cell)
    Cell(function ()
        y = 0
        for ll in 1:(ln-1)
            y += line_h[ll][] + vgap[]
        end
        y
    end)
end

function _fl_line_w(ln::Int, n::Int, child_iomaps::Vector, line_plan::Cell)
    Cell(function ()
        w = 0
        plan = line_plan[]
        for k in 1:n
            plan[k][1] == ln || continue
            cx = plan[k][2]
            cw = _child_w(child_iomaps[k])
            right = cx + cw
            right > w && (w = right)
        end
        w
    end)
end

function _fl_child_x(i::Int, line_plan::Cell, max_w_cell::Cell,
                    line_w::Vector{Cell}, halign::Cell)
    Cell(function ()
        plan = line_plan[]
        ln, x_in_line = plan[i]
        mw = max_w_cell[]
        lw = line_w[ln][]
        a  = halign[]
        off = a === :center ? div(mw - lw, 2) :
              a === :right  ? mw - lw          :
                              0
        Int32(x_in_line + off)
    end)
end

function _fl_child_y(i::Int, child_iomaps::Vector, line_plan::Cell,
                    line_h::Vector{Cell}, line_y::Vector{Cell}, valign::Cell)
    Cell(function ()
        plan = line_plan[]
        ln, _ = plan[i]
        lh = line_h[ln][]
        ch = _child_h(child_iomaps[i])
        a  = valign[]
        off = a === :center ? div(lh - ch, 2) :
              a === :bottom ? lh - ch         :
                              0
        Int32(line_y[ln][] + off)
    end)
end

function print_document(p::FlowLayoutToGraphicsCanvas,
                          recursion, doc::FlowLayout, ctx)
    n = length(doc.children)
    if n == 0
        return ChildrenIoMap(p, doc, _empty_canvas(), Cell(Tuple{Cell,Cell,Any}[]))
    end

    child_iomaps = Any[]
    for i in 1:n
        cim = _recurse_child(recursion, doc.children[i],
                             make_child_context(ctx, @reference ^(ctx.reference).children[i]))
        push!(child_iomaps, cim)
    end

    max_w_cell = getfield(doc, :max_width)
    hgap_cell  = getfield(doc, :horizontal_gap)
    vgap_cell  = getfield(doc, :vertical_gap)
    halign     = getfield(doc, :horizontal_align)
    valign     = getfield(doc, :vertical_align)

    line_plan = _fl_line_plan(n, child_iomaps, max_w_cell, hgap_cell)

    line_count = Cell(function ()
        plan = line_plan[]
        isempty(plan) ? 0 : plan[end][1]
    end)

    line_h = Cell[]
    line_w = Cell[]
    for ln in 1:n
        push!(line_h, _fl_line_h(ln, n, child_iomaps, line_plan))
        push!(line_w, _fl_line_w(ln, n, child_iomaps, line_plan))
    end

    line_y = Cell[]
    for ln in 1:n
        push!(line_y, _fl_line_y(ln, line_h, vgap_cell))
    end

    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        push!(child_x, _fl_child_x(i, line_plan, max_w_cell, line_w, halign))
        push!(child_y, _fl_child_y(i, child_iomaps, line_plan, line_h, line_y, valign))
    end

    outer_w = Cell(() -> max_w_cell[])
    outer_h = Cell(function ()
        lc = line_count[]
        lc == 0 && return 0
        total = 0
        for ln in 1:lc
            total += line_h[ln][]
        end
        total + max(0, lc - 1) * vgap_cell[]
    end)

    wrapped = Any[]
    for i in 1:n
        c = child_iomaps[i].output
        c isa GraphicsDocument || continue
        push!(wrapped, _wrap_child(c, child_x[i], child_y[i]))
    end

    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(() -> Int32(outer_w[])),
                           Cell(() -> Int32(outer_h[])),
                           CellVector(Cell[Cell(e) for e in wrapped]),
                           layout_none, true, Cell(nothing))

    entries = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(entries, (child_x[i], child_y[i], child_iomaps[i]))
    end

    ChildrenIoMap(p, doc, outer, Cell(entries))
end

function map_reference_forward(::FlowLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::FlowLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::FlowLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_layout_event(iomap, evt)
end

# ── StackLayout ───────────────────────────────────────────────────────────

function _sl_child_x_cell(i::Int, child_iomaps::Vector, outer_w::Cell, halign::Cell)
    Cell(function ()
        cw = _child_w(child_iomaps[i])
        ow = outer_w[]
        a  = halign[]
        x = a === :center ? div(ow - cw, 2) :
            a === :right  ? ow - cw         :
                            0
        Int32(x)
    end)
end

function _sl_child_y_cell(i::Int, child_iomaps::Vector, outer_h::Cell, valign::Cell)
    Cell(function ()
        ch = _child_h(child_iomaps[i])
        oh = outer_h[]
        a  = valign[]
        y = a === :center ? div(oh - ch, 2) :
            a === :bottom ? oh - ch         :
                            0
        Int32(y)
    end)
end

"""Reverse-order hit-test: iterate children from last (top) to first (bottom)."""
function _route_to_children_reverse(child_entries::Vector, x::Int, y::Int, make_evt)
    for i in length(child_entries):-1:1
        entry = child_entries[i]
        entry === nothing && continue
        (ox_cell, oy_cell, cim) = entry::Tuple{Cell,Cell,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        ox = Int(ox_cell[])
        oy = Int(oy_cell[])
        lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
        hit_element_at(canvas, lx, ly) === nothing && continue
        result = read_intent(cim.projection, cim, make_evt(lx, ly))
        result !== nothing && return (result, i)
    end
    nothing
end

_route_scroll_reverse(entries, evt::MouseScroll) =
    _route_to_children_reverse(entries, evt.x, evt.y,
        (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))

_route_click_reverse(entries, evt::MousePress) =
    _route_to_children_reverse(entries, evt.x, evt.y,
        (x, y) -> MousePress(evt.button, x, y, evt.modifiers))

function _route_stack_event(iomap::ChildrenIoMap, evt)
    entries = iomap.child_iomaps[]::Vector
    # Tab traversal: distributed focus advance, handled before the selection-only
    # coordless routing (same as the other layout readers).
    if evt isa KeyDown && evt.key === :tab
        return _layout_tab(iomap.input, entries, evt)
    end
    res = @event_case evt begin
        MousePress  => _route_click_reverse(entries, evt)
        MouseScroll => _route_scroll_reverse(entries, evt)
        _ => begin
            # Selection-only: route the coordless event to the child the
            # selection points at, or nowhere (no broadcast fallback) — selection
            # is authoritative. See documentation/document/widget.md.
            slot = _selected_layout_slot(iomap.input, length(entries))
            slot == 0 ? nothing :
                        _forward_layout_event_slot(entries, evt, slot)
        end
    end
    res === nothing && return nothing
    op, i = res
    reroot_operation(op, (FieldReference("children"), RangeReference(i - 1, i)))
end

function print_document(p::StackLayoutToGraphicsCanvas,
                          recursion, doc::StackLayout, ctx)
    n = length(doc.children)
    if n == 0
        return ChildrenIoMap(p, doc, _empty_canvas(), Cell(Tuple{Cell,Cell,Any}[]))
    end

    halign = getfield(doc, :horizontal_align)
    valign = getfield(doc, :vertical_align)

    child_iomaps = Any[]
    for i in 1:n
        cctx = make_child_context(ctx, @reference ^(ctx.reference).children[i])
        cctx = with_available_size(cctx; width=nothing, height=nothing)
        cim = _recurse_child(recursion, doc.children[i], cctx)
        push!(child_iomaps, cim)
    end

    # `active` (Stage 6 page container): 0 ⇒ z-stack (all children, the original
    # behaviour); i ⇒ show only page i (a QStackedWidget). Visible pages drive the
    # extent, the rendered elements, and event routing — all reactive to `active`.
    active_cell = getfield(doc, :active)
    _visible(a) = a == 0 ? (1:n) : (1 <= a <= n ? (a:a) : (1:0))

    outer_w = Cell(function ()
        w = 0
        for i in _visible(active_cell[])
            cw = _child_w(child_iomaps[i]); cw > w && (w = cw)
        end
        w
    end)

    outer_h = Cell(function ()
        h = 0
        for i in _visible(active_cell[])
            ch = _child_h(child_iomaps[i]); ch > h && (h = ch)
        end
        h
    end)

    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        push!(child_x, _sl_child_x_cell(i, child_iomaps, outer_w, halign))
        push!(child_y, _sl_child_y_cell(i, child_iomaps, outer_h, valign))
    end

    elements_cv = CellVector(() -> begin
        out = Any[]
        for i in _visible(active_cell[])
            c = child_iomaps[i].output
            c isa GraphicsCanvas && push!(out, _wrap_child(c, child_x[i], child_y[i]))
        end
        out
    end)

    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(() -> Int32(outer_w[])),
                           Cell(() -> Int32(outer_h[])),
                           elements_cv,
                           layout_none, true, Cell(nothing))

    entries_cell = Cell(() -> begin
        out = Tuple{Cell,Cell,Any}[]
        for i in _visible(active_cell[])
            push!(out, (child_x[i], child_y[i], child_iomaps[i]))
        end
        out
    end)

    ChildrenIoMap(p, doc, outer, entries_cell)
end

function map_reference_forward(::StackLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::StackLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

function read_intent(::StackLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_stack_event(iomap, evt)
end

# ── ConstraintLayout ───────────────────────────────────────────────────────

# Translate the editable `LayoutRelation` documents into the pure solver's
# plain `SolverRelation`s. Reading the relation/anchor fields here (inside the
# solve cell) registers the reactive dependencies, so editing any constraint
# re-runs the solve.
function _solver_relations(relations_cv)
    rels = SolverRelation[]
    for k in 1:length(relations_cv)
        rel = relations_cv[k]
        terms = Tuple{SolverAnchor,Float64}[]
        rel_terms = rel.terms
        for j in 1:length(rel_terms)
            t = rel_terms[j]
            a = t[1]::LayoutAnchor
            push!(terms, (SolverAnchor(a.child, a.edge), Float64(t[2])))
        end
        push!(rels, SolverRelation(terms, rel.op, Float64(rel.constant), rel.strength))
    end
    rels
end

_cl_pos_cell(solve::Cell, i::Int, k::Int)  = Cell(() -> Int32(solve[][i][k]))  # k = 1 (x) / 2 (y)
_cl_size_cell(solve::Cell, i::Int, k::Int) = Cell(() -> solve[][i][k])         # k = 3 (w) / 4 (h), Int

# Which children have a size axis *explicitly* constrained by some relation, so
# the layout should own that dimension (size-override) rather than leave it
# intrinsic. A relation owns a child's width if it references that child's
# `:width`, `:right`, or `:centerx` (all involve the width variable); height is
# symmetric (`:height`, `:bottom`, `:centery`). Read at build time so editing
# *which* edges a relation references re-projects with the right override set.
function _cl_size_constrained(relations_cv, n::Int)
    xset = falses(n)
    yset = falses(n)
    for k in 1:length(relations_cv)
        rel = relations_cv[k]
        rel_terms = rel.terms
        for j in 1:length(rel_terms)
            a = rel_terms[j][1]::LayoutAnchor
            ci = a.child
            (1 <= ci <= n) || continue
            e = a.edge
            if e === :width || e === :right || e === :centerx
                xset[ci] = true
            elseif e === :height || e === :bottom || e === :centery
                yset[ci] = true
            end
        end
    end
    (xset, yset)
end

# Recompute the whole laid-out constraint layout. Like `_hl_build`, reads
# `doc.children` so the enclosing `build` cell re-runs on structural changes,
# while the per-child position cells and the single `solve` cell stay lazy.
function _cl_build(solver, recursion, doc, ctx)
    n = length(doc.children)

    # ── Pass 1: measure ──────────────────────────────────────────────────
    # Recurse with both available dims stripped to read each child's intrinsic
    # extent. Constraint positions/sizes feed the solve, which reads these
    # extents — a child carrying an available size derived from this layout's
    # own solved output would close a reactive loop, so the measure pass must
    # never see one.
    measure_iomaps = Any[]
    for i in 1:n
        cctx = make_child_context(ctx, @reference ^(ctx.reference).children[i])
        cctx = with_available_size(cctx; width=nothing, height=nothing)
        push!(measure_iomaps, _recurse_child(recursion, doc.children[i], cctx))
    end

    bw_cell = getfield(doc, :bounding_width)
    bh_cell = getfield(doc, :bounding_height)
    relations_cv = doc.relations

    # One reactive cell wrapping the whole LP solve. Re-runs lazily when any
    # child intrinsic extent, any relation, or a bounding dimension changes.
    solve = Cell(function ()
        iw = Int[_child_w(cim) for cim in measure_iomaps]
        ih = Int[_child_h(cim) for cim in measure_iomaps]
        rels = _solver_relations(relations_cv)
        solve_constraint_layout(solver, n, iw, ih, rels, Int(bw_cell[]), Int(bh_cell[]))
    end)

    child_x = Cell[]
    child_y = Cell[]
    sw = Cell[]
    sh = Cell[]
    for i in 1:n
        push!(child_x, _cl_pos_cell(solve, i, 1))
        push!(child_y, _cl_pos_cell(solve, i, 2))
        push!(sw, _cl_size_cell(solve, i, 3))
        push!(sh, _cl_size_cell(solve, i, 4))
    end

    # ── Pass 2: arrange (with size override) ─────────────────────────────
    # Re-project children whose size the layout owns, handing them the solved
    # extent as their available size so content that honors available size
    # reflows to fill its allocation. The available cells read `solve`, which
    # depends only on the measure pass, so this stays cycle-free and a resize
    # propagates through the existing graph without re-projection. Children with
    # no size axis constrained reuse the measure pass unchanged.
    xset, yset = _cl_size_constrained(relations_cv, n)
    final_iomaps = Any[]
    for i in 1:n
        if !xset[i] && !yset[i]
            push!(final_iomaps, measure_iomaps[i])
        else
            cctx = make_child_context(ctx, @reference ^(ctx.reference).children[i])
            cctx = with_available_size(cctx;
                                       width  = xset[i] ? sw[i] : nothing,
                                       height = yset[i] ? sh[i] : nothing)
            push!(final_iomaps, _recurse_child(recursion, doc.children[i], cctx))
        end
    end

    # The container is extrinsically sized when bounding dims are given;
    # otherwise it falls back to the max solved child extent.
    outer_w = Cell(function ()
        bw = Int(bw_cell[])
        bw > 0 && return bw
        s = solve[]
        w = 0
        for i in 1:n
            right = s[i][1] + s[i][3]
            right > w && (w = right)
        end
        w
    end)

    outer_h = Cell(function ()
        bh = Int(bh_cell[])
        bh > 0 && return bh
        s = solve[]
        h = 0
        for i in 1:n
            bottom = s[i][2] + s[i][4]
            bottom > h && (h = bottom)
        end
        h
    end)

    wrapped = Any[]
    for i in 1:n
        c = final_iomaps[i].output
        c isa GraphicsDocument || continue
        push!(wrapped, _wrap_child(c, child_x[i], child_y[i]))
    end

    entries = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(entries, (child_x[i], child_y[i], final_iomaps[i]))
    end

    (wrapped = wrapped, w = outer_w, h = outer_h, entries = entries)
end

function print_document(p::ConstraintLayoutToGraphicsCanvas,
                          recursion, doc::ConstraintLayout, ctx)
    solver = p.solver
    build = Cell(() -> _cl_build(solver, recursion, doc, ctx))
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(() -> Int32(build[].w[])),
                           Cell(() -> Int32(build[].h[])),
                           CellVector(() -> build[].wrapped),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, doc, outer, Cell(() -> build[].entries))
end

function map_reference_forward(::ConstraintLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::ConstraintLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

# Children can overlap (the solver places them freely), so route like a stack:
# scan topmost-first so the last-drawn child wins a click.
function read_intent(::ConstraintLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_stack_event(iomap, evt)
end

# ── Factory ────────────────────────────────────────────────────────────────

"""
    LayoutToGraphics()

A type-dispatching projection that routes any layout document to its
`…ToGraphicsCanvas` projection. Wrap in a `RecursiveProjection` (or
include in a larger dispatcher) so children re-enter the recursion.
"""
function LayoutToGraphics()
    TypeDispatchingProjection(
        HorizontalLayout => HorizontalLayoutToGraphicsCanvas(),
        VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
        GridLayout       => GridLayoutToGraphicsCanvas(),
        FlowLayout       => FlowLayoutToGraphicsCanvas(),
        StackLayout      => StackLayoutToGraphicsCanvas(),
        LayoutConstraint => LayoutConstraintToGraphicsCanvas(),
        ConstraintLayout => ConstraintLayoutToGraphicsCanvas(),
    )
end

end # module
