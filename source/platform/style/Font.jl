# Fragment of `StyleModule`.
#
# The font value type and the named font constants. A font names a family, a
# size, a weight and a slant; the registry of `FontFace.jl` finds the file.
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
with_font_size(font::StyleFont, size::Integer) =
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

# ── Inconsolata ───────────────────────────────────────────────────────────────

const font_inconsolata_regular_18 = StyleFont("Inconsolata", 18)

# ── Ubuntu monospace ──────────────────────────────────────────────────────────

const font_ubuntu_monospace_regular_14 = StyleFont("Ubuntu Mono", 14)
const font_ubuntu_monospace_italic_14  = StyleFont("Ubuntu Mono", 14; italic = true)
const font_ubuntu_monospace_bold_14    = StyleFont("Ubuntu Mono", 14; weight = 700)

const font_ubuntu_monospace_regular_16 = StyleFont("Ubuntu Mono", 16)
const font_ubuntu_monospace_italic_16  = StyleFont("Ubuntu Mono", 16; italic = true)
const font_ubuntu_monospace_bold_16    = StyleFont("Ubuntu Mono", 16; weight = 700)

const font_ubuntu_monospace_regular_18 = StyleFont("Ubuntu Mono", 18)
const font_ubuntu_monospace_italic_18  = StyleFont("Ubuntu Mono", 18; italic = true)
const font_ubuntu_monospace_bold_18    = StyleFont("Ubuntu Mono", 18; weight = 700)

const font_ubuntu_monospace_regular_20 = StyleFont("Ubuntu Mono", 20)
const font_ubuntu_monospace_italic_20  = StyleFont("Ubuntu Mono", 20; italic = true)
const font_ubuntu_monospace_bold_20    = StyleFont("Ubuntu Mono", 20; weight = 700)

const font_ubuntu_monospace_regular_22 = StyleFont("Ubuntu Mono", 22)
const font_ubuntu_monospace_italic_22  = StyleFont("Ubuntu Mono", 22; italic = true)
const font_ubuntu_monospace_bold_22    = StyleFont("Ubuntu Mono", 22; weight = 700)

const font_ubuntu_monospace_regular_24 = StyleFont("Ubuntu Mono", 24)
const font_ubuntu_monospace_italic_24  = StyleFont("Ubuntu Mono", 24; italic = true)
const font_ubuntu_monospace_bold_24    = StyleFont("Ubuntu Mono", 24; weight = 700)

const font_ubuntu_monospace_regular_36 = StyleFont("Ubuntu Mono", 36)
const font_ubuntu_monospace_italic_36  = StyleFont("Ubuntu Mono", 36; italic = true)
const font_ubuntu_monospace_bold_36    = StyleFont("Ubuntu Mono", 36; weight = 700)

const font_ubuntu_monospace_regular_48 = StyleFont("Ubuntu Mono", 48)
const font_ubuntu_monospace_italic_48  = StyleFont("Ubuntu Mono", 48; italic = true)
const font_ubuntu_monospace_bold_48    = StyleFont("Ubuntu Mono", 48; weight = 700)

# ── Ubuntu ────────────────────────────────────────────────────────────────────

const font_ubuntu_regular_14 = StyleFont("Ubuntu", 14)
const font_ubuntu_italic_14  = StyleFont("Ubuntu", 14; italic = true)
const font_ubuntu_bold_14    = StyleFont("Ubuntu", 14; weight = 700)

const font_ubuntu_regular_16 = StyleFont("Ubuntu", 16)
const font_ubuntu_italic_16  = StyleFont("Ubuntu", 16; italic = true)
const font_ubuntu_bold_16    = StyleFont("Ubuntu", 16; weight = 700)

const font_ubuntu_regular_18 = StyleFont("Ubuntu", 18)
const font_ubuntu_italic_18  = StyleFont("Ubuntu", 18; italic = true)
const font_ubuntu_bold_18    = StyleFont("Ubuntu", 18; weight = 700)

