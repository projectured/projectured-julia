"""
    GeometryModule

Reactive geometry primitives shared across document domains. Provides
`Inset` (spacing descriptor for margin, border, padding) and `Point2D`
(2-D coordinate or dimension), both built on reactive Cells.
"""
module GeometryModule

import ..ReactiveModule: Cell
export Inset, Point2D, inset_default,
       inset_size, inset_width, inset_height,
       inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right

# ── Inset ──────────────────────────────────────────────────────────────────

"""
    Inset(top, bottom, left, right)

A reactive spacing descriptor used for margin, border, and padding.
Each side is a `Cell` holding a number.
"""
struct Inset
    top::Cell     # Number
    bottom::Cell  # Number
    left::Cell    # Number
    right::Cell   # Number
end

Inset(top::Real, bottom::Real, left::Real, right::Real) =
    Inset(Cell(top), Cell(bottom), Cell(left), Cell(right))

function Base.show(io::IO, ins::Inset)
    print(io, "Inset(top=", ins.top[], ", bottom=", ins.bottom[],
          ", left=", ins.left[], ", right=", ins.right[], ")")
end

# Shared zero-inset singleton.
const inset_default = Inset(0, 0, 0, 0)

# ── Point2D ────────────────────────────────────────────────────────────────

"""
    Point2D(x, y)

A reactive 2-D coordinate or dimension.  Each axis is a `Cell` holding a
number.  Used for widget positions, sizes, and scroll offsets.
"""
struct Point2D
    x::Cell  # Number
    y::Cell  # Number
end

Point2D(x::Real, y::Real) = Point2D(Cell(x), Cell(y))

function Base.show(io::IO, p::Point2D)
    print(io, "Point2D(", p.x[], ", ", p.y[], ")")
end

# ── Inset API ──────────────────────────────────────────────────────────────

"""Return the total `Point2D` extent consumed by `ins` on each axis."""
inset_size(ins::Inset) =
    Point2D(ins.left[] + ins.right[], ins.top[] + ins.bottom[])

"""Return the total horizontal space consumed by `ins`."""
inset_width(ins::Inset) = ins.left[] + ins.right[]

"""Return the total vertical space consumed by `ins`."""
inset_height(ins::Inset) = ins.top[] + ins.bottom[]

"""Return the top-left corner offset of `ins` as a `Point2D`."""
inset_top_left(ins::Inset) = Point2D(ins.left[], ins.top[])

"""Return the top-right corner offset of `ins` as a `Point2D`."""
inset_top_right(ins::Inset) = Point2D(ins.right[], ins.top[])

"""Return the bottom-left corner offset of `ins` as a `Point2D`."""
inset_bottom_left(ins::Inset) = Point2D(ins.left[], ins.bottom[])

"""Return the bottom-right corner offset of `ins` as a `Point2D`."""
inset_bottom_right(ins::Inset) = Point2D(ins.right[], ins.bottom[])

end # module
