# Fragment of `StyleModule`.
#
# Reactive geometry primitives shared across document domains. Provides
# `Inset` (spacing descriptor for margin, border, padding) and `Point2D`
# (2-D coordinate or dimension), both built on reactive Cells.
# ── Inset ──────────────────────────────────────────────────────────────────

"""
    Inset(top, bottom, left, right)

Four spacings: top, bottom, left and right.

Use it to give a widget a margin, a border width or a padding, one number per
side. `Inset(0, 0, 12, 0)` indents by 12 pixels on the left and nothing else.
Each side is a `Cell` that holds a number.

# Example

    open_pane!(WidgetCard(; title = "Note", content = WidgetLabel("Indented"), padding = Inset(8, 8, 24, 8));
               title = "Padded")

See also `Point2D` for a position or a size.
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

A pair of numbers: a position or a size.

Use it to give a widget its `position`, a keyword that is `Point2D(0, 0)` unless
the widget is placed by hand, or a size such as a button's `Point2D(120, 32)`. Each axis is
a `Cell` that holds a number, so a widget moves when the cell changes.

# Example

    open_pane!(WidgetButton("Run"; size = Point2D(120, 32)); title = "Button")

See also `Inset` for a spacing per side.
"""
struct Point2D
    x::Cell  # Number
    y::Cell  # Number
end

Point2D(x::Real, y::Real) = Point2D(Cell(x), Cell(y))

function Base.show(io::IO, p::Point2D)
    print(io, "Point2D(", p.x[], ", ", p.y[], ")")
end

# A size, a scroll position and a margin are data, so a saved window keeps them:
# a file writes each as its call, and the reader builds it from the numbers.
is_pred_constructible(::Type{Point2D}) = true
is_pred_constructible(::Type{Inset}) = true

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

# ── AffineTransform ──────────────────────────────────────────────────────────

"""
    AffineTransform(a, b, c, d, e, f)

An immutable 2-D affine transform mapping a *local* point to a *screen* point:

    screen.x = a*local.x + c*local.y + e
    screen.y = b*local.x + d*local.y + f

i.e. the 2×3 matrix `[a c e; b d f]` (column vectors), matching the convention
used by SVG/Canvas `setTransform(a,b,c,d,e,f)` and PostScript/PDF `cm`. The
fields are plain `Float64` (not `Cell`s): a transform is a *value* that is
swapped wholesale (like a `Point2D` written into `scroll_position`), so it is
held inside a single `Cell` by whatever document carries it.

Use [`affine_identity`](@ref), [`make_affine_translate`](@ref),
[`make_affine_scale`](@ref) to build common cases and `∘` to compose
(`A ∘ B` applies `B` first, then `A`).
"""
struct AffineTransform
    a::Float64; b::Float64; c::Float64; d::Float64; e::Float64; f::Float64
end

"The identity transform (no scale, no translation)."
const affine_identity = AffineTransform(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)

"A pure translation by `(tx, ty)`."
make_affine_translate(tx, ty) = AffineTransform(1.0, 0.0, 0.0, 1.0, Float64(tx), Float64(ty))

"A pure (possibly non-uniform) scale by `(sx, sy)` about the origin."
make_affine_scale(sx, sy) = AffineTransform(Float64(sx), 0.0, 0.0, Float64(sy), 0.0, 0.0)
make_affine_scale(s) = make_affine_scale(s, s)

"""Compose two transforms: `(A ∘ B)` applies `B` first, then `A`."""
function Base.:∘(A::AffineTransform, B::AffineTransform)
    AffineTransform(
        A.a * B.a + A.c * B.b,
        A.b * B.a + A.d * B.b,
        A.a * B.c + A.c * B.d,
        A.b * B.c + A.d * B.d,
        A.a * B.e + A.c * B.f + A.e,
        A.b * B.e + A.d * B.f + A.f,
    )
end

"""Apply `M` to the local point `(x, y)`; returns the screen `(x, y)` tuple."""
apply_affine_transform(M::AffineTransform, x, y) =
    (M.a * x + M.c * y + M.e, M.b * x + M.d * y + M.f)

"""
    compute_affine_inverse(M) -> AffineTransform

The inverse transform (screen → local). Errors if `M` is singular
(determinant zero).
"""
function compute_affine_inverse(M::AffineTransform)
    det = M.a * M.d - M.b * M.c
    det == 0 && error("AffineTransform is singular; cannot invert")
    ia = M.d / det
    ib = -M.b / det
    ic = -M.c / det
    id = M.a / det
    AffineTransform(ia, ib, ic, id,
                    -(ia * M.e + ic * M.f),
                    -(ib * M.e + id * M.f))
end

"""
    is_affine_axis_aligned(M) -> Bool

`true` when `M` has no rotation/shear (off-diagonal terms zero), i.e. it is a
pure translate+scale. The renderer fast path (`RenderSetScale` + baked offset)
only applies in this case.
"""
is_affine_axis_aligned(M::AffineTransform) = M.b == 0.0 && M.c == 0.0

function Base.show(io::IO, M::AffineTransform)
    if M == affine_identity
        print(io, "AffineTransform(identity)")
    elseif is_affine_axis_aligned(M)
        print(io, "AffineTransform(scale=(", M.a, ", ", M.d, "), translate=(", M.e, ", ", M.f, "))")
    else
        print(io, "AffineTransform(", M.a, ", ", M.b, ", ", M.c, ", ", M.d, ", ", M.e, ", ", M.f, ")")
    end
end
