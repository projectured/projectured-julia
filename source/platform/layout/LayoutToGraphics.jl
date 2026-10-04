# Fragment of `LayoutModule`.
#
# Projections from layout documents (`HorizontalLayout`, `VerticalLayout`,
# `GridLayout`, `FlowLayout`, `StackLayout`) to `GraphicsCanvas`.
#
# Every projection follows the same two-phase shape:
#
# 1. Recurse into each child to obtain a `GraphicsCanvas`.
# 2. Read each child canvas's `w` / `h` cells and wire computed cells
#    for per-child `(x, y)` and the outer canvas's `(w, h)`.
#
# Each child canvas is wrapped in an outer `GraphicsCanvas` at its
# computed `(x, y)`. The resulting per-child position cells are reactive:
# an edit that changes a child's intrinsic extent invalidates only the
# downstream position/extent cells, no re-projection of the layout.
# The focus walk is generic and names no widget type, so layout containers share
# Tab traversal with the widget readers without importing the widget domain.

# ── Projection structs ─────────────────────────────────────────────────────

# A layout that draws a ring around a child selected as a whole holds the values
# of the `GraphicsTheme`, which give the ring. The default is the default theme.
# The field is an `UntrackedCell`, so `LayoutToGraphics(; theme)` gives values
# that read a scaled theme at each read, as the widgets read it.

@projection UntrackedCell struct HorizontalLayoutToGraphicsCanvas
    graphics_style::NamedTuple = get_theme_defaults(GraphicsTheme)
end

@projection UntrackedCell struct VerticalLayoutToGraphicsCanvas
    graphics_style::NamedTuple = get_theme_defaults(GraphicsTheme)
end

@projection UntrackedCell struct GridLayoutToGraphicsCanvas
    graphics_style::NamedTuple = get_theme_defaults(GraphicsTheme)
end

@projection UntrackedCell struct FlowLayoutToGraphicsCanvas
    graphics_style::NamedTuple = get_theme_defaults(GraphicsTheme)
end

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
@projection UntrackedCell struct ConstraintLayoutToGraphicsCanvas
    solver::ConstraintSolver = FallbackConstraintSolver()
    graphics_style::NamedTuple = get_theme_defaults(GraphicsTheme)
end

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
@iomap struct GridLayoutIoMap
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
    clip_child_to_slot(child, iomap; x_cell, y_cell, slot_x, slot_y, slot_w, slot_h,
                       clip_x, clip_y)

A child drawn inside the slot it was allocated, on each axis the slot's extent
was known independently of the child — §3b of the layout rules: the container
that handed out a bounded extent clips to it. On an axis that is the child's
own, the viewport follows the child and clips nothing. The child sits at the
position the alignment gave it, expressed inside the viewport. Every cell is
a `Cell`, so a slot that moves moves the viewport with it. A grid draws its
cells through this, and so does a table whose rows are a list.
"""
function clip_child_to_slot(child::GraphicsDocument, cim; x_cell::Cell, y_cell::Cell,
                            slot_x::Cell, slot_y::Cell, slot_w::Cell, slot_h::Cell,
                            clip_x::Bool, clip_y::Bool)
    vx = clip_x ? slot_x : x_cell
    vy = clip_y ? slot_y : y_cell
    vw = clip_x ? slot_w : Cell(@computation _child_w(cim))
    vh = clip_y ? slot_h : Cell(@computation _child_h(cim))
    inner = GraphicsCanvas(Cell(@computation Int32(Int(x_cell[]) - Int(vx[]))),
                           Cell(@computation Int32(Int(y_cell[]) - Int(vy[]))),
                           Cell(Int32(0)), Cell(Int32(0)),
                           CellVector(Cell[Cell(child)]),
                           layout_none, true, Cell(nothing))
    GraphicsViewport(Cell(@computation Int32(Int(vx[]))), Cell(@computation Int32(Int(vy[]))),
                     Cell(@computation Int32(max(0, Int(vw[])))),
                     Cell(@computation Int32(max(0, Int(vh[])))),
                     Cell(inner))
end

"""
    read_child_event(child_iomap, event) -> operation | nothing

Hand a pointer `event`, already in the child's frame, to the child's reader.
Every container routes a press and a button down to a child through this.

An Alt+press answers with `convert_to_whole_selection`: the child is selected
as a whole unless it selected a whole object inside itself. So the innermost
object under the pointer wins, and a control under it does not act.

A left button down with no modifier on a drawn part of the child answers with
`convert_to_focus_selection`: a focusable child that answers nothing is selected
as a whole, so a key after the click goes to it.

A move of the pointer answers with `read_child_move`: when the child names no
part under the pointer, its own backward map of the point names it, such as a row
of a list, and a child that maps the point to no part is the part itself.

A dwell and a right click that the child does not answer go to the documents
inside it (`read_child_part_gesture`): the part under the point reads its gesture
table, and the documents around it read theirs, out to the child's input. A
container calls this only for the child under the point; the child that the
pointer leaves gets the move through its reader alone (`read_child_leave`), so
it names no part.
"""
function read_child_event(child_iomap, event)
    event isa MouseMove && return read_child_move(child_iomap, event)
    answer = read_intent(child_iomap.projection, child_iomap, event)
    if is_outward_gesture(event) && !(answer isa Operation)
        own = read_child_part_gesture(child_iomap, event)
        own === nothing || (answer = own)
    end
    child = get_iomap_input(child_iomap)
    is_focusing_press(event) && _is_event_on_child(child_iomap, event) &&
        return convert_to_focus_selection(answer, child)
    is_whole_selection_press(event) || return answer
    convert_to_whole_selection(answer, child)
end

# Whether a pointer event in the frame of a child lands on something the child
# drew. A container gives a button down to a child that the pointer does not hit
# when the child holds a drag, and such a down gives the child no focus.
function _is_event_on_child(child_iomap, event)
    canvas = child_iomap.output
    canvas isa GraphicsCanvas && hit_element_at(canvas, event.x, event.y) !== nothing
end

"""
    make_layout_selection_ring(layout, entries, style) -> GraphicsRect

