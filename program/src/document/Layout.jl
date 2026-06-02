"""
    LayoutModule

Generic, content-driven layout documents. Each layout type holds an
ordered `children::CellVector` of arbitrary `Document`s and a few
axis-specific knobs (alignment, gap, max extent). Layouts are *not*
tied to widgets — children can be any document type that has a
projection to `GraphicsCanvas`.

Layouts have no `position`/`size` of their own; their projected
canvas is intrinsic (computed from the children's `w`/`h` cells).
A parent that needs to place a layout positions the outer canvas
the layout produces.
"""
module LayoutModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export LayoutDocument,
       HorizontalLayout, VerticalLayout, GridLayout, FlowLayout,
       LayoutConstraint,
       allocate_axis,
       layout_min, layout_max, layout_preferred, layout_weight,
       IHorizontalLayout, IVerticalLayout, IGridLayout, IFlowLayout,
       ILayoutConstraint

# ── Abstract base ───────────────────────────────────────────────────────────

"""
    LayoutDocument

Abstract base for layout documents. Each concrete layout has a
`children::CellVector` field, plus its own axis-specific options.
"""
abstract type LayoutDocument <: Document end

# ── HorizontalLayout ────────────────────────────────────────────────────────

"""
    HorizontalLayout(children; vertical_align, gap)

A row of children. The projection places each child at an
increasing x cursor, with vertical alignment chosen by
`vertical_align ∈ (:top, :center, :bottom)`. The outer canvas has
width = sum of child widths + gaps and height = max of child
heights.
"""
@document struct HorizontalLayout <: LayoutDocument
    children::CellVector
    vertical_align::Symbol
    gap::Int
    selection::Reference
end

function HorizontalLayout(children::Vector;
                          vertical_align::Symbol=:top,
                          gap::Integer=0)
    HorizontalLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
                     Cell(vertical_align), Cell(Int(gap)), Cell(nothing))
end

HorizontalLayout(; kwargs...) = HorizontalLayout(Any[]; kwargs...)

function Base.show(io::IO, h::HorizontalLayout)
    print(io, "HorizontalLayout(n=", length(h.children),
          ", v_align=", h.vertical_align, ", gap=", h.gap, ")")
end

# ── VerticalLayout ──────────────────────────────────────────────────────────

"""
    VerticalLayout(children; horizontal_align, gap)

A column of children. Symmetric to `HorizontalLayout`:
`horizontal_align ∈ (:left, :center, :right)`. Outer width = max
of child widths; outer height = sum of child heights + gaps.
"""
@document struct VerticalLayout <: LayoutDocument
    children::CellVector
    horizontal_align::Symbol
    gap::Int
    selection::Reference
end

function VerticalLayout(children::Vector;
                        horizontal_align::Symbol=:left,
                        gap::Integer=0)
    VerticalLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
                   Cell(horizontal_align), Cell(Int(gap)), Cell(nothing))
end

VerticalLayout(; kwargs...) = VerticalLayout(Any[]; kwargs...)

function Base.show(io::IO, v::VerticalLayout)
    print(io, "VerticalLayout(n=", length(v.children),
          ", h_align=", v.horizontal_align, ", gap=", v.gap, ")")
end

# ── GridLayout ──────────────────────────────────────────────────────────────

"""
    GridLayout(children, columns; horizontal_align, vertical_align,
               horizontal_gap, vertical_gap)

A grid of children in row-major order. Column widths are the max
of `w` across children in that column; row heights are the max of
`h` across children in that row. Cells with no child are empty.
`horizontal_align` / `vertical_align` apply within each cell.
"""
@document struct GridLayout <: LayoutDocument
    children::CellVector
    columns::Int
    horizontal_align::Symbol
    vertical_align::Symbol
    horizontal_gap::Int
    vertical_gap::Int
    selection::Reference
end

function GridLayout(children::Vector, columns::Integer;
                    horizontal_align::Symbol=:left,
                    vertical_align::Symbol=:top,
                    horizontal_gap::Integer=0,
                    vertical_gap::Integer=0)
    columns >= 1 || error("GridLayout: columns must be >= 1")
    GridLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
               Cell(Int(columns)),
               Cell(horizontal_align), Cell(vertical_align),
               Cell(Int(horizontal_gap)), Cell(Int(vertical_gap)),
               Cell(nothing))
