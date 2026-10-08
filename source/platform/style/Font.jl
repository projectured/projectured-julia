# Fragment of `StyleModule`.
#
# The font value type. A font names a family, a size, a weight and a slant; the
# registry of `FontFace.jl` finds the file.
# ── Document ──────────────────────────────────────────────────────────────────

# A value-document: the fields are immutable by default; the selection is
# typed `Nothing` (non-selectable, so `StyleFont` — the bare form — inlines in a
# config cell). `RCStyleFont` gives a reactive, selectable, editable font.
"""
    StyleFont(family, size; weight = 400, italic = false)

A font: the family of its typeface, how large, how heavy, and whether it leans.

Use it to say how words look: which typeface a label, a heading or a block of
code is drawn in, and at what size. The `size` is in logical pixels. The
`weight` is on the scale of CSS from 100 to 900: 400 is regular and 700 is bold.
A backend draws the font with the file of the bundled face that
[`compute_font_path`](@ref) finds, and the measure reads the same file.

Two equal fonts are one value: a font is 24 bytes, stored inline, with no cache.

# Example

    StyleFont("Ubuntu Mono", 14; weight = 700)

See also `StyleText`, which pairs a font with a colour, and `GraphicsText`.
"""
@document ImmutableCell [DC] struct StyleFont
    family::String
    size::Int
    weight::Int16
    italic::Bool
    selection::Nothing
end

StyleFont(family::AbstractString, size::Integer; weight::Integer = 400, italic::Bool = false) =
    StyleFont(String(family), Int(size), Int16(weight), italic)

# ── Construction ──────────────────────────────────────────────────────────────

make_style_font(family::AbstractString, size::Integer; weight::Integer = 400, italic::Bool = false) =
    StyleFont(family, size; weight, italic)

"""
    with_font_size(font, size) -> StyleFont

`font` at `size` logical pixels, with its family, its weight and its slant.
"""
with_font_size(font::StyleFont, size) =
    StyleFont(font.family, Int(size), font.weight, font.italic)

# ── Font size ────────────────────────────────────────────────────────────────

"""
    font_logical_size(font::StyleFont) -> Int

A font's size in logical pixels. The size of a font of a theme already holds the
font scale of the appearance, so this is `font.size`, rounded to the nearest
whole pixel and never below 1.
"""
font_logical_size(font::StyleFont) = max(1, round(Int, font.size))

"""
    font_device_size(font::StyleFont, ratio::Real) -> Int

A font's size in device pixels: its logical size times `ratio`, the number of
device pixels in one logical pixel. A backend rasterizes the glyphs at this
size, so that they land one to one on the device pixels.
"""
font_device_size(font::StyleFont, ratio::Real) = max(1, round(Int, font.size * ratio))

# ── Scale stepping ──────────────────────────────────────────────────────────

# The zoom factors that `step_factor` steps through, as in a web browser.
const _FACTOR_STEPS = (0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0)

"""
    step_factor(zoom::Real, delta::Integer) -> Float64

The zoom `delta` steps away from `zoom` in the table of zoom factors: `+1` zooms
in, `-1` zooms out, and `0` gives `1.0`. A `zoom` between two factors counts as
the nearest one, and the result stays inside the table.
"""
function step_factor(zoom::Real, delta::Integer)
    delta == 0 && return 1.0
    i = argmin(abs.(collect(_FACTOR_STEPS) .- zoom))
    _FACTOR_STEPS[clamp(i + delta, 1, length(_FACTOR_STEPS))]
end

# ── Font directory ─────────────────────────────────────────────────────────────

# This file sits at source/platform/style/, so the repository root is two levels up.
const _FONT_DIR = joinpath(@__DIR__, "../../../asset/font")