The ring over the child that `layout`'s selection names as a whole
(`children[i]`). `entries()` answers the layout's routing entries, the
`(x, y, child_iomap)` triples of its children in order. A child that takes the
focus gets no ring, because it draws its own focus ring when it is selected.
`style` holds the values of the `GraphicsTheme` that the ring takes.
"""
make_layout_selection_ring(layout, entries::Function, style::NamedTuple) =
    make_selection_ring(() -> _find_whole_selected_child_box(layout, entries()), style)

function _find_whole_selected_child_box(layout, entries)
    i = find_whole_selected_index(layout.selection, "children")
    (i === nothing || !(1 <= i <= length(entries))) && return nothing
    entry = entries[i]
    entry === nothing && return nothing
    (x, y, cim) = entry
    # A control that takes the focus draws its own ring when it is selected.
    is_focusable_document(get_iomap_input(cim)) && return nothing
    child = cim.output
    x0 = child isa GraphicsCanvas ? Int(child.x[]) : 0
    y0 = child isa GraphicsCanvas ? Int(child.y[]) : 0
    (Int(x isa Cell ? x[] : x) + x0, Int(y isa Cell ? y[] : y) + y0, _child_w(cim), _child_h(cim))
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
        point = _find_child_point(entry, x, y; bounded = true)
        point === nothing && continue
        # A position in the answer goes back into this frame by the offset the
        # event came in by.
        result = shift_operation_position(read_child_event(last(entry), make_evt(point...)),
                                          x - point[1], y - point[2])
        result !== nothing && return (result, i)
    end
    nothing
end

# The point `(x, y)` in the frame of a child, when the child drew something
# there, or `nothing`.
#
# A child that is a canvas is hit where it drew an element. `bounded` also keeps
# the hit inside the canvas's own box, so each child owns exactly its laid-out
# box, also where one of its elements draws past it.
#
# A bare graphics document, such as a circle laid out directly, is hit anywhere
# in the box of its size, the box `_child_w` and `_child_h` gave it.
function _find_child_point(entry, x::Int, y::Int; bounded::Bool)
    (ox_cell, oy_cell, cim) = entry::Tuple{Cell,Cell,Any}
    output = cim.output
    ox, oy = Int(ox_cell[]), Int(oy_cell[])
    if output isa GraphicsCanvas
        lx, ly = x - ox - Int(output.x), y - oy - Int(output.y)
        bounded && !(0 <= lx < Int(output.w[]) && 0 <= ly < Int(output.h[])) && return nothing
        hit_element_at(output, lx, ly) === nothing && return nothing
        return (lx, ly)
    end
    output isa GraphicsDocument || return nothing
    lx, ly = x - ox, y - oy
    (w, h) = get_graphics_size(output)
    (0 <= lx < w && 0 <= ly < h) ? (lx, ly) : nothing
end

# A move of the pointer: the child that the pointer leaves, then the child it
# is on (`route` finds that one), each re-rooted into its own `children[i]`.
function _read_layout_move(document, entries::Vector, evt::MouseMove, route)
    new = route(entries, evt)
    new_answer = new === nothing ? nothing : _reroot_into_child(document, new...)
    old = _get_target_layout_slot(document, length(entries))
    (old == 0 || (new !== nothing && new[2] == old) || entries[old] === nothing) &&
        return new_answer
    old_answer = read_child_leave(last(entries[old]), evt, get_child_frame_offset(entries[old])...)
    join_move_answers(_reroot_into_child(document, old_answer, old), new_answer)
end

_route_scroll(entries, evt::MouseScroll) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> MouseScroll(evt.dx, evt.dy, x, y; time = evt.time))

_route_click(entries, evt::MouseClick) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> MouseClick(evt.button, x, y, evt.count, evt.modifiers; time = evt.time))

# A dwell goes to the child at its point, as a click does.
_route_dwell(entries, evt::MouseDwell) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> shift_event_position(evt, x - evt.x, y - evt.y))

# A pointer motion carries coordinates, so it hit-tests the laid-out children like
# a click: it goes to the child under the pointer, not to the selected one.
_route_move(entries, evt::MouseMove) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers; time = evt.time))

# A raw press-down / release also hit-tests by coordinate, so a button laid out in a
# layout flips its `pressed` cell (the depress feedback). The composed MouseClick
# click is routed separately by `_route_click`.
_route_downup(entries, evt) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> evt isa MouseDown ? MouseDown(evt.button, x, y, evt.modifiers;
                                                time = evt.time) :
                                      MouseUp(evt.button, x, y, evt.modifiers;
                                              time = evt.time))

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
_selected_layout_slot(doc, n::Int) =
    hasproperty(doc, :selection) ? _get_children_slot(getfield(doc, :selection)[], n) : 0

# Which child slot the layout's own mouse target names, or 0: the child that the
# pointer was on.
_get_target_layout_slot(doc, n::Int) = _get_children_slot(get_mouse_target(doc), n)

# The slot `i` of a path that begins `children[i]`, or 0.
function _get_children_slot(path, n::Int)
    path isa ConcreteReference || return 0
    (path.head isa FieldReferenceStep && path.head.name == "children") || return 0
    t = path.tail
    (t isa ConcreteReference && t.head isa RangeReferenceStep) || return 0
    slot = t.head.start + 1
    1 <= slot <= n ? slot : 0
end

# Re-root a child's answer into this layout's own `children[i]`, **with the types
# the path needs**.
#
# `reroot_operation` prepends bare steps, and a bare step leaves its node untyped.
# That is invisible until a container one level up splices the answer into an
# `@reference` literal: the literal refuses an untyped node, so a click inside a
# layout threw *under-typed @reference* one projection away from its cause.
# Annotating against the layout document is what fills the types in, and it is
# right by construction because the path resolves against that document.
_reroot_into_child(document, op, index::Integer) =
    _annotate_operation(document, reroot_operation(op, _get_layout_child_steps(index)))

_annotate_operation(::Any, ::Nothing) = nothing
_annotate_operation(::Any, op) = op
_annotate_operation(document, op::ReplacePathOperation) =
    make_path_operation(op, annotate_reference_types(document, get_operation_path(op)))
_annotate_operation(document, op::CompoundOperation) =
    CompoundOperation(Any[_annotate_operation(document, o) for o in op.operations])
_annotate_operation(document, op::WrappingOperation) =
    rewrap_operation(op, _annotate_operation(document, get_wrapped_operation(op)))
function _annotate_operation(document, op::ReplaceReferencedValueOperation)
    # A self-contained operation carries its own root, so this document says
    # nothing about its path.
    op.document === nothing || return op
    ReplaceReferencedValueOperation(nothing,
        annotate_reference_types(document, op.reference), op.value)
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
        sub = reverse ? get_last_focusable_path(w) : get_first_focusable_path(w)
        return sub === nothing ? nothing : ReplaceSelectionOperation(sub)
    end
    deleg = _forward_layout_event_slot(entries, evt, i)
    if deleg !== nothing
        op, slot = deleg
        return _reroot_into_child(w, op, slot)
    end
    j = get_next_focusable_index(w.children, i, reverse)
    j == 0 && return nothing
    sub = reverse ? get_last_focusable_path(w.children[j]) : get_first_focusable_path(w.children[j])
    sub === nothing && return nothing
    _annotate_operation(w, ReplaceSelectionOperation(
        ConcreteReference(FieldReferenceStep("children"),
            ConcreteReference(RangeReferenceStep(j - 1, j), sub))))
end

function _route_layout_event(iomap::_LayoutChildrenIoMap, evt)
    entries = getfield(iomap, :child_iomaps)[]::Vector
    # Tab traversal: distributed focus advance — but only for a Tab nothing
    # wanted. Selection is authoritative for every other coordless event, and a
    # field the caret is in may mean something by Tab: a composer opens its kind
    # chooser with one. Offering it to the selected child first costs a declined
    # read and is what lets a Tab reach a field at all; a child that declines
    # leaves the traversal exactly as it was.
    if evt isa KeyDown && evt.key === :tab
        slot = _selected_layout_slot(iomap.input, length(entries))
        if slot != 0
            taken = _forward_layout_event_slot(entries, evt, slot)
            if taken !== nothing
                op, i = taken
                return _reroot_into_child(iomap.input, op, i)
            end
        end
        return _layout_tab(iomap.input, entries, evt)
    end
    evt isa MouseMove && return _read_layout_move(iomap.input, entries, evt, _route_move)
    res = @gesture_case evt begin
        MouseClick  => _route_click(entries, evt)
        MouseDwell  => _route_dwell(entries, evt)
        MouseScroll => _route_scroll(entries, evt)
        MouseDown   => _route_downup(entries, evt)
        MouseUp     => _route_downup(entries, evt)
        _ => begin
            # Selection-only: route the coordless event to the child the
            # selection points at, or nowhere (no broadcast fallback) — selection
            # is authoritative. See package/visual/doc/widget.md.
            slot = _selected_layout_slot(iomap.input, length(entries))
            slot == 0 ? nothing :
                        _forward_layout_event_slot(entries, evt, slot)
        end
    end
    res === nothing && return read_container_gesture(nothing, evt, iomap.input)
    op, i = res
    read_container_gesture(_reroot_into_child(iomap.input, op, i), evt, iomap.input;
                           steps = _get_layout_child_steps(i))
end

_get_layout_child_steps(i::Integer) =
    (FieldReferenceStep("children"), RangeReferenceStep(i - 1, i))

"""
Recurse into a child document via the dispatcher.
"""
function _recurse_child(recursion, child, ref)
    recursion === nothing && return SimpleIoMap(nothing, child, child)
    return print_child(recursion, child, ref)
end

# A child's intrinsic extent. A laid-out child is normally a `GraphicsCanvas`
# (its `w`/`h` are the authored size). A bare graphics primitive
# (`GraphicsCircle`, `GraphicsLine`, …) reports its size generically via
# `get_graphics_size`, so it can be a layout child directly without being wrapped in
# a sized canvas.
"""
Read `w` from a child iomap's output. Returns 0 when the output isn't
a `GraphicsCanvas` (defensive — the layout still works, just collapses
to the children that are canvases).
"""
function _child_w(cim)
    c = cim.output
    c isa GraphicsCanvas && return Int(c.w[])
    c isa GraphicsDocument && return get_graphics_size(c)[1]
    0
end

function _child_h(cim)
    c = cim.output
    c isa GraphicsCanvas && return Int(c.h[])
    c isa GraphicsDocument && return get_graphics_size(c)[2]
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
    Cell(Computation(function ()
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
        allocate_axis(avail; mins, maxs, prefs, weights = wts, gap, n)
    end))
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
                             make_child_context(ctx, doc, (@reference_step child)))
    output = inner.output isa GraphicsDocument ? inner.output : _empty_canvas()
    ContentIoMap(p, doc, output, inner)
end

# The wrapper forwards the child's canvas as its own output, so the wrapper itself
# is that canvas, and `child` followed by a reference into the child is what the
# child's mapper answers.
function map_reference_forward(::LayoutConstraintToGraphicsCanvas, iomap::ContentIoMap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    h = reference.head
    h isa FieldReferenceStep && h.name == "child" || return nothing
    map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, reference.tail)
end

# The wrapper forwards the child's canvas as its own output, so a path into that
# output is already a path into the child's — there is no step of its own to peel.
function map_reference_backward(::LayoutConstraintToGraphicsCanvas, iomap::ContentIoMap, reference)
    inner = iomap.inner_iomap
    inner === nothing && return nothing
    answer = map_reference_backward(inner.projection, inner, reference)
    answer === nothing && return nothing
    annotate_reference_types(iomap.input, ConcreteReference(FieldReferenceStep("child"), answer))
end

# A path that the child answers continues past the `child` step, as the backward
# map says, with the types that the constraint gives it.
function read_intent(::LayoutConstraintToGraphicsCanvas, iomap::ContentIoMap, evt)
    inner = iomap.inner_iomap
    inner === nothing && return nothing
    answer = read_intent(inner.projection, inner, evt)
    _annotate_operation(iomap.input, reroot_operation(answer, (FieldReferenceStep("child"),)))
end

"""
    make_slot_reference(canvas, entries, index, inner; drawn) -> Reference | Nothing

The output reference of the node that draws the child at `index` of `entries`,
the `(x, y, child_iomap)` triples of a container, followed by `inner`, the
reference that the child's own mapper answered. A child takes a slot among the
drawn children of `canvas`, the container's own canvas, and the slot holds a
wrapper: a canvas that places the child (`_wrap_child`), or a viewport that clips
it (`clip_child_to_slot`), one `content` step deeper. The node of the slot says
which, so this reads that one node of the output. `drawn` is the test that the
container's own build used. The mirror of `_backward_descend`.
"""
function make_slot_reference(canvas, entries::Vector, index::Int, inner::Reference;
                             drawn = output -> output isa GraphicsDocument)
    slot = 0
    for i in 1:index
        child = entries[i][3]
        if child === nothing || !drawn(child.output)
            i == index && return nothing
            continue
        end
        slot += 1
    end
    wrapper = nothing
    elements = unwrap_cell(getfield(unwrap_cell(canvas), :elements))
    1 <= slot <= length(elements) && (wrapper = unwrap_cell(elements[slot]))
    below = ConcreteReference(FieldReferenceStep("elements"),
                              ConcreteReference(RangeReferenceStep(0, 1), inner))
    wrapper isa GraphicsViewport && (below = ConcreteReference(FieldReferenceStep("content"), below))
    ConcreteReference(FieldReferenceStep("elements"),
                      ConcreteReference(RangeReferenceStep(slot - 1, slot), below))
end

"""
    descend_reference_forward(canvas, entries, field, reference; drawn) -> Reference | Nothing

The forward map of a container that addresses its children by an indexed field,
`field[i]` followed by a reference into the child (`children` for a layout): the
child's own mapper answers the rest of the reference, and
[`make_slot_reference`](@ref) puts the node of the child's slot in front of it.
A child that is not drawn has no image. The empty reference is the container
itself, whose image is its own canvas.
"""
function descend_reference_forward(canvas, entries::Vector, field::String, reference;
                                   drawn = output -> output isa GraphicsDocument)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    head = reference.head
    (head isa FieldReferenceStep && head.name == field) || return nothing
    rest = reference.tail
    rest isa ConcreteReference || return nothing
    rest.head isa RangeReferenceStep || return nothing
    index = rest.head.start + 1
    1 <= index <= length(entries) || return nothing
    child = entries[index][3]
    (child === nothing || !drawn(child.output)) && return nothing
    inner = map_reference_forward(child.projection, child, rest.tail)
    inner === nothing && return nothing
    make_slot_reference(canvas, entries, index, inner; drawn)
end

"""
A reference of the form `children[i]/...`, as the output reference of the node
that draws the child, followed by what the child's own mapper answers.
"""
_children_forward(iomap::_LayoutChildrenIoMap, reference,
                  drawn = output -> output isa GraphicsDocument) =
    descend_reference_forward(iomap.output, getfield(iomap, :child_iomaps)[]::Vector,
                              "children", reference; drawn)

# Which child drew the `slot`-th element of the container's own canvas.
#
# A child whose output is not a graphics document draws nothing and takes no slot
# there, so the two indices are not the same number. `drawn` is the test the
# container's own build used — a stack keeps canvases where the others keep
# documents — so the count here matches the one that filled the canvas.
function _drawn_child_index(entries::Vector, slot::Integer, drawn)
    seen = 0
    for i in 1:length(entries)
        iomap = entries[i][3]
        iomap === nothing && continue
        drawn(iomap.output) || continue
        seen += 1
        seen == slot && return i
    end
    0
end

"""
The mirror of `descend_reference_forward`: a path into this container's own canvas, as a
path into the document it printed.