end

function Base.show(io::IO, g::GridLayout)
    print(io, "GridLayout(n=", length(g.children),
          ", cols=", g.columns, ")")
end

# ── FlowLayout ──────────────────────────────────────────────────────────────

"""
    FlowLayout(children; max_width, horizontal_align, vertical_align,
               horizontal_gap, vertical_gap)

A row of children that wraps to a new line when the next child
would push past `max_width`. Each line is laid out left-to-right;
line height = max `h` of children on that line. `horizontal_align`
controls intra-line justification (`:left`, `:center`, `:right`);
`vertical_align` controls cross-axis alignment within a line
(`:top`, `:center`, `:bottom`).
"""
@document struct FlowLayout <: LayoutDocument
    children::CellVector
    max_width::Int
    horizontal_align::Symbol
    vertical_align::Symbol
    horizontal_gap::Int
    vertical_gap::Int
    selection::Reference
end

function FlowLayout(children::Vector;
                    max_width::Integer=400,
                    horizontal_align::Symbol=:left,
                    vertical_align::Symbol=:top,
                    horizontal_gap::Integer=0,
                    vertical_gap::Integer=0)
    FlowLayout(CellVector(Cell[c isa Cell ? c : Cell(c) for c in children]),
               Cell(Int(max_width)),
               Cell(horizontal_align), Cell(vertical_align),
               Cell(Int(horizontal_gap)), Cell(Int(vertical_gap)),
               Cell(nothing))
end

FlowLayout(; kwargs...) = FlowLayout(Any[]; kwargs...)

function Base.show(io::IO, f::FlowLayout)
    print(io, "FlowLayout(n=", length(f.children),
          ", max_w=", f.max_width, ")")
end

# ── LayoutConstraint ────────────────────────────────────────────────────────

"""
    LayoutConstraint(child; min_width, preferred_width, max_width, weight_width,
                            min_height, preferred_height, max_height, weight_height)

A wrapper document that attaches per-child layout policy to `child` without
polluting the child's own type with layout fields. A parent layout reads
these values to allocate available space across its children; a bare
(unwrapped) child uses the defaults (`min=0`, `preferred=intrinsic`,
`max=∞`, `weight=0`).

Each axis field is `nothing` by default. When `nothing`, the parent layout
falls back to the bare-child interpretation for that field.
"""
@document struct LayoutConstraint <: Document
    child::Document
    min_width::Any
    preferred_width::Any
    max_width::Any
    weight_width::Any
    min_height::Any
    preferred_height::Any
    max_height::Any
    weight_height::Any
    selection::Reference
end

function LayoutConstraint(child::Document;
                          min_width=nothing, preferred_width=nothing,
                          max_width=nothing, weight_width=nothing,
                          min_height=nothing, preferred_height=nothing,
                          max_height=nothing, weight_height=nothing)
    LayoutConstraint(Cell(child),
                     Cell(min_width), Cell(preferred_width),
                     Cell(max_width), Cell(weight_width),
                     Cell(min_height), Cell(preferred_height),
                     Cell(max_height), Cell(weight_height),
                     Cell(nothing))
end

function Base.show(io::IO, c::LayoutConstraint)
    print(io, "LayoutConstraint(child=", c.child, ")")
end

# ── Constraint reading helpers ───────────────────────────────────────────────

"""
    layout_min(doc, axis, intrinsic) -> Int

Per-child minimum on `axis` (`:x` or `:y`). Reads through the
`LayoutConstraint` wrapper when present; falls back to `0` for bare
children.
"""
function layout_min(doc, axis::Symbol, intrinsic::Integer)
    doc isa LayoutConstraint || return 0
    v = axis === :x ? doc.min_width : doc.min_height
    v === nothing ? 0 : Int(v)
end

"""
    layout_max(doc, axis, intrinsic) -> Int

Per-child maximum on `axis`. Falls back to `typemax(Int)` for bare children.
"""
function layout_max(doc, axis::Symbol, intrinsic::Integer)
    doc isa LayoutConstraint || return typemax(Int)
    v = axis === :x ? doc.max_width : doc.max_height
    v === nothing ? typemax(Int) : Int(v)
end

