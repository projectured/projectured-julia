# Fragment of `StyleModule`.
#
# Combined stroke style value type. A `StyleStroke` bundles the values that
# describe a drawn line or outline — a [`StyleColor`](@ref), a `width`, and an
# optional `dash` pattern — so a renderer (and a theme) can pass one value instead
# of a loose `(color, width)` pair. Used for widget borders and for line strokes
# (hairlines, chevrons, checkmarks). Mirrors the plain-value convention of
# `StyleColor` / `StyleFont` / `StyleText`.
#
# `dash` is `nothing` for a solid stroke; a dash array is reserved for a future
# backend that renders dashed strokes (solid is drawn until then).
# ── Document ──────────────────────────────────────────────────────────────────

"""
    StyleStroke(color, width; dash=nothing)

A stroke style value: the `color` to draw with, the `width` in logical pixels,
and an optional `dash` pattern (`nothing` = solid).
"""
struct StyleStroke
    color::StyleColor
    width::Int
    dash::Any
end

StyleStroke(color::StyleColor, width; dash=nothing) =
    StyleStroke(color, Int(width), dash)

# ── Construction ──────────────────────────────────────────────────────────────

make_style_stroke(color::StyleColor, width; dash=nothing) =
    StyleStroke(color, Int(width), dash)

function Base.show(io::IO, stroke::StyleStroke)
    print(io, "StyleStroke(", stroke.color, ", ", stroke.width,
          stroke.dash === nothing ? "" : ", dash=$(stroke.dash)", ")")
end