The canvas holds one wrapper per drawn child (`_wrap_child`), and a wrapper holds
that child's canvas as its single element — so the way down is
`elements[slot].elements[1]`, and what is left belongs to the child's own mapper.
A path that stops at the wrapper names the child itself, which is what a click on
a child's area but not on anything inside it should answer.

**The answer is annotated against `document`**, so every node carries its type. A
caller splices this into an `@reference` literal, and that literal refuses a path
with an untyped node — which is how a container that answered an untyped path
showed up: not as a wrong selection, but as a throw one projection higher.
"""
function _backward_descend(document, entries::Vector, field::String, reference, drawn)
    reference isa ConcreteReference || return nothing
    head = reference.head
    (head isa FieldReferenceStep && head.name == "elements") || return nothing
    outer = reference.tail
    outer isa ConcreteReference || return nothing
    outer.head isa RangeReferenceStep || return nothing
    index = _drawn_child_index(entries, outer.head.start + 1, drawn)
    index == 0 && return nothing

    inside = EmptyReference()
    below = outer.tail
    # A clipped child sits behind a viewport, one `content` step deeper than a
    # bare wrapper; the step is skipped so both shapes read the same.
    if below isa ConcreteReference && below.head isa FieldReferenceStep && below.head.name == "content"
        below = below.tail
    end
    if below isa ConcreteReference
        wrapper = below.head
        (wrapper isa FieldReferenceStep && wrapper.name == "elements") || return nothing
        element = below.tail
        element isa ConcreteReference || return nothing
        element.head isa RangeReferenceStep || return nothing
        child = entries[index][3]
        answer = map_reference_backward(child.projection, child, element.tail)
        answer === nothing && return nothing
        inside = answer
    end
    annotate_reference_types(document,
        ConcreteReference(FieldReferenceStep(field),
            ConcreteReference(RangeReferenceStep(index - 1, index), inside)))
end

"""
A path into a layout's canvas, as a path into its `children`. A point of the
canvas maps to the child drawn at it (`_point_backward`).
"""
function _children_backward(iomap::_LayoutChildrenIoMap, reference,
                            drawn = output -> output isa GraphicsDocument;
                            topmost_first::Bool = false)
    entries = getfield(iomap, :child_iomaps)[]::Vector
    point = find_reference_point(reference)
    point === nothing || return _point_backward(iomap.input, entries, point; topmost_first)
    _backward_descend(iomap.input, entries, "children", reference, drawn)
end

"""
A point of a container's canvas, as a path into the document it printed: the
child drawn at the point, and on into that child with the point in the child's
frame. It is the hit test of a pointer event (`_find_child_point`), so a point
maps to the child that a click there reaches. A layout that draws its children
over each other searches from the topmost child down, as its reader does. A child
that maps nothing at its point is itself the part at the point. `steps_of(index)`
names the steps from the document to the child of an entry; by default the
entries are the `children` in order.
"""
function _point_backward(document, entries::Vector, point; topmost_first::Bool = false,
                         steps_of = index -> (FieldReferenceStep("children"),
                                              RangeReferenceStep(index - 1, index)))
    order = topmost_first ? (length(entries):-1:1) : (1:length(entries))
    for index in order
        entry = entries[index]
        entry === nothing && continue
        local_point = _find_child_point(entry, point.x, point.y; bounded = !topmost_first)
        local_point === nothing && continue
        child = entry[3]
        answer = map_reference_backward(child.projection, child, PointReferenceStep(local_point...))
        path = answer === nothing ? EmptyReference() : answer
        for step in Base.reverse(steps_of(index))
            path = ConcreteReference(step, path)
        end
        return annotate_reference_types(document, path)
    end
    nothing
end

# ── Per-cell helpers (a comprehension body cannot hold a begin/end block) ──

function _hl_child_x_cell(i::Int, child_iomaps::Vector, gap_cell::Cell)
    Cell(Computation(function ()
        x = 0
        for j in 1:(i-1)
            x += _child_w(child_iomaps[j]) + gap_cell[]
        end
        Int32(x)
    end))
end

"""Position helper for the main axis when extrinsic allocation is in effect."""
function _hl_alloc_child_x_cell(i::Int, actual_w_cells::Vector{Cell}, gap_cell::Cell)
    Cell(Computation(function ()
        x = 0
        for j in 1:(i-1)
            x += Int(actual_w_cells[j][]) + gap_cell[]
        end
        Int32(x)
    end))
end

"""Position helper for the main axis (y) of a VerticalLayout under extrinsic allocation."""
function _vl_alloc_child_y_cell(i::Int, actual_h_cells::Vector{Cell}, gap_cell::Cell)
    Cell(Computation(function ()
        y = 0
        for j in 1:(i-1)
            y += Int(actual_h_cells[j][]) + gap_cell[]
        end
        Int32(y)
    end))
end

function _hl_child_y_cell(i::Int, child_iomaps::Vector, outer_h::Cell, align_cell::Cell,
                          row_baseline::Cell)
    Cell(Computation(function ()
        ch = _child_h(child_iomaps[i])
        oh = outer_h[]
        a  = align_cell[]
        y = a === :center   ? div(oh - ch, 2) :
            a === :bottom   ? oh - ch         :
            a === :baseline ? row_baseline[] - _child_baseline(child_iomaps[i]) :
                              0
        Int32(y)
    end))
end

# The baseline of a child of a row on the baseline: the baseline of its first line,
# or its bottom edge when it draws no text, as CSS takes it.
_child_baseline(cim) = something(find_first_baseline(cim), _child_h(cim))

function _vl_child_y_cell(i::Int, child_iomaps::Vector, gap_cell::Cell)
    Cell(Computation(function ()
        y = 0
        for j in 1:(i-1)
            y += _child_h(child_iomaps[j]) + gap_cell[]
        end
        Int32(y)
    end))
end

function _vl_child_x_cell(i::Int, child_iomaps::Vector, outer_w::Cell, align_cell::Cell)
    Cell(Computation(function ()
        cw = _child_w(child_iomaps[i])
        ow = outer_w[]
        a  = align_cell[]
        x = a === :center ? div(ow - cw, 2) :
            a === :right  ? ow - cw         :
                            0
        Int32(x)
    end))
end

# ── HorizontalLayout ───────────────────────────────────────────────────────

# Recompute the whole laid-out horizontal row. Like `_vl_build`, reads
# `doc.children` so the enclosing `build` cell re-runs on structural changes,
# while the per-child size/position cells stay lazy.
function _hl_build(recursion, doc, ctx)
    gap_cell   = getfield(doc, :gap)
    align_cell = getfield(doc, :vertical_align)
    n = length(doc.children)

    # Symmetric to VerticalLayout: pass the range on the CROSS axis (height) so
    # children can fill the row's allocation, but give no slot on the MAIN axis
    # (width) — a horizontal row sizes its width from the sum of its children, so
    # a child must not carry a slot that ultimately reads this layout's own outer
    # width (a feedback loop that stack-overflows). A child gets the room the
    # others leave as a bounded range instead (`_main_context`), which reads the
    # parent's edge and the children before it, never `outer_w`. The cross axis
    # is cycle-free: `outer_h` reads child heights while each child reads the
    # parent-supplied edge, never `outer_h`.
    # The mirror of `_vl_build`: a child that carries a weight on the main axis
    # (width, here) asks for a share of this row's width, and can have one only
    # when the row has an edge on that axis, exact or bounded. Only a weighted child is offered a
    # slot, so an unweighted child's width does not depend on the allocation and
    # is safe to read while computing it.
    # The space a row divides is the edge of its range, exact or bounded: `Fill`
    # takes all of what is offered, and the edge is what is offered.
    avail_w  = ctx.maximum_width
    default  = getfield(doc, :child_width)[]
    weighted = [layout_weight(doc.children[i], :x; default) > 0 for i in 1:n]
    filling  = avail_w !== nothing && any(weighted)
    slotted  = [filling && weighted[i] for i in 1:n]

    alloc_cell = Cell(nothing)
    slot_w = Cell[]
    if filling
        for i in 1:n
            push!(slot_w, Cell(@computation begin
                v = alloc_cell[]; v === nothing ? 0 : Int32(v[i])
            end))
        end
    end


    # The CROSS axis carries a policy too, and it is the same one. A child that
    # carries a weight there takes this layout's edge exactly. A child that
    # declares a preferred cross extent gets that number. A child that declares
    # nothing is `Content`, and it draws its content up to the edge — a badge in
    # a column stays badge-shaped, and a paragraph wraps at the column
    # (`make_cross_axis_context`). This is what makes `child_width`/`child_height` mean
    # something on the axis the layout does not divide.
    cross_default = getfield(doc, :child_height)[]

    child_iomaps = Any[]
    for i in 1:n
        child = doc.children[i]
        cctx = make_child_context(ctx, doc, (@reference_step children), (@reference_step [i]))
        cctx = _main_context(cctx, i, doc.children, child_iomaps, slotted, slot_w, :x, default,
                             gap_cell, ctx.maximum_width)
        cctx = make_cross_axis_context(cctx, child, :y, cross_default)
        push!(child_iomaps, _recurse_child(recursion, child, cctx))
    end

    if filling
        set_cell_computation!(alloc_cell, function ()
            mins  = Vector{Int}(undef, n); maxs  = Vector{Int}(undef, n)
            prefs = Vector{Int}(undef, n); wts   = Vector{Float64}(undef, n)
            for i in 1:n
                child     = doc.children[i]
                intrinsic = weighted[i] ? 0 : _child_w(child_iomaps[i])
                mins[i]   = layout_min(child, :x, intrinsic; default)
                maxs[i]   = layout_max(child, :x, intrinsic; default)
                prefs[i]  = layout_preferred(child, :x, intrinsic; default)
                wts[i]    = layout_weight(child, :x; default)
            end
            allocate_axis(Int(avail_w[]); mins, maxs, prefs, weights = wts, gap = gap_cell[], n)
        end)
    end

    # A row on the baseline stands each child so that its baseline meets the
    # lowest baseline of the row; the row is as tall as the lowest child reaches.
    row_baseline = Cell(Computation(function ()
        align_cell[] === :baseline || return 0
        b = 0
        for cim in child_iomaps
            b = max(b, _child_baseline(cim))
        end
        b
    end))
    outer_h = Cell(Computation(function ()
        on_baseline = align_cell[] === :baseline
        h = 0
        for cim in child_iomaps
            ch = _child_h(cim)
            on_baseline && (ch += row_baseline[] - _child_baseline(cim))
            ch > h && (h = ch)
        end
        h
    end))

    # Distributing an offer means occupying it.
    outer_w = filling ? Cell(@computation Int(avail_w[])) : Cell(Computation(function ()
        n2 = length(child_iomaps)
        n2 == 0 && return 0
        total = 0
        for cim in child_iomaps
            total += _child_w(cim)
        end
        total + (n2 - 1) * gap_cell[]
    end))

    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        push!(child_x, _hl_child_x_cell(i, child_iomaps, gap_cell))
        push!(child_y, _hl_child_y_cell(i, child_iomaps, outer_h, align_cell, row_baseline))
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
    # The type of `children` says which layout this is: a list draws the
    # children a viewport shows, a vector draws them all.
    doc.children isa ListNode && return _print_layout_list(p, recursion, doc, ctx, :x)
    build = Cell(@computation _hl_build(recursion, doc, ctx))
    ring = make_layout_selection_ring(doc, () -> build[].entries, p.graphics_style)
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(@computation Int32(build[].w[])),
                           Cell(@computation Int32(build[].h[])),
                           CellVector(@computation vcat(build[].wrapped, Any[ring])),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, doc, outer, Cell(@computation build[].entries))
end

function map_reference_forward(::HorizontalLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

map_reference_backward(::HorizontalLayoutToGraphicsCanvas, iomap, reference) =
    _children_backward(iomap, reference)

function read_intent(::HorizontalLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_layout_event(iomap, evt)
end

# ── VerticalLayout ─────────────────────────────────────────────────────────

# Recompute the whole laid-out vertical stack. Reads `doc.children` (length +
# each child), so the enclosing `build` cell re-runs when the children list
# changes (a part is added/swapped) — that is what makes structure reactive. The
# per-child size/position cells it constructs stay lazy, so a child merely
# *growing* recomputes those cells without rebuilding the stack.
# The range a stack gives a child on the axis it divides.
#
# A weighted child of a stack that distributes takes its slot exactly, and a
# child with a declared preferred extent (`Fixed`) takes that number exactly. Any
# other child — `Content`, or a weighted child of a stack that has no slot to
# divide — draws its content up to the room the others leave: the stack's edge,
# less the gaps, less what the children before it drew, less the minimums of the
# children after it and of the slotted ones, cut at its placement maximum and
# raised to its placement minimum. Each room reads only children that come before
# it, and the allocation reads the unslotted children after they are drawn, so no
# cell reads its own result.
function _main_context(cctx, i::Int, children, child_iomaps, slotted::Vector{Bool},
                       slots::Vector{Cell}, axis::Symbol, default, gap_cell, edge)
    on_axis(range) = axis === :x ? (; width = range) : (; height = range)
    slotted[i] && return with_exact_size(cctx; on_axis(slots[i])...)
    child = children[i]
    pref = layout_preferred(child, axis, 0; default)
    pref > 0 && return with_exact_size(cctx; on_axis(Cell(Int32(pref)))...)
    n = length(children)
    room = edge === nothing ? nothing : Cell(@computation begin
        r = Int(edge[]) - gap_cell[] * (n - 1)
        for j in 1:n
            j == i && continue
            r -= (j < i && !slotted[j]) ?
                 (axis === :x ? _child_w(child_iomaps[j]) : _child_h(child_iomaps[j])) :
                 layout_min(children[j], axis, 0; default)
        end
        Int32(max(0, r))
    end)
    minimum = layout_min(child, axis, 0; default)
    maximum = layout_max(child, axis, 0; default)
    bound = maximum == typemax(Int) ? room :
            room === nothing ? Cell(Int32(maximum)) :
            Cell(@computation Int32(min(Int(room[]), maximum)))
    with_size_range(cctx; on_axis((minimum > 0 ? Cell(Int32(minimum)) : nothing, bound))...)
end

"""
    make_cross_axis_context(cctx, child, axis, default) -> PrinterContext

