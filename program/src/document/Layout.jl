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
       IHorizontalLayout, IVerticalLayout, IGridLayout, IFlowLayout

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

end # module