const font_ubuntu_regular_20 = StyleFont("Ubuntu", 20)
const font_ubuntu_italic_20  = StyleFont("Ubuntu", 20; italic = true)
const font_ubuntu_bold_20    = StyleFont("Ubuntu", 20; weight = 700)

const font_ubuntu_regular_22 = StyleFont("Ubuntu", 22)
const font_ubuntu_italic_22  = StyleFont("Ubuntu", 22; italic = true)
const font_ubuntu_bold_22    = StyleFont("Ubuntu", 22; weight = 700)

const font_ubuntu_regular_24 = StyleFont("Ubuntu", 24)
const font_ubuntu_italic_24  = StyleFont("Ubuntu", 24; italic = true)
const font_ubuntu_bold_24    = StyleFont("Ubuntu", 24; weight = 700)

const font_ubuntu_regular_36 = StyleFont("Ubuntu", 36)
const font_ubuntu_italic_36  = StyleFont("Ubuntu", 36; italic = true)
const font_ubuntu_bold_36    = StyleFont("Ubuntu", 36; weight = 700)

# ── Liberation sans ───────────────────────────────────────────────────────────

const font_liberation_sans_regular_14 = StyleFont("Liberation Sans", 14)
const font_liberation_sans_italic_14  = StyleFont("Liberation Sans", 14; italic = true)
const font_liberation_sans_bold_14    = StyleFont("Liberation Sans", 14; weight = 700)

const font_liberation_sans_regular_16 = StyleFont("Liberation Sans", 16)
const font_liberation_sans_italic_16  = StyleFont("Liberation Sans", 16; italic = true)
const font_liberation_sans_bold_16    = StyleFont("Liberation Sans", 16; weight = 700)

const font_liberation_sans_regular_18 = StyleFont("Liberation Sans", 18)
const font_liberation_sans_italic_18  = StyleFont("Liberation Sans", 18; italic = true)
const font_liberation_sans_bold_18    = StyleFont("Liberation Sans", 18; weight = 700)

const font_liberation_sans_regular_20 = StyleFont("Liberation Sans", 20)
const font_liberation_sans_italic_20  = StyleFont("Liberation Sans", 20; italic = true)
const font_liberation_sans_bold_20    = StyleFont("Liberation Sans", 20; weight = 700)

const font_liberation_sans_regular_22 = StyleFont("Liberation Sans", 22)
const font_liberation_sans_italic_22  = StyleFont("Liberation Sans", 22; italic = true)
const font_liberation_sans_bold_22    = StyleFont("Liberation Sans", 22; weight = 700)

const font_liberation_sans_regular_24 = StyleFont("Liberation Sans", 24)
const font_liberation_sans_italic_24  = StyleFont("Liberation Sans", 24; italic = true)
const font_liberation_sans_bold_24    = StyleFont("Liberation Sans", 24; weight = 700)

const font_liberation_sans_regular_30 = StyleFont("Liberation Sans", 30)
const font_liberation_sans_italic_30  = StyleFont("Liberation Sans", 30; italic = true)
const font_liberation_sans_bold_30    = StyleFont("Liberation Sans", 30; weight = 700)

const font_liberation_sans_regular_36 = StyleFont("Liberation Sans", 36)
const font_liberation_sans_italic_36  = StyleFont("Liberation Sans", 36; italic = true)
const font_liberation_sans_bold_36    = StyleFont("Liberation Sans", 36; weight = 700)

# ── Liberation serif ──────────────────────────────────────────────────────────

const font_liberation_serif_regular_14 = StyleFont("Liberation Serif", 14)
const font_liberation_serif_italic_14  = StyleFont("Liberation Serif", 14; italic = true)
const font_liberation_serif_bold_14    = StyleFont("Liberation Serif", 14; weight = 700)