The context of `child` with the range that a container gives it on an axis
that the container does not divide: the cross axis of a stack, and both axes
of a `WidgetComposite`, whose children overlap.

The edge `B` on that axis is the maximum of the range of `cctx`. `Fill` and
`Relative` take it exactly, `(B, B)`; a declared preferred extent takes that
number exactly; and everything else is `Content`: the child draws its content
up to the edge, `(minᵢ, min(B, maxᵢ))`, from the placement's minimum and
maximum. The policy is the `LayoutConstraint` that `child` is, else `default`,
the container's `child_width` or `child_height` for that axis.

The edge is a cell that the container's parent gave, never the container's own
extent, which is computed from its children, so no child reads a result of its
own.
"""
function make_cross_axis_context(cctx, child, axis::Symbol, default)
    edge = axis === :x ? cctx.maximum_width : cctx.maximum_height
    on_axis(range) = axis === :x ? (; width = range) : (; height = range)
    layout_weight(child, axis; default) > 0 && return with_size_range(cctx; on_axis((edge, edge))...)
    pref = layout_preferred(child, axis, 0; default)
    pref > 0 && return with_exact_size(cctx; on_axis(Cell(Int32(pref)))...)
    minimum = layout_min(child, axis, 0; default)
    maximum = layout_max(child, axis, 0; default)
    bound = maximum == typemax(Int) ? edge :
            edge === nothing ? Cell(Int32(maximum)) :
            Cell(@computation Int32(min(Int(edge[]), maximum)))
    with_size_range(cctx; on_axis((minimum > 0 ? Cell(Int32(minimum)) : nothing, bound))...)
end

function _vl_build(recursion, doc, ctx)
    gap_cell   = getfield(doc, :gap)
    align_cell = getfield(doc, :horizontal_align)
    n = length(doc.children)

    # Pass the range on the CROSS axis (width) so children can fill the layout's
    # allocation or wrap at its edge (responsive cards/text), but give no slot on
    # the MAIN axis (height): a vertical stack sizes its height from the sum of its
    # children, so a child must not carry a slot that ultimately reads this
    # layout's own outer height — that closes a feedback loop and stack-overflows
    # when the reactive cell evaluates. A child gets the room the others leave as
    # a bounded range instead (`_main_context`), which reads the parent's edge and
    # the children before it, never `outer_h`. The cross axis is cycle-free
    # because `outer_w` (below) reads child widths while each child reads the
    # *parent-supplied* edge, never `outer_w`.
    # A child that carries a weight on the main axis is asking for a share of this
    # layout's height. It can have one only when this layout has an edge on that
    # axis, exact or bounded — a share of a sum of its own children is the reactive
    # cycle the comment above describes. So the two conditions together decide, and nothing
    # has to be declared on the layout.
    # The space a column divides is the edge of its range, exact or bounded:
    # `Fill` takes all of what is offered, and the edge is what is offered.
    avail_h  = ctx.maximum_height
    default  = getfield(doc, :child_height)[]
    weighted = [layout_weight(doc.children[i], :y; default) > 0 for i in 1:n]
    filling  = avail_h !== nothing && any(weighted)
    slotted  = [filling && weighted[i] for i in 1:n]

    # The allocation is forward-declared: a weighted child is offered its slot
    # before the slots can be computed, because computing them reads the
    # unweighted children's own heights. `set_cell_computation!` installs the real
    # thunk below and invalidates the slot cells — the order `_split_build` uses.
    #
    # Only a weighted child is offered a slot. Every other child keeps the
    # withheld axis, so its height does not depend on the allocation and reading
    # it to compute the allocation closes no loop.
    alloc_cell = Cell(nothing)
    slot_h = Cell[]
    if filling
        for i in 1:n
            push!(slot_h, Cell(@computation begin
                v = alloc_cell[]; v === nothing ? 0 : Int32(v[i])
            end))
        end
    end


    # The CROSS axis carries a policy too, and it is the same one. A child that
    # carries a weight there takes this layout's edge exactly. A child that
    # declares a preferred cross extent gets that number. A child that declares
    # nothing is `Content`, and it draws its content up to the edge — a badge in
    # a column stays badge-shaped, and a paragraph wraps at the column
    # (`make_cross_axis_context`). This is what makes `child_width`/`child_height` mean
    # something on the axis the layout does not divide.
    cross_default = getfield(doc, :child_width)[]

    child_iomaps = Any[]
    for i in 1:n
        child = doc.children[i]
        cctx = make_child_context(ctx, doc, (@reference_step children), (@reference_step [i]))
        cctx = _main_context(cctx, i, doc.children, child_iomaps, slotted, slot_h, :y, default,
                             gap_cell, ctx.maximum_height)
        cctx = make_cross_axis_context(cctx, child, :x, cross_default)
        push!(child_iomaps, _recurse_child(recursion, child, cctx))
    end

    if filling
        set_cell_computation!(alloc_cell, function ()
            mins  = Vector{Int}(undef, n); maxs  = Vector{Int}(undef, n)
            prefs = Vector{Int}(undef, n); wts   = Vector{Float64}(undef, n)
            for i in 1:n
                child = doc.children[i]
                # A weighted child's preference comes from its constraint, never
                # from what it drew: what it drew came from the slot.
                intrinsic = weighted[i] ? 0 : _child_h(child_iomaps[i])
                mins[i]   = layout_min(child, :y, intrinsic; default)
                maxs[i]   = layout_max(child, :y, intrinsic; default)
                prefs[i]  = layout_preferred(child, :y, intrinsic; default)
                wts[i]    = layout_weight(child, :y; default)
            end
            allocate_axis(Int(avail_h[]); mins, maxs, prefs, weights = wts, gap = gap_cell[], n)
        end)
    end

    outer_w = Cell(Computation(function ()
        w = 0
        for cim in child_iomaps
            cw = _child_w(cim)
            cw > w && (w = cw)
        end
        w
    end))

    # Distributing an offer means occupying it.
    outer_h = filling ? Cell(@computation Int(avail_h[])) : Cell(Computation(function ()
        n2 = length(child_iomaps)
        n2 == 0 && return 0
        total = 0
        for cim in child_iomaps
            total += _child_h(cim)
        end
        total + (n2 - 1) * gap_cell[]
    end))

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
    # The type of `children` says which layout this is: a list draws the
    # children a viewport shows, a vector draws them all.
    doc.children isa ListNode && return _print_layout_list(p, recursion, doc, ctx, :y)
    # A single cell holding the laid-out stack, recomputed when `doc.children`
    # changes. The output canvas, its element list, and the child-routing
    # entries are all derived reactively from it, so adding/removing a child
    # repaints without reprinting the projection (and without `iomap = nothing`).
    build = Cell(@computation _vl_build(recursion, doc, ctx))
    ring = make_layout_selection_ring(doc, () -> build[].entries, p.graphics_style)
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(@computation Int32(build[].w[])),
                           Cell(@computation Int32(build[].h[])),
                           CellVector(@computation vcat(build[].wrapped, Any[ring])),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, doc, outer, Cell(@computation build[].entries))
end

function map_reference_forward(::VerticalLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

map_reference_backward(::VerticalLayoutToGraphicsCanvas, iomap, reference) =
    _children_backward(iomap, reference)

function read_intent(::VerticalLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_layout_event(iomap, evt)
end

# ── GridLayout ─────────────────────────────────────────────────────────────

# Where each child of a grid stands: its row, its column, and the number of
# columns that it takes (`get_column_span`). The grid fills its rows in order. A
# child that takes more columns than its row has left starts the next row, and a
# span past the number of columns takes the whole row. With every span 1, child
# `i` stands at row `div(i - 1, c) + 1` and column `mod(i - 1, c) + 1`.
function _gl_place(spans::Vector{Int}, c::Int)
    c = max(c, 1)
    places = Vector{NTuple{3,Int}}(undef, length(spans))
    row, col = 1, 1
    for (i, span) in enumerate(spans)
        s = min(span, c)
        if col + s - 1 > c
            row += 1
            col = 1
        end
        places[i] = (row, col, s)
        col += s
        if col > c
            row += 1
            col = 1
        end
    end
    places
end

# A child that spans columns adds nothing to the width of a column: it is offered
# the width of the columns that it spans, and breaks its lines there.
function _gl_col_w_cell(col::Int, child_iomaps::Vector, places::Cell)
    Cell(Computation(function ()
        w = 0
        for (k, (_, child_col, span)) in enumerate(places[])
            if child_col == col && span == 1
                cw = _child_w(child_iomaps[k])
                cw > w && (w = cw)
            end
        end
        w
    end))
end

function _gl_row_h_cell(row::Int, child_iomaps::Vector, places::Cell)
    Cell(Computation(function ()
        h = 0
        for (k, (child_row, _, _)) in enumerate(places[])
            if child_row == row
                ch = _child_h(child_iomaps[k])
                ch > h && (h = ch)
            end
        end
        h
    end))
end

# The width of the columns that child `i` spans, with the gaps between them: the
# width of its column for a child that spans one.
function _gl_span_w_cell(i::Int, places::Cell, col_w::Vector{Cell}, hgap::Cell)
    Cell(Computation(function ()
        _, col, span = places[][i]
        last_col = min(col + span - 1, length(col_w))
        total = 0
        for k in col:last_col
            total += Int(col_w[k][])
        end
        total + max(0, last_col - col) * Int(hgap[])
    end))
end

# The edge of column `col` and of row `row`: the shared sum over the extents
# before it, read reactively so an earlier extent that grows moves the edge.
function _gl_col_x_cell(col::Int, col_w::Vector{Cell}, hgap::Cell)
    Cell(@computation last(compute_axis_offsets(Int[Int(col_w[cc][]) for cc in 1:(col-1)], Int(hgap[]))))
end

# The top of row `row`: the rows above it, and the gap above each row after the
# first (`gap_above`).
function _gl_row_y_cell(row::Int, row_h::Vector{Cell}, gap_above)
    Cell(Computation(function ()
        y = 0
        for rr in 1:(row - 1)
            y += Int(row_h[rr][]) + gap_above(rr + 1)
        end
        y
    end))
end

# Per-column alignment. An empty vector falls back to the single
# `horizontal_align`.
_col_align(v, col::Int, default::Symbol) =
    (v isa AbstractVector && 1 <= col <= length(v)) ? Symbol(v[col]) : default

# The policy of one column or one row: the vector's entry when it has one, and
# the grid's own default when it does not.
_gl_policy_at(v, i::Int, default) =
    (v isa AbstractVector && 1 <= i <= length(v) && v[i] isa SizePolicy) ? v[i] : default

# The policy of a column or a row on an axis that the grid was `offered` an
# extent on, or not. A weighted one with no offer has no share to take, so it
# takes the extent of its cells, as a weighted child of a stack does: it acts as
# `Content` and keeps its minimum and its maximum. So a `Fill` column fills a
# pane, and keeps the width of its cells where nothing is offered.
_gl_unoffered_policy(p::SizePolicy, offered::Bool) =
    (offered || p.weight === nothing || p.weight <= 0) ? p : SizePolicy(p.min, nothing, p.max, 0.0)

# The four allocator inputs of one column or one row.
#
# `content` is what its cells measured, and it is passed as `0` for an item that
# offers its extent to its cells — see `_gl_extents_cell` for why that item's
# cells are never read here. A policy with no minimum takes the content as its
# minimum, so a weighted item whose cells were read is at least as wide as they
# are; `Fill` and `Relative` say a minimum of 0 and keep it.
function _gl_axis_inputs(p::SizePolicy, content::Int)
    weight = p.weight === nothing ? 0.0 : Float64(p.weight)
    pref   = p.preferred === nothing ? content : Int(p.preferred)
    lo     = p.min === nothing ? content : Int(p.min)
    hi     = p.max === nothing ? typemax(Int) : Int(p.max)
    (lo, hi, pref, weight)
end

# Whether a column or a row may hand its extent to its cells.
#
# A weighted one is given a slot and a `Fixed` one was told a number, so neither
# extent comes from the cells and both are safe to offer. A `Content` one IS its
# cells, so §3 says it offers nothing.
_gl_offers(p::SizePolicy) =
    (p.weight !== nothing && p.weight > 0) || p.preferred !== nothing

# The laid-out extent of every column, or of every row, allocated in one pass.
#
# An item that is NOT offered its extent keeps what its cells measured, and that
# is read here because it does not depend on the allocation.
#
# **The cells of an item that IS offered are never read.** That is every item
# `_gl_offers` answers true for, and it is not only the weighted ones: a
# `Fixed(n)` column is told `n` and hands `n` to its cells, so reading those
# cells here would make its width depend on itself. A stack overflow is what a
# closed cycle looks like, and `Fixed` is what produced one.
#
# `reads(k)` says whether item k's cells may be read. By default that is every
# item that does not offer its extent; a grid whose caller withheld a column's
# offer (a table whose cells clip) reads that column too, weighted or not.
#
# `allocate_axis` is the same allocator the stacks and the split use.
function _gl_extents_cell(count_cell, policy_of, content::Vector{Cell},
                          gap::Cell, avail; reads = k -> !_gl_offers(policy_of(k)),
                          extra_gap = c -> 0)
    Cell(Computation(function ()
        c = count_cell[]
        c <= 0 && return Int[]
        c = min(c, length(content))
        mins = Vector{Int}(undef, c); maxs = Vector{Int}(undef, c)
        prefs = Vector{Int}(undef, c); wts = Vector{Float64}(undef, c)
        weighted = false
        for k in 1:c
            policy = policy_of(k)
            w = policy.weight === nothing ? 0.0 : Float64(policy.weight)
            w > 0 && (weighted = true)
            (mins[k], maxs[k], prefs[k], wts[k]) =
                _gl_axis_inputs(policy, reads(k) ? content[k][] : 0)
        end
        (avail === nothing || !weighted) && return Int[clamp(prefs[k], mins[k], maxs[k]) for k in 1:c]
        # `extra_gap(c)` is what the gaps of the items differ from `c - 1` gaps of
        # `gap`, so a weighted item shares what the gaps leave.
        allocate_axis(Int(avail[]) - extra_gap(c); mins, maxs, prefs, weights = wts,
                      gap = gap[], n = c)
    end))
end

# An offer is carried as an `Int32` cell, the way every other seeded extent is.
_gl_int32_cell(extent::Cell) = Cell(@computation Int32(max(0, extent[])))

# One entry of what `_gl_extents_cell` allocated.
_gl_extent_cell(extents, k::Int) =
    Cell(Computation(function ()
        e = extents[]
        k <= length(e) ? e[k] : 0
    end))

function _gl_child_x(i::Int, child_iomaps::Vector, places::Cell, span_w::Vector{Cell},
                     col_x::Vector{Cell}, halign::Cell, column_align_cell::Cell)
    Cell(Computation(function ()
        _, col, _ = places[][i]
        cw = _child_w(child_iomaps[i])
        cellw = span_w[i][]
        a = _col_align(column_align_cell[], col, halign[])
        # A cell wider than its column starts at its left edge, whatever its
        # alignment, so a column that clips it shows its start, as the grid of a
        # list does.
        off = a === :center ? max(0, div(cellw - cw, 2)) :
              a === :right  ? max(0, cellw - cw)         :
                              0
        Int32(col_x[col][] + off)
    end))
end

function _gl_child_y(i::Int, child_iomaps::Vector, places::Cell,
                     row_h::Vector{Cell}, row_y::Vector{Cell}, valign::Cell)
    Cell(Computation(function ()
        row, _, _ = places[][i]
        ch = _child_h(child_iomaps[i])
        cellh = row_h[row][]
        a = valign[]
        # A cell taller than its row starts at its top edge, as across.
        off = a === :center ? max(0, div(cellh - ch, 2)) :
              a === :bottom ? max(0, cellh - ch)         :
                              0
        Int32(row_y[row][] + off)
    end))
end

function print_document(p::GridLayoutToGraphicsCanvas,
                          recursion, doc::GridLayout, ctx)
    # The type of `children` says which grid this is: a list of rows draws the
    # rows a viewport shows, a vector of cells draws them all. `nothing` is a
    # list with no rows, which can hold rows later.
    (doc.children isa ListNode || doc.children === nothing) &&
        return _print_grid_list(p, recursion, doc, ctx)
    n = length(doc.children)
    if n == 0
        return GridLayoutIoMap(p, doc, _empty_canvas(), Cell(Tuple{Cell,Cell,Any}[]),
                               Cell[], Cell[], Cell[], Cell[],
                               getfield(doc, :columns), Cell(0),
                               getfield(doc, :horizontal_gap), getfield(doc, :vertical_gap),
                               Cell(Int32(0)), Cell(Int32(0)))
    end

    cols_cell = getfield(doc, :columns)
    hgap      = getfield(doc, :horizontal_gap)
    vgap      = getfield(doc, :vertical_gap)
    halign    = getfield(doc, :horizontal_align)
    valign    = getfield(doc, :vertical_align)
    column_align_cell = getfield(doc, :column_align)
    avail_w = ctx === nothing ? nothing : get_exact_width(ctx)
    avail_h = ctx === nothing ? nothing : get_exact_height(ctx)

    # A column's and a row's policy. Its KIND — `Fixed`, a weight or `Content` —
    # decides what a cell is offered, and that is read when the grid prints,
    # with no dependency: a caller says what a column is when it builds the
    # grid. Its NUMBERS are read inside the extent cells, so a policy that is a
    # computed cell — a header row that takes the widths of the grid under it —
    # follows what it reads, and a new number does not print the grid again.
    #
    # A weighted column or row on an axis that the grid was offered no extent on
    # has no share to take, so it takes the extent of its cells
    # (`_gl_unoffered_policy`).
    offered_w, offered_h = avail_w !== nothing, avail_h !== nothing
    policy_of_column(k::Int) =
        _gl_unoffered_policy(_gl_policy_at(doc.column_policies, k, doc.column_policy), offered_w)
    policy_of_row(k::Int) =
        _gl_unoffered_policy(_gl_policy_at(doc.row_policies, k, doc.row_policy), offered_h)
    peek_column_policy(k::Int) =
        _gl_unoffered_policy(_gl_policy_at(peek(getfield(doc, :column_policies)), k,
                                           peek(getfield(doc, :column_policy))), offered_w)
    peek_row_policy(k::Int) =
        _gl_unoffered_policy(_gl_policy_at(peek(getfield(doc, :row_policies)), k,
                                           peek(getfield(doc, :row_policy))), offered_h)
    # A column that was given an extent hands it to its cells unless the grid
    # was told not to for that column; a column that was not given one has
    # nothing to hand out either way.
    column_offers = doc.column_offers
    offers_to_cells(k::Int) = _gl_offers(peek_column_policy(k)) &&
        !(column_offers isa AbstractVector && k <= length(column_offers) && column_offers[k] === false)
    row_offers = doc.row_offers
    offers_to_row_cells(k::Int) = _gl_offers(peek_row_policy(k)) &&
        !(row_offers isa AbstractVector && k <= length(row_offers) && row_offers[k] === false)

    # Up to n columns and n rows — one child per column, or one column of n.
    #
    # The extents are built BEFORE the children, because a weighted column or row
    # offers its slot to the cells in it. They read `child_iomaps` lazily, and the
    # loop below fills that vector; nothing forces an extent while it runs.
    child_iomaps = Any[]
    # Where each child stands. The spans are read once here, as the children are.
    spans = Int[get_column_span(doc.children[i]) for i in 1:n]
    places = Cell(@computation _gl_place(spans, cols_cell[]))
    row_count_cell = Cell(Computation(function ()
        p = places[]
        isempty(p) ? 0 : maximum(first, p)
    end))
    content_col_w = Cell[]
    content_row_h = Cell[]
    for k in 1:n
        push!(content_col_w, _gl_col_w_cell(k, child_iomaps, places))
        push!(content_row_h, _gl_row_h_cell(k, child_iomaps, places))
    end
    col_extents = _gl_extents_cell(cols_cell, policy_of_column, content_col_w, hgap, avail_w;
                                   reads = k -> !offers_to_cells(k))
    # The gap above row `r`: its entry of `row_gaps`, or `vertical_gap`.
    function gap_above(r::Int)
        gaps = doc.row_gaps
        gap = gaps isa AbstractVector && 2 <= r <= length(gaps) ? gaps[r] : nothing
        gap === nothing ? Int(vgap[]) : Int(gap)
    end
    row_extents = _gl_extents_cell(row_count_cell, policy_of_row, content_row_h, vgap, avail_h;
                                   reads = k -> !offers_to_row_cells(k),
                                   extra_gap = c -> sum((gap_above(r) - Int(vgap[]) for r in 2:c); init = 0))
    col_w = Cell[_gl_extent_cell(col_extents, k) for k in 1:n]
    row_h = Cell[_gl_extent_cell(row_extents, k) for k in 1:n]

    # The edge of a `Content` column: the grid's edge, less the gaps, less what
    # the `Content` columns before it drew, less the minimums of the other
    # columns. It reads only columns that come before it, and nothing forces it
    # while the cells are printed. A sized column that keeps its extent from its
    # cells (`column_offers`) clips them instead, and gives them no edge.
    is_content_column(k::Int) = !_gl_offers(peek_column_policy(k))
    edge_w = ctx === nothing ? nothing : ctx.maximum_width
    function make_column_edge(col::Int)
        edge_w === nothing && return nothing
        Cell(@computation begin
            c = cols_cell[]
            r = Int(edge_w[]) - Int(hgap[]) * max(0, c - 1)
            for k in 1:c
                k == col && continue
                r -= (k < col && is_content_column(k)) ? Int(content_col_w[k][]) :
                     something(policy_of_column(k).min, 0)
            end
            Int32(max(0, r))
        end)
    end
    column_edges = Union{Nothing,Cell}[make_column_edge(col) for col in 1:n]
    span_w = Cell[_gl_span_w_cell(i, places, col_w, hgap) for i in 1:n]
    col_x = Cell[_gl_col_x_cell(k, col_w, hgap) for k in 1:n]
    # The columns that child `i` spans, at the column count of this print.
    places_now = places[]
    spanned_columns(i::Int) = places_now[i][2]:min(places_now[i][2] + places_now[i][3] - 1, n)
    # A spanning child reaches from its first column to the edge of the grid, and
    # at least over the columns that it spans: it widens no column, and a text in
    # it breaks at the width that the grid was offered. A grid offered no width
    # gives it no edge, and it draws as wide as it measures.
    function make_span_edge(i::Int)
        edge_w === nothing && return nothing
        col = places_now[i][2]
        Cell(@computation Int32(max(Int(span_w[i][]), Int(edge_w[]) - Int(col_x[col][]))))
    end

    # What each cell is given. A column or a row that may hand out its extent
    # gives it exactly — §3, and §4's rule that only a weighted item is given a
    # slot. A `Content` column gives its cells its edge, so a cell draws its
    # content up to it; a row that does not hand out its extent keeps the height
    # free, because no content reflows with its height. A child that spans
    # columns is given their width exactly when each of them hands out its
    # extent, and as a bound otherwise.
    for i in 1:n
        row, col, span = places_now[i]
        cctx = ctx
        if cctx !== nothing
            cctx = span > 1 ?
                       (all(offers_to_cells, spanned_columns(i)) ?
                            with_exact_size(cctx; width = _gl_int32_cell(span_w[i])) :
                            with_bounded_size(cctx; width = make_span_edge(i))) :
                   offers_to_cells(col) ? with_exact_size(cctx; width = _gl_int32_cell(col_w[col])) :
                   is_content_column(col) ? with_bounded_size(cctx; width = column_edges[col]) :
                   with_free_axis(cctx, :x)
            cctx = offers_to_row_cells(row) ?
                with_exact_size(cctx; height = _gl_int32_cell(row_h[row])) :
                with_free_axis(cctx, :y)
        end
        cim = _recurse_child(recursion, doc.children[i],
                             make_child_context(cctx, doc, (@reference_step children), (@reference_step [i])))
        push!(child_iomaps, cim)
    end

    row_y = Cell[]
    for k in 1:n
        push!(row_y, _gl_row_y_cell(k, row_h, gap_above))
    end

    child_x = Cell[]
    child_y = Cell[]
    for i in 1:n
        push!(child_x, _gl_child_x(i, child_iomaps, places, span_w, col_x, halign, column_align_cell))
        push!(child_y, _gl_child_y(i, child_iomaps, places, row_h, row_y, valign))
    end

    # The grid is as wide as its columns, and as wide as a spanning child that
    # reaches past them.
    spanning = [i for i in 1:n if places_now[i][3] > 1]
    outer_w = Cell(Computation(function ()
        c = cols_cell[]
        total = 0
        for cc in 1:c
            total += col_w[cc][]
        end
        total += max(0, c - 1) * hgap[]
        for i in spanning
            total = max(total, Int(col_x[places_now[i][2]][]) + _child_w(child_iomaps[i]))
        end
        total
    end))

    outer_h = Cell(Computation(function ()
        nrows = row_count_cell[]
        total = 0
        for rr in 1:nrows
            total += row_h[rr][]
            rr > 1 && (total += gap_above(rr))
        end
        total
    end))

    # A child in a column or a row whose extent was given is drawn inside that
    # slot; every other child is drawn where the alignment put it and reaches as
    # far as it reaches. The column count is read once here: a grid whose column
    # count changes is rebuilt by the cell around this function.
    wrapped = Any[]
    for i in 1:n
        c = child_iomaps[i].output
        c isa GraphicsDocument || continue
        row, col, span = places_now[i]
        clip_x = all(k -> _gl_offers(peek_column_policy(k)), spanned_columns(i))
        clip_y = _gl_offers(peek_row_policy(row))
        if clip_x || clip_y
            push!(wrapped, clip_child_to_slot(c, child_iomaps[i]; x_cell = child_x[i],
                                              y_cell = child_y[i], slot_x = col_x[col],
                                              slot_y = row_y[row],
                                              slot_w = span > 1 ? span_w[i] : col_w[col],
                                              slot_h = row_h[row], clip_x, clip_y))
        else
            push!(wrapped, _wrap_child(c, child_x[i], child_y[i]))
        end
    end

    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(@computation Int32(outer_w[])),
                           Cell(@computation Int32(outer_h[])),
                           CellVector(Cell[Cell(e) for e in wrapped]),
                           layout_none, true, Cell(nothing))

    entries = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(entries, (child_x[i], child_y[i], child_iomaps[i]))
    end
    push!(outer.elements, make_layout_selection_ring(doc, () -> entries, p.graphics_style))

    row_count = row_count_cell

    GridLayoutIoMap(p, doc, outer, Cell(entries),
                    col_x, row_y, col_w, row_h,
                    cols_cell, row_count, hgap, vgap,
                    Cell(@computation Int32(outer_w[])), Cell(@computation Int32(outer_h[])))
end

function map_reference_forward(::GridLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

map_reference_backward(::GridLayoutToGraphicsCanvas, iomap, reference) =
    _children_backward(iomap, reference)

# A grid holds its cells in entries of a place and an IoMap, so a route reaches
# the cell it names through the kernel's default reader.
ProjectionModule.get_child_iomaps(iomap::GridLayoutIoMap) =
    Any[last(entry) for entry in iomap.child_iomaps
        if entry isa Tuple && !isempty(entry) && last(entry) isa IoMap]

function read_intent(::GridLayoutToGraphicsCanvas, iomap::GridLayoutIoMap, evt)
    _route_layout_event(iomap, evt)
end

# ── FlowLayout ─────────────────────────────────────────────────────────────

function _fl_line_plan(n::Int, child_iomaps::Vector, max_w_cell::Cell, hgap_cell::Cell)
    Cell(Computation(function ()
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
    end))
end

function _fl_line_h(ln::Int, n::Int, child_iomaps::Vector, line_plan::Cell)
    Cell(Computation(function ()
        h = 0
        plan = line_plan[]
        for k in 1:n
            plan[k][1] == ln || continue
            ch = _child_h(child_iomaps[k])
            ch > h && (h = ch)
        end
        h
    end))
end

function _fl_line_y(ln::Int, line_h::Vector{Cell}, vgap::Cell)
    Cell(Computation(function ()
        y = 0
        for ll in 1:(ln-1)
            y += line_h[ll][] + vgap[]
        end
        y
    end))
end

function _fl_line_w(ln::Int, n::Int, child_iomaps::Vector, line_plan::Cell)
    Cell(Computation(function ()
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
    end))
end

function _fl_child_x(i::Int, line_plan::Cell, outer_w::Cell,
                    line_w::Vector{Cell}, halign::Cell)
    Cell(Computation(function ()
        plan = line_plan[]
        ln, x_in_line = plan[i]
        ow = outer_w[]
        lw = line_w[ln][]
        a  = halign[]
        off = a === :center ? div(ow - lw, 2) :
              a === :right  ? ow - lw          :
                              0
        Int32(x_in_line + off)
    end))
end

function _fl_child_y(i::Int, child_iomaps::Vector, line_plan::Cell,
                    line_h::Vector{Cell}, line_y::Vector{Cell}, valign::Cell)
    Cell(Computation(function ()
        plan = line_plan[]
        ln, _ = plan[i]
        lh = line_h[ln][]
        ch = _child_h(child_iomaps[i])
        a  = valign[]
        off = a === :center ? div(lh - ch, 2) :
              a === :bottom ? lh - ch         :
                              0
        Int32(line_y[ln][] + off)
    end))
end

function print_document(p::FlowLayoutToGraphicsCanvas,
                          recursion, doc::FlowLayout, ctx)
    # Rebuild children + geometry inside one build cell (the H/V/Constraint sibling
    # pattern) so a structural edit to `doc.children` re-flows; the outer canvas's
    # extent + membership derive from `build[]` (PAR-STABLE-IOMAP-IDENTITY).
    # A flow's children are their content on both axes — a line is as tall as
    # its tallest child and holds as many as fit — so neither extent is offered
    # to them. The flow breaks its lines at `max_width`, or at the edge of the
    # range it was given when that is less: a flow in a card breaks at the card's
    # edge.
    child_ctx = ctx === nothing ? nothing : with_free_axis(with_free_axis(ctx, :x), :y)
    edge_w = ctx === nothing ? nothing : ctx.maximum_width
    minimum_w = ctx === nothing ? nothing : ctx.minimum_width
    build = Cell(@computation begin
        n = length(doc.children)
        child_iomaps = Any[]
        for i in 1:n
            cim = _recurse_child(recursion, doc.children[i],
                                 make_child_context(child_ctx, doc, (@reference_step children), (@reference_step [i])))
            push!(child_iomaps, cim)
        end
        # The break width: the smaller of `max_width` and the edge, and a width no
        # line reaches when the flow has neither.
        authored_w = getfield(doc, :max_width)
        max_w_cell = Cell(@computation begin
            authored = authored_w[]
            limit = authored === nothing ? Int(typemax(Int32)) : Int(authored)
            edge_w === nothing ? limit : min(limit, max(0, Int(edge_w[])))
        end)
        hgap_cell  = getfield(doc, :horizontal_gap)
        vgap_cell  = getfield(doc, :vertical_gap)
        halign     = getfield(doc, :horizontal_align)
        valign     = getfield(doc, :vertical_align)
        line_plan = _fl_line_plan(n, child_iomaps, max_w_cell, hgap_cell)
        line_count = Cell(Computation(function ()
            plan = line_plan[]
            isempty(plan) ? 0 : plan[end][1]
        end))
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
        # The flow draws its widest line, and at least the minimum of its range,
        # cut at `max_width`: the edge of an exact range, its content in a
        # bounded or a free one.
        outer_w = Cell(@computation begin
            widest = 0
            for ln in 1:line_count[]
                widest = max(widest, line_w[ln][])
            end
            minimum = minimum_w === nothing ? nothing : minimum_w[]
            authored = authored_w[]
            minimum isa Integer || return widest
            max(widest, authored === nothing ? Int(minimum) : min(Int(minimum), Int(authored)))
        end)
        child_x = Cell[]
        child_y = Cell[]
        for i in 1:n
            push!(child_x, _fl_child_x(i, line_plan, outer_w, line_w, halign))
            push!(child_y, _fl_child_y(i, child_iomaps, line_plan, line_h, line_y, valign))
        end
        outer_h = Cell(Computation(function ()
            lc = line_count[]
            lc == 0 && return 0
            total = 0
            for ln in 1:lc
                total += line_h[ln][]
            end
            total + max(0, lc - 1) * vgap_cell[]
        end))
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
    end)
    ring = make_layout_selection_ring(doc, () -> build[].entries, p.graphics_style)
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(@computation Int32(build[].w[])),
                           Cell(@computation Int32(build[].h[])),
                           CellVector(@computation vcat(build[].wrapped, Any[ring])),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, doc, outer, Cell(@computation build[].entries))
end

function map_reference_forward(::FlowLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

map_reference_backward(::FlowLayoutToGraphicsCanvas, iomap, reference) =
    _children_backward(iomap, reference)

function read_intent(::FlowLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_layout_event(iomap, evt)
end

# ── StackLayout ───────────────────────────────────────────────────────────

function _sl_child_x_cell(i::Int, child_iomaps::Vector, outer_w::Cell, halign::Cell)
    Cell(Computation(function ()
        cw = _child_w(child_iomaps[i])
        ow = outer_w[]
        a  = halign[]
        x = a === :center ? div(ow - cw, 2) :
            a === :right  ? ow - cw         :
                            0
        Int32(x)
    end))
end

function _sl_child_y_cell(i::Int, child_iomaps::Vector, outer_h::Cell, valign::Cell)
    Cell(Computation(function ()
        ch = _child_h(child_iomaps[i])
        oh = outer_h[]
        a  = valign[]
        y = a === :center ? div(oh - ch, 2) :
            a === :bottom ? oh - ch         :
                            0
        Int32(y)
    end))
end

"""Reverse-order hit-test: iterate children from last (top) to first (bottom)."""
function _route_to_children_reverse(child_entries::Vector, x::Int, y::Int, make_evt)
    for i in length(child_entries):-1:1
        entry = child_entries[i]
        entry === nothing && continue
        point = _find_child_point(entry, x, y; bounded = false)
        point === nothing && continue
        # A position in the answer goes back into this frame by the offset the
        # event came in by.
        result = shift_operation_position(read_child_event(last(entry), make_evt(point...)),
                                          x - point[1], y - point[2])
        result !== nothing && return (result, i)
    end
    nothing
end

_route_scroll_reverse(entries, evt::MouseScroll) =
    _route_to_children_reverse(entries, evt.x, evt.y,
        (x, y) -> MouseScroll(evt.dx, evt.dy, x, y; time = evt.time))

_route_click_reverse(entries, evt::MouseClick) =
    _route_to_children_reverse(entries, evt.x, evt.y,
        (x, y) -> MouseClick(evt.button, x, y, evt.count, evt.modifiers; time = evt.time))

_route_move_reverse(entries, evt::MouseMove) =
    _route_to_children_reverse(entries, evt.x, evt.y,
        (x, y) -> MouseMove(x, y, evt.buttons, evt.modifiers; time = evt.time))

function _route_stack_event(iomap::ChildrenIoMap, evt)
    entries = getfield(iomap, :child_iomaps)[]::Vector
    # Tab traversal: distributed focus advance, handled before the selection-only
    # coordless routing (same as the other layout readers).
    if evt isa KeyDown && evt.key === :tab
        return _layout_tab(iomap.input, entries, evt)
    end
    evt isa MouseMove &&
        return _read_layout_move(iomap.input, entries, evt, _route_move_reverse)
    res = @gesture_case evt begin
        MouseClick  => _route_click_reverse(entries, evt)
        MouseScroll => _route_scroll_reverse(entries, evt)
        _ => begin
            # Selection-only: route the coordless event to the child the
            # selection points at, or nowhere (no broadcast fallback) — selection
            # is authoritative. See package/visual/doc/widget.md.
            slot = _selected_layout_slot(iomap.input, length(entries))
            slot == 0 ? nothing :
                        _forward_layout_event_slot(entries, evt, slot)
        end
    end
    res === nothing && return nothing
    op, i = res
    _reroot_into_child(iomap.input, op, i)
end

function print_document(p::StackLayoutToGraphicsCanvas,
                          recursion, doc::StackLayout, ctx)
    halign = getfield(doc, :horizontal_align)
    valign = getfield(doc, :vertical_align)
    active_cell = getfield(doc, :active)
    _visible(a, n) = a == 0 ? (1:n) : (1 <= a <= n ? (a:a) : (1:0))

    # Rebuild the child iomaps on a structural edit to `doc.children` (a stack's
    # pages can be added/removed), so a child add/remove reflows. `active` /
    # child-size changes flow through the cells below without re-entering this.
    build = Cell(@computation begin
        n = length(doc.children)
        cims = Any[]
        for i in 1:n
            cctx = with_exact_size(
                make_child_context(ctx, doc, (@reference_step children), (@reference_step [i]));
                width=nothing, height=nothing)
            push!(cims, _recurse_child(recursion, doc.children[i], cctx))
        end
        (n, cims)
    end)

    # `active` (Stage 6 page container): 0 ⇒ z-stack (all children); i ⇒ only page i
    # (a QStackedWidget). Visible pages drive the extent, elements and event routing.
    outer_w = Cell(Computation(function ()
        (n, cims) = build[]
        w = 0
        for i in _visible(active_cell[], n)
            cw = _child_w(cims[i]); cw > w && (w = cw)
        end
        w
    end))
    outer_h = Cell(Computation(function ()
        (n, cims) = build[]
        h = 0
        for i in _visible(active_cell[], n)
            ch = _child_h(cims[i]); ch > h && (h = ch)
        end
        h
    end))

    # Per-child position cells; rebuilt only on a structural change (they capture
    # `outer_w`/`outer_h` rather than reading them, so `active` does not churn them).
    positions = Cell(@computation begin
        (n, cims) = build[]
        ([_sl_child_x_cell(i, cims, outer_w, halign) for i in 1:n],
         [_sl_child_y_cell(i, cims, outer_h, valign) for i in 1:n])
    end)

    elements_cv = CellVector(@computation begin
        (n, cims) = build[]
        (cx, cy) = positions[]
        out = Any[]
        for i in _visible(active_cell[], n)
            c = cims[i].output
            c isa GraphicsCanvas && push!(out, _wrap_child(c, cx[i], cy[i]))
        end
        out
    end)

    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(@computation Int32(outer_w[])),
                           Cell(@computation Int32(outer_h[])),
                           elements_cv,
                           layout_none, true, Cell(nothing))

    entries_cell = Cell(@computation begin
        (n, cims) = build[]
        (cx, cy) = positions[]
        out = Tuple{Cell,Cell,Any}[]
        for i in _visible(active_cell[], n)
            push!(out, (cx[i], cy[i], cims[i]))
        end
        out
    end)

    ChildrenIoMap(p, doc, outer, entries_cell)
end

# A stack keeps only canvases, which is the test its own build used.
map_reference_forward(::StackLayoutToGraphicsCanvas, iomap, reference) =
    _children_forward(iomap, reference, output -> output isa GraphicsCanvas)

map_reference_backward(::StackLayoutToGraphicsCanvas, iomap, reference) =
    _children_backward(iomap, reference, output -> output isa GraphicsCanvas;
                       topmost_first = true)

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

_cl_pos_cell(solve::Cell, i::Int, k::Int)  = Cell(@computation Int32(solve[][i][k]))  # k = 1 (x) / 2 (y)
_cl_size_cell(solve::Cell, i::Int, k::Int) = Cell(@computation solve[][i][k])         # k = 3 (w) / 4 (h), Int

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
        cctx = make_child_context(ctx, doc, (@reference_step children), (@reference_step [i]))
        cctx = with_exact_size(cctx; width=nothing, height=nothing)
        push!(measure_iomaps, _recurse_child(recursion, doc.children[i], cctx))
    end

    bw_cell = getfield(doc, :bounding_width)
    bh_cell = getfield(doc, :bounding_height)
    relations_cv = doc.relations

    # One reactive cell wrapping the whole LP solve. Re-runs lazily when any
    # child intrinsic extent, any relation, or a bounding dimension changes.
    solve = Cell(Computation(function ()
        iw = Int[_child_w(cim) for cim in measure_iomaps]
        ih = Int[_child_h(cim) for cim in measure_iomaps]
        rels = _solver_relations(relations_cv)
        solve_constraint_layout(solver, n, iw, ih, rels, Int(bw_cell[]), Int(bh_cell[]))
    end))

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
            cctx = make_child_context(ctx, doc, (@reference_step children), (@reference_step [i]))
            cctx = with_exact_size(cctx;
                                   width  = xset[i] ? sw[i] : nothing,
                                   height = yset[i] ? sh[i] : nothing)
            push!(final_iomaps, _recurse_child(recursion, doc.children[i], cctx))
        end
    end

    # The container is extrinsically sized when bounding dims are given;
    # otherwise it falls back to the max solved child extent.
    outer_w = Cell(Computation(function ()
        bw = Int(bw_cell[])
        bw > 0 && return bw
        s = solve[]
        w = 0
        for i in 1:n
            right = s[i][1] + s[i][3]
            right > w && (w = right)
        end
        w
    end))

    outer_h = Cell(Computation(function ()
        bh = Int(bh_cell[])
        bh > 0 && return bh
        s = solve[]
        h = 0
        for i in 1:n
            bottom = s[i][2] + s[i][4]
            bottom > h && (h = bottom)
        end
        h
    end))

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
    build = Cell(@computation _cl_build(solver, recursion, doc, ctx))
    ring = make_layout_selection_ring(doc, () -> build[].entries, p.graphics_style)
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(@computation Int32(build[].w[])),
                           Cell(@computation Int32(build[].h[])),
                           CellVector(@computation vcat(build[].wrapped, Any[ring])),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, doc, outer, Cell(@computation build[].entries))
end

function map_reference_forward(::ConstraintLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

map_reference_backward(::ConstraintLayoutToGraphicsCanvas, iomap, reference) =
    _children_backward(iomap, reference; topmost_first = true)

# Children can overlap (the solver places them freely), so route like a stack:
# scan topmost-first so the last-drawn child wins a click.
function read_intent(::ConstraintLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    _route_stack_event(iomap, evt)
end

# ── AnchoredLayoutToGraphicsCanvas ─────────────────────────────────────────
#
# The content is projected exactly as it would be on its own, and each anchored
# child is placed beside a target *inside* it and drawn afterwards. The content
# never sees the anchored children, which is the property the whole type exists
# for: annotating a diagram must not move it.

"""
    AnchoredLayoutToGraphicsCanvas()

