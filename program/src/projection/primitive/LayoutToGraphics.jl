"""
    LayoutToGraphicsModule

Projections from layout documents (`HorizontalLayout`, `VerticalLayout`,
`GridLayout`, `FlowLayout`) to `GraphicsCanvas`.

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
import ..ProjectionApiModule: projection_print, projection_read,
                               map_reference_forward, map_reference_backward, Projection
import ..DocumentApiModule: Document
import ..LayoutModule: HorizontalLayout, VerticalLayout, GridLayout, FlowLayout
import ..CollectionModule: CellVector
import ..GraphicsModule: GraphicsCanvas, layout_none, hit_element_at
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..MouseModule: MouseScroll, MousePress
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..ReferenceBuilderModule: var"@reference"
export HorizontalLayoutToGraphicsCanvas, VerticalLayoutToGraphicsCanvas,
       GridLayoutToGraphicsCanvas, FlowLayoutToGraphicsCanvas,
       LayoutToGraphics

# ── Projection structs ─────────────────────────────────────────────────────

struct HorizontalLayoutToGraphicsCanvas <: Projection end
struct VerticalLayoutToGraphicsCanvas   <: Projection end
struct GridLayoutToGraphicsCanvas       <: Projection end
struct FlowLayoutToGraphicsCanvas       <: Projection end

# ── Helpers ────────────────────────────────────────────────────────────────

_empty_canvas() = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0),
                                 CellVector(), layout_none, true, Cell(nothing))

"""
Wrap a child `GraphicsCanvas` at the (x, y) given by two cells. The
wrapper is a fresh canvas at (x, y) whose single element is the child
canvas — same pattern as `_make_canvas` in `WidgetToGraphics`.
"""
function _wrap_child(child::GraphicsCanvas, x_cell::Cell, y_cell::Cell)
    GraphicsCanvas(x_cell, y_cell,
                   Cell(Int32(0)), Cell(Int32(0)),
                   CellVector(Cell[Cell(child)]),
                   layout_none, true, Cell(nothing))
end

"""
Route a mouse-style event to whichever child wrapper canvas contains
the (x, y). `child_entries` is a vector of `(x_cell, y_cell, cim)`
triples — the same shape this module stores on `ChildrenIoMap`.
"""
function _route_to_children(child_entries::Vector, x::Int, y::Int, make_evt)
    for entry in child_entries
        entry === nothing && continue
        (ox_cell, oy_cell, cim) = entry::Tuple{Cell,Cell,Any}
        canvas = cim.output
        canvas isa GraphicsCanvas || continue
        ox = Int(ox_cell[])
        oy = Int(oy_cell[])
        lx, ly = x - ox - Int(canvas.x), y - oy - Int(canvas.y)
        hit_element_at(canvas, lx, ly) === nothing && continue
        result = projection_read(cim.projection, cim, make_evt(lx, ly))
        result !== nothing && return result
    end
    nothing
end

_route_scroll(entries, evt::MouseScroll) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> MouseScroll(evt.dx, evt.dy, x, y))

_route_click(entries, evt::MousePress) =
    _route_to_children(entries, evt.x, evt.y,
        (x, y) -> MousePress(evt.button, x, y, evt.modifiers))

"""
Recurse into a child document via the dispatcher.
"""
function _recurse_child(recursion, child, ref)
    recursion === nothing && return SimpleIoMap(nothing, child, child)
    return projection_print(recursion, child, recursion, ref)
end

"""
Read `w` from a child iomap's output. Returns 0 when the output isn't
a `GraphicsCanvas` (defensive — the layout still works, just collapses
to the children that are canvases).
"""
function _child_w(cim)
    c = cim.output
    c isa GraphicsCanvas || return 0
    Int(c.w[])
end

function _child_h(cim)
    c = cim.output
    c isa GraphicsCanvas || return 0
    Int(c.h[])
end

"""
A reference of the form `children[i]/...` routes to the i-th child
iomap's forward mapping.
"""
function _children_forward(iomap::ChildrenIoMap, reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "children" || return nothing
    rest = reference.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    idx = h2.start + 1
    entries = iomap.child_iomaps[]::Vector
    1 <= idx <= length(entries) || return nothing
    cim = entries[idx][3]
    map_reference_forward(cim.projection, cim, rest.tail)
end

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

function projection_print(p::HorizontalLayoutToGraphicsCanvas,
                          doc::HorizontalLayout, recursion, reference)
    n = length(doc.children)
    if n == 0
        return ChildrenIoMap(p, doc, _empty_canvas(), Cell(Tuple{Cell,Cell,Any}[]))
    end

    child_iomaps = Any[]
    for i in 1:n
        cim = _recurse_child(recursion, doc.children[i],
                             @reference ^(reference).children[i])
        push!(child_iomaps, cim)
    end

    gap_cell   = getfield(doc, :gap)
    align_cell = getfield(doc, :vertical_align)

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
        c isa GraphicsCanvas || continue
        push!(wrapped, _wrap_child(c, child_x[i], child_y[i]))
    end

    outer_w_i32 = Cell(() -> Int32(outer_w[]))
    outer_h_i32 = Cell(() -> Int32(outer_h[]))
    outer = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                           outer_w_i32, outer_h_i32,
                           CellVector(Cell[Cell(e) for e in wrapped]),
                           layout_none, true, Cell(nothing))

    entries = Tuple{Cell,Cell,Any}[]
    for i in 1:n
        push!(entries, (child_x[i], child_y[i], child_iomaps[i]))
    end

    ChildrenIoMap(p, doc, outer, Cell(entries))
end

function map_reference_forward(::HorizontalLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::HorizontalLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::HorizontalLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    entries = iomap.child_iomaps[]::Vector
    evt isa MousePress  && return _route_click(entries, evt)
    evt isa MouseScroll && return _route_scroll(entries, evt)
    nothing
end

# ── VerticalLayout ─────────────────────────────────────────────────────────

function projection_print(p::VerticalLayoutToGraphicsCanvas,
                          doc::VerticalLayout, recursion, reference)
    n = length(doc.children)
    if n == 0
        return ChildrenIoMap(p, doc, _empty_canvas(), Cell(Tuple{Cell,Cell,Any}[]))
    end

    child_iomaps = Any[]
    for i in 1:n
        cim = _recurse_child(recursion, doc.children[i],
                             @reference ^(reference).children[i])
        push!(child_iomaps, cim)
    end

    gap_cell   = getfield(doc, :gap)
    align_cell = getfield(doc, :horizontal_align)

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
        c isa GraphicsCanvas || continue
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

function map_reference_forward(::VerticalLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::VerticalLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::VerticalLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    entries = iomap.child_iomaps[]::Vector
    evt isa MousePress  && return _route_click(entries, evt)
    evt isa MouseScroll && return _route_scroll(entries, evt)
    nothing
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

function _gl_child_x(i::Int, child_iomaps::Vector,
                    cols_cell::Cell, col_w::Vector{Cell}, col_x::Vector{Cell},
                    halign::Cell)
    Cell(function ()
        c = cols_cell[]
        cw = _child_w(child_iomaps[i])
        col = _grid_col(i, c)
        cellw = col_w[col][]
        a = halign[]
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

function projection_print(p::GridLayoutToGraphicsCanvas,
                          doc::GridLayout, recursion, reference)
    n = length(doc.children)
    if n == 0
        return ChildrenIoMap(p, doc, _empty_canvas(), Cell(Tuple{Cell,Cell,Any}[]))
    end

    child_iomaps = Any[]
    for i in 1:n
        cim = _recurse_child(recursion, doc.children[i],
                             @reference ^(reference).children[i])
        push!(child_iomaps, cim)
    end

    cols_cell = getfield(doc, :columns)
    hgap      = getfield(doc, :horizontal_gap)
    vgap      = getfield(doc, :vertical_gap)
    halign    = getfield(doc, :horizontal_align)
    valign    = getfield(doc, :vertical_align)

    # Pre-allocate up to n column / row extents — at most n columns
    # (one child per column, n rows of 1) or n rows (one column).
    col_w = Cell[]
    row_h = Cell[]
    for k in 1:n
        push!(col_w, _gl_col_w_cell(k, n, child_iomaps, cols_cell))
        push!(row_h, _gl_row_h_cell(k, n, child_iomaps, cols_cell))
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
        push!(child_x, _gl_child_x(i, child_iomaps, cols_cell, col_w, col_x, halign))
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
        c isa GraphicsCanvas || continue
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

function map_reference_forward(::GridLayoutToGraphicsCanvas, iomap, reference)
    return _children_forward(iomap, reference)
end

function map_reference_backward(::GridLayoutToGraphicsCanvas, iomap, reference)
    return nothing
end

function projection_read(::GridLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    entries = iomap.child_iomaps[]::Vector
    evt isa MousePress  && return _route_click(entries, evt)
    evt isa MouseScroll && return _route_scroll(entries, evt)
    nothing
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

function projection_print(p::FlowLayoutToGraphicsCanvas,
                          doc::FlowLayout, recursion, reference)
    n = length(doc.children)
    if n == 0
        return ChildrenIoMap(p, doc, _empty_canvas(), Cell(Tuple{Cell,Cell,Any}[]))
    end

    child_iomaps = Any[]
    for i in 1:n
        cim = _recurse_child(recursion, doc.children[i],
                             @reference ^(reference).children[i])
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
        c isa GraphicsCanvas || continue
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

function projection_read(::FlowLayoutToGraphicsCanvas, iomap::ChildrenIoMap, evt)
    entries = iomap.child_iomaps[]::Vector
    evt isa MousePress  && return _route_click(entries, evt)
    evt isa MouseScroll && return _route_scroll(entries, evt)
    nothing
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
    )
end

end # module