const font_liberation_serif_regular_16 = StyleFont("Liberation Serif", 16)
const font_liberation_serif_italic_16  = StyleFont("Liberation Serif", 16; italic = true)
const font_liberation_serif_bold_16    = StyleFont("Liberation Serif", 16; weight = 700)

const font_liberation_serif_regular_18 = StyleFont("Liberation Serif", 18)
const font_liberation_serif_italic_18  = StyleFont("Liberation Serif", 18; italic = true)
const font_liberation_serif_bold_18    = StyleFont("Liberation Serif", 18; weight = 700)

const font_liberation_serif_regular_20 = StyleFont("Liberation Serif", 20)
const font_liberation_serif_italic_20  = StyleFont("Liberation Serif", 20; italic = true)
const font_liberation_serif_bold_20    = StyleFont("Liberation Serif", 20; weight = 700)

const font_liberation_serif_regular_22 = StyleFont("Liberation Serif", 22)
const font_liberation_serif_italic_22  = StyleFont("Liberation Serif", 22; italic = true)
const font_liberation_serif_bold_22    = StyleFont("Liberation Serif", 22; weight = 700)

const font_liberation_serif_regular_24 = StyleFont("Liberation Serif", 24)
const font_liberation_serif_italic_24  = StyleFont("Liberation Serif", 24; italic = true)
const font_liberation_serif_bold_24    = StyleFont("Liberation Serif", 24; weight = 700)

const font_liberation_serif_regular_30 = StyleFont("Liberation Serif", 30)
const font_liberation_serif_italic_30  = StyleFont("Liberation Serif", 30; italic = true)
const font_liberation_serif_bold_30    = StyleFont("Liberation Serif", 30; weight = 700)

const font_liberation_serif_regular_36 = StyleFont("Liberation Serif", 36)
const font_liberation_serif_italic_36  = StyleFont("Liberation Serif", 36; italic = true)
const font_liberation_serif_bold_36    = StyleFont("Liberation Serif", 36; weight = 700)

const font_liberation_serif_regular_42 = StyleFont("Liberation Serif", 42)
const font_liberation_serif_italic_42  = StyleFont("Liberation Serif", 42; italic = true)
const font_liberation_serif_bold_42    = StyleFont("Liberation Serif", 42; weight = 700)

# ── DejaVu monospace ────────────────────────────────────────────────────────────
# Broad Unicode coverage (geometric shapes ▾▸▼►, arrows, emoticons ☺♥) absent
# from the Ubuntu/Liberation faces. A text in any font falls back to it for a
# glyph its own font lacks (`get_fallback_font_files`). A text whose glyphs must
# all share one face, such as a column of monospaced marks, uses it directly.

const font_dejavu_monospace_regular_14 = StyleFont("DejaVu Sans Mono", 14)
const font_dejavu_monospace_italic_14  = StyleFont("DejaVu Sans Mono", 14; italic = true)
const font_dejavu_monospace_bold_14    = StyleFont("DejaVu Sans Mono", 14; weight = 700)

const font_dejavu_monospace_regular_16 = StyleFont("DejaVu Sans Mono", 16)
const font_dejavu_monospace_italic_16  = StyleFont("DejaVu Sans Mono", 16; italic = true)
const font_dejavu_monospace_bold_16    = StyleFont("DejaVu Sans Mono", 16; weight = 700)

const font_dejavu_monospace_regular_18 = StyleFont("DejaVu Sans Mono", 18)
const font_dejavu_monospace_italic_18  = StyleFont("DejaVu Sans Mono", 18; italic = true)
const font_dejavu_monospace_bold_18    = StyleFont("DejaVu Sans Mono", 18; weight = 700)

const font_dejavu_monospace_regular_20 = StyleFont("DejaVu Sans Mono", 20)
const font_dejavu_monospace_italic_20  = StyleFont("DejaVu Sans Mono", 20; italic = true)
const font_dejavu_monospace_bold_20    = StyleFont("DejaVu Sans Mono", 20; weight = 700)