Project an [`AnchoredLayout`](@ref): the content, with each anchored child
composited over it beside its target.
"""
@projection UntrackedCell struct AnchoredLayoutToGraphicsCanvas
    graphics_style::NamedTuple = get_theme_defaults(GraphicsTheme)
end

# Where a target sits, as `(x, y, w, h)` in the content's own coordinates.
#
# A target given directly is read from its position cells. A target named by
# reference is resolved through the content's IoMap — `map_reference_forward`
# takes a reference in the content's input domain to one in the graphics it
# produced, and the node it lands on carries the coordinates. Unresolvable is
# `nothing` rather than an error: a target may legitimately be hidden, and an
# annotation with nowhere to go is better dropped at the origin than fatal.
function _al_target_rect(entry, content_iomap)
    direct = entry.target
    direct === nothing || return _al_rect_of(direct)
    reference = entry.reference
    reference === nothing && return nothing
    projected = try
        map_reference_forward(content_iomap.projection, content_iomap, reference)
    catch
        nothing
    end
    projected === nothing && return nothing
    node = try
        evaluate_reference(content_iomap.output, projected)
    catch
        nothing
    end
    node === nothing ? nothing : _al_rect_of(node)
end

function _al_rect_of(node)
    node isa GraphicsCanvas &&
        return (Int(node.x[]), Int(node.y[]), Int(node.w[]), Int(node.h[]))
    node isa GraphicsDocument || return nothing
    x = hasproperty(node, :x) ? Int(node.x) : 0
    y = hasproperty(node, :y) ? Int(node.y) : 0
    # A node that states its own size says it exactly; for anything else
    # `get_graphics_size` gives the extent measured *from the origin*, so the node's
    # own size is what is left of that after its offset.
    (hasproperty(node, :w) && hasproperty(node, :h)) &&
        return (x, y, Int(node.w), Int(node.h))
    ex, ey = get_graphics_size(node)
    (x, y, max(0, Int(ex) - x), max(0, Int(ey) - y))
end

function _al_build(recursion, doc::AnchoredLayout, ctx)
    content_iomap = _recurse_child(recursion, doc.content,
                                   make_child_context(ctx, doc, (@reference_step content)))
    n = length(doc.children)
    child_iomaps = Any[]
    for i in 1:n
        entry = doc.children[i]
        cctx = make_child_context(ctx, doc, (@reference_step children), (@reference_step [i]),
                                  (@reference_step child))
        push!(child_iomaps, _recurse_child(recursion, entry.child, cctx))
    end

    # One cell over the whole placement: it re-runs when a target moves, a child
    # resizes, or the region changes — and NOT when the content merely redraws,
    # because the content's geometry is not a function of these children.
    placed = Cell(Computation(function ()
        entries = Tuple{Int,Int,Symbol,Int,Int}[]
        targets = Any[]
        for i in 1:n
            entry = doc.children[i]
            cim = child_iomaps[i]
            push!(entries, (_child_w(cim), _child_h(cim), entry.placement,
                            Int(entry.offset_x), Int(entry.offset_y)))
            push!(targets, _al_target_rect(entry, content_iomap))
        end
        compute_anchored_positions(entries, targets; bounding_w = Int(doc.bounding_width),
                                   bounding_h = Int(doc.bounding_height),
                                   stacking_gap = Int(doc.stacking_gap))
    end))

    child_x = Cell[Cell(@computation Int32(placed[][i][1])) for i in 1:n]
    child_y = Cell[Cell(@computation Int32(placed[][i][2])) for i in 1:n]

    # The content first, the anchored children over it, in the order given.
    wrapped = Any[]
    content_output = content_iomap.output
    content_output isa GraphicsDocument && push!(wrapped, content_output)
    for i in 1:n
        c = child_iomaps[i].output
        c isa GraphicsDocument || continue
        push!(wrapped, _wrap_child(c, child_x[i], child_y[i]))
    end

    # The region is what was asked for, else what the content needs — an
    # annotation hanging off the edge does not grow the diagram.
    outer_w = Cell(Computation(function ()
        bw = Int(doc.bounding_width)
        bw > 0 ? bw : _child_w(content_iomap)
    end))
    outer_h = Cell(Computation(function ()
        bh = Int(doc.bounding_height)
        bh > 0 ? bh : _child_h(content_iomap)
    end))

    entries = Tuple{Cell,Cell,Any}[]
    push!(entries, (Cell(Int32(0)), Cell(Int32(0)), content_iomap))
    for i in 1:n
        push!(entries, (child_x[i], child_y[i], child_iomaps[i]))
    end
    (wrapped = wrapped, w = outer_w, h = outer_h, entries = entries)
end

function print_document(p::AnchoredLayoutToGraphicsCanvas, recursion,
                        doc::AnchoredLayout, ctx)
    build = Cell(@computation _al_build(recursion, doc, ctx))
    ring = make_layout_selection_ring(doc, () -> build[].entries, p.graphics_style)
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           Cell(@computation Int32(build[].w[])),
                           Cell(@computation Int32(build[].h[])),
                           CellVector(@computation vcat(build[].wrapped, Any[ring])),
                           layout_none, true, Cell(nothing))
    ChildrenIoMap(p, doc, outer, Cell(@computation build[].entries))
end

# Child 1 of the IoMap is the content; the anchored children follow it, so a
# reference into the content keeps working and `children[i]` lands on entry i.
function map_reference_forward(::AnchoredLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

# Only a point maps back: the anchored child drawn at it, topmost first, as the
# reader routes a click.
function map_reference_backward(::AnchoredLayoutToGraphicsCanvas, iomap, reference)
    point = find_reference_point(reference)
    point === nothing && return nothing
    # The first entry is the content, and the entry after it the first child.
    _point_backward(iomap.input, getfield(iomap, :child_iomaps)[]::Vector, point;
                    topmost_first = true,
                    steps_of = index -> index == 1 ? (FieldReferenceStep("content"),) :
                                        (FieldReferenceStep("children"),
                                         RangeReferenceStep(index - 2, index - 1)))
end

# Anchored children are drawn over the content, so a click must reach them
# first — the same topmost-first rule the stack and constraint layouts follow.
read_intent(::AnchoredLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt) =
    _route_stack_event(iomap, evt)

# ── Factory ────────────────────────────────────────────────────────────────

"""
    LayoutToGraphics(; theme = nothing)