"""
    layout_preferred(doc, axis, intrinsic) -> Int

Per-child preferred extent on `axis`. Falls back to the child's intrinsic
extent (`intrinsic`) when the constraint is absent or `nothing`.
"""
function layout_preferred(doc, axis::Symbol, intrinsic::Integer)
    doc isa LayoutConstraint || return Int(intrinsic)
    v = axis === :x ? doc.preferred_width : doc.preferred_height
    v === nothing ? Int(intrinsic) : Int(v)
end

"""
    layout_weight(doc, axis) -> Float64

Per-child weight on `axis`. Falls back to `0.0` for bare children.
"""
function layout_weight(doc, axis::Symbol)
    doc isa LayoutConstraint || return 0.0
    v = axis === :x ? doc.weight_width : doc.weight_height
    v === nothing ? 0.0 : Float64(v)
end

# ── Allocation algorithm (per axis, one pass) ───────────────────────────────

"""
    allocate_axis(available, mins, maxs, prefs, weights, gap, n) -> Vector{Int}

Pure allocator: distributes `available` extent across `n` children whose
seed sizes are `prefs` clamped to `[mins, maxs]`. Inter-child `gap` is
subtracted first. Slack > 0 is distributed in proportion to `weights`,
each share capped at `maxs[i]`; slack < 0 is taken in proportion to
`weights`, each draw floored at `mins[i]`. Returns one `Int` per child.

Pixel rounding may leave ±1 px residual; the residual is absorbed by the
last weighted child if any.
"""
function allocate_axis(available::Int, mins::Vector{Int}, maxs::Vector{Int},
                       prefs::Vector{Int}, weights::Vector{Float64},
                       gap::Int, n::Int)
    actual = Vector{Int}(undef, n)
    for i in 1:n
        actual[i] = clamp(prefs[i], mins[i], maxs[i])
    end
    n == 0 && return actual
    gaps_total = n > 1 ? (n - 1) * gap : 0
    seed_total = sum(actual)
    remaining  = available - seed_total - gaps_total

    if remaining > 0
        active = [i for i in 1:n if weights[i] > 0 && actual[i] < maxs[i]]
        while !isempty(active) && remaining > 0
            wsum = sum(weights[i] for i in active)
            wsum > 0 || break
            slack_in_pass = remaining
            # Compute each child's tentative share against the slack at the
            # *start* of this pass, then apply caps; redistribute residual
            # in the next outer iteration. This gives proportional shares
            # independent of iteration order.
            shares = Dict{Int,Int}()
            for i in active
                shares[i] = Int(floor(slack_in_pass * weights[i] / wsum))
            end
            # Hand out the floored residual to the largest-weight child so
            # the pass actually empties the slack on average.
            assigned = sum(values(shares); init=0)
            residual = slack_in_pass - assigned
            if residual > 0
                # Largest-weight active child absorbs the floor residual.
                heaviest = active[1]
                for i in active
                    weights[i] > weights[heaviest] && (heaviest = i)
                end
                shares[heaviest] += residual
            end
            any_change = false
            for i in copy(active)
                room = maxs[i] - actual[i]
                give = min(shares[i], room, remaining)
                if give > 0
                    actual[i] += give
                    remaining -= give
                    any_change = true
                end
                actual[i] >= maxs[i] && deleteat!(active, findfirst(==(i), active))
                remaining <= 0 && break
            end
            any_change || break
        end
    elseif remaining < 0
        deficit = -remaining
        active = [i for i in 1:n if weights[i] > 0 && actual[i] > mins[i]]
        while !isempty(active) && deficit > 0
            wsum = sum(weights[i] for i in active)
            wsum > 0 || break
            deficit_in_pass = deficit
            shares = Dict{Int,Int}()
            for i in active
                shares[i] = Int(floor(deficit_in_pass * weights[i] / wsum))
            end
            assigned = sum(values(shares); init=0)
            residual = deficit_in_pass - assigned
            if residual > 0
                heaviest = active[1]
                for i in active
                    weights[i] > weights[heaviest] && (heaviest = i)
                end
                shares[heaviest] += residual
            end
            any_change = false
            for i in copy(active)
                room = actual[i] - mins[i]
                take = min(shares[i], room, deficit)
                if take > 0
                    actual[i] -= take
                    deficit   -= take
                    any_change = true
                end
                actual[i] <= mins[i] && deleteat!(active, findfirst(==(i), active))
                deficit <= 0 && break
            end
            any_change || break
        end
    end
    actual
end

end # module