const font_dejavu_monospace_regular_22 = StyleFont("DejaVu Sans Mono", 22)
const font_dejavu_monospace_italic_22  = StyleFont("DejaVu Sans Mono", 22; italic = true)
const font_dejavu_monospace_bold_22    = StyleFont("DejaVu Sans Mono", 22; weight = 700)

const font_dejavu_monospace_regular_24 = StyleFont("DejaVu Sans Mono", 24)
const font_dejavu_monospace_italic_24  = StyleFont("DejaVu Sans Mono", 24; italic = true)
const font_dejavu_monospace_bold_24    = StyleFont("DejaVu Sans Mono", 24; weight = 700)

const font_dejavu_monospace_regular_36 = StyleFont("DejaVu Sans Mono", 36)
const font_dejavu_monospace_italic_36  = StyleFont("DejaVu Sans Mono", 36; italic = true)
const font_dejavu_monospace_bold_36    = StyleFont("DejaVu Sans Mono", 36; weight = 700)

const font_dejavu_monospace_regular_48 = StyleFont("DejaVu Sans Mono", 48)
const font_dejavu_monospace_italic_48  = StyleFont("DejaVu Sans Mono", 48; italic = true)
const font_dejavu_monospace_bold_48    = StyleFont("DejaVu Sans Mono", 48; weight = 700)

# ── DejaVu sans ─────────────────────────────────────────────────────────────────
# Proportional companion. Adds the modern Emoticons block (😀…) as monochrome
# outlines on top of the symbol coverage above — for assistant/LLM text.

const font_dejavu_sans_regular_14 = StyleFont("DejaVu Sans", 14)
const font_dejavu_sans_italic_14  = StyleFont("DejaVu Sans", 14; italic = true)
const font_dejavu_sans_bold_14    = StyleFont("DejaVu Sans", 14; weight = 700)

const font_dejavu_sans_regular_16 = StyleFont("DejaVu Sans", 16)
const font_dejavu_sans_italic_16  = StyleFont("DejaVu Sans", 16; italic = true)
const font_dejavu_sans_bold_16    = StyleFont("DejaVu Sans", 16; weight = 700)

const font_dejavu_sans_regular_18 = StyleFont("DejaVu Sans", 18)
const font_dejavu_sans_italic_18  = StyleFont("DejaVu Sans", 18; italic = true)
const font_dejavu_sans_bold_18    = StyleFont("DejaVu Sans", 18; weight = 700)

const font_dejavu_sans_regular_20 = StyleFont("DejaVu Sans", 20)
const font_dejavu_sans_italic_20  = StyleFont("DejaVu Sans", 20; italic = true)
const font_dejavu_sans_bold_20    = StyleFont("DejaVu Sans", 20; weight = 700)

const font_dejavu_sans_regular_22 = StyleFont("DejaVu Sans", 22)
const font_dejavu_sans_italic_22  = StyleFont("DejaVu Sans", 22; italic = true)
const font_dejavu_sans_bold_22    = StyleFont("DejaVu Sans", 22; weight = 700)

const font_dejavu_sans_regular_24 = StyleFont("DejaVu Sans", 24)
const font_dejavu_sans_italic_24  = StyleFont("DejaVu Sans", 24; italic = true)
const font_dejavu_sans_bold_24    = StyleFont("DejaVu Sans", 24; weight = 700)

const font_dejavu_sans_regular_36 = StyleFont("DejaVu Sans", 36)
const font_dejavu_sans_italic_36  = StyleFont("DejaVu Sans", 36; italic = true)
const font_dejavu_sans_bold_36    = StyleFont("DejaVu Sans", 36; weight = 700)

# ── Lucide icons ────────────────────────────────────────────────────────────────

# The icon font of the widget layer: every glyph is a picture, at a code point of
# the private use area. An icon draws its glyph at the size of its box, so this
# size is only the size of a label written in this font.
const font_lucide_icons_20 = StyleFont("Lucide", 20)