A type-dispatching projection that routes any layout document to its
`…ToGraphicsCanvas` projection. A layout draws the ring around a child selected
as a whole with the `GraphicsTheme` `theme`, scaled or not, which the layouts
read at each read, or `nothing` for the default theme. Wrap in a
`RecursiveProjection` (or include in a larger dispatcher) so children re-enter
the recursion.
"""
function LayoutToGraphics(; theme::Union{GraphicsTheme, ScaledGraphicsTheme, Nothing} = nothing)
    graphics_style = make_theme_values_field(GraphicsTheme, theme)
    TypeDispatchingProjection(
        HorizontalLayout => HorizontalLayoutToGraphicsCanvas(; graphics_style),
        VerticalLayout   => VerticalLayoutToGraphicsCanvas(; graphics_style),
        GridLayout       => GridLayoutToGraphicsCanvas(; graphics_style),
        FlowLayout       => FlowLayoutToGraphicsCanvas(; graphics_style),
        StackLayout      => StackLayoutToGraphicsCanvas(),
        LayoutConstraint => LayoutConstraintToGraphicsCanvas(),
        ConstraintLayout => ConstraintLayoutToGraphicsCanvas(; graphics_style),
        AnchoredLayout   => AnchoredLayoutToGraphicsCanvas(; graphics_style),
    )
end

# A route gives the child that it reaches the point in the child's own frame, as
# a gesture at the point does: each layout keeps the place of each child in an
# entry of its IoMap.
const _PlacingLayoutProjection = Union{
    HorizontalLayoutToGraphicsCanvas, VerticalLayoutToGraphicsCanvas,
    GridLayoutToGraphicsCanvas, FlowLayoutToGraphicsCanvas, StackLayoutToGraphicsCanvas,
    ConstraintLayoutToGraphicsCanvas, AnchoredLayoutToGraphicsCanvas}

ProjectionModule.read_child_by_route(::_PlacingLayoutProjection, recursion, change::Intent,
                                     iomap, child) =
    read_routed_entry_child(recursion, change, child; entries = iomap.child_iomaps)
