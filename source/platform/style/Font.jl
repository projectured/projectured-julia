# Fragment of `StyleModule`.
#
# Font style value type and named font constants. Fonts are identified by a
# file path and a point size.
# ── Document ──────────────────────────────────────────────────────────────────

# A value-document: `filename`/`size` are immutable by default; the selection is
# typed `Nothing` (non-selectable, so `StyleFont` — the bare form — inlines in a
# config cell). `RCStyleFont` gives a reactive, selectable, editable font.
"""
    StyleFont(filename, size)

A font: the file it is drawn from, and how large.

Use it to say how words look: which typeface a label, a heading or a block of
code is drawn in, and at what size. A backend loads the file and measures the
words with it.

# Example

    StyleFont("DejaVuSans.ttf", 14)

See also `StyleText`, which pairs a font with a colour, and `GraphicsText`.
"""
@document ImmutableCell [DC] struct StyleFont
    filename::String
    size::Int
    selection::Nothing
end

# ── Construction ──────────────────────────────────────────────────────────────

make_style_font(filename::AbstractString, size::Integer) = StyleFont(filename, size)

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

const font_inconsolata_regular_18 = StyleFont(joinpath(_FONT_DIR, "Inconsolata.otf"), 18)

# ── Ubuntu monospace ──────────────────────────────────────────────────────────

const font_ubuntu_monospace_regular_14 = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-R.ttf"), 14)
const font_ubuntu_monospace_italic_14  = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-RI.ttf"), 14)
const font_ubuntu_monospace_bold_14    = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-B.ttf"), 14)

const font_ubuntu_monospace_regular_16 = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-R.ttf"), 16)
const font_ubuntu_monospace_italic_16  = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-RI.ttf"), 16)
const font_ubuntu_monospace_bold_16    = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-B.ttf"), 16)

const font_ubuntu_monospace_regular_18 = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-R.ttf"), 18)
const font_ubuntu_monospace_italic_18  = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-RI.ttf"), 18)
const font_ubuntu_monospace_bold_18    = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-B.ttf"), 18)

const font_ubuntu_monospace_regular_20 = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-R.ttf"), 20)
const font_ubuntu_monospace_italic_20  = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-RI.ttf"), 20)
const font_ubuntu_monospace_bold_20    = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-B.ttf"), 20)

const font_ubuntu_monospace_regular_22 = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-R.ttf"), 22)
const font_ubuntu_monospace_italic_22  = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-RI.ttf"), 22)
const font_ubuntu_monospace_bold_22    = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-B.ttf"), 22)

const font_ubuntu_monospace_regular_24 = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-R.ttf"), 24)
const font_ubuntu_monospace_italic_24  = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-RI.ttf"), 24)
const font_ubuntu_monospace_bold_24    = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-B.ttf"), 24)

const font_ubuntu_monospace_regular_36 = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-R.ttf"), 36)
const font_ubuntu_monospace_italic_36  = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-RI.ttf"), 36)
const font_ubuntu_monospace_bold_36    = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-B.ttf"), 36)

const font_ubuntu_monospace_regular_48 = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-R.ttf"), 48)
const font_ubuntu_monospace_italic_48  = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-RI.ttf"), 48)
const font_ubuntu_monospace_bold_48    = StyleFont(joinpath(_FONT_DIR, "UbuntuMono-B.ttf"), 48)

# ── Ubuntu ────────────────────────────────────────────────────────────────────

const font_ubuntu_regular_14 = StyleFont(joinpath(_FONT_DIR, "Ubuntu-R.ttf"), 14)
const font_ubuntu_italic_14  = StyleFont(joinpath(_FONT_DIR, "Ubuntu-RI.ttf"), 14)
const font_ubuntu_bold_14    = StyleFont(joinpath(_FONT_DIR, "Ubuntu-B.ttf"), 14)

const font_ubuntu_regular_16 = StyleFont(joinpath(_FONT_DIR, "Ubuntu-R.ttf"), 16)
const font_ubuntu_italic_16  = StyleFont(joinpath(_FONT_DIR, "Ubuntu-RI.ttf"), 16)
const font_ubuntu_bold_16    = StyleFont(joinpath(_FONT_DIR, "Ubuntu-B.ttf"), 16)

const font_ubuntu_regular_18 = StyleFont(joinpath(_FONT_DIR, "Ubuntu-R.ttf"), 18)
const font_ubuntu_italic_18  = StyleFont(joinpath(_FONT_DIR, "Ubuntu-RI.ttf"), 18)
const font_ubuntu_bold_18    = StyleFont(joinpath(_FONT_DIR, "Ubuntu-B.ttf"), 18)

const font_ubuntu_regular_20 = StyleFont(joinpath(_FONT_DIR, "Ubuntu-R.ttf"), 20)
const font_ubuntu_italic_20  = StyleFont(joinpath(_FONT_DIR, "Ubuntu-RI.ttf"), 20)
const font_ubuntu_bold_20    = StyleFont(joinpath(_FONT_DIR, "Ubuntu-B.ttf"), 20)

const font_ubuntu_regular_22 = StyleFont(joinpath(_FONT_DIR, "Ubuntu-R.ttf"), 22)
const font_ubuntu_italic_22  = StyleFont(joinpath(_FONT_DIR, "Ubuntu-RI.ttf"), 22)
const font_ubuntu_bold_22    = StyleFont(joinpath(_FONT_DIR, "Ubuntu-B.ttf"), 22)

const font_ubuntu_regular_24 = StyleFont(joinpath(_FONT_DIR, "Ubuntu-R.ttf"), 24)
const font_ubuntu_italic_24  = StyleFont(joinpath(_FONT_DIR, "Ubuntu-RI.ttf"), 24)
const font_ubuntu_bold_24    = StyleFont(joinpath(_FONT_DIR, "Ubuntu-B.ttf"), 24)

const font_ubuntu_regular_36 = StyleFont(joinpath(_FONT_DIR, "Ubuntu-R.ttf"), 36)
const font_ubuntu_italic_36  = StyleFont(joinpath(_FONT_DIR, "Ubuntu-RI.ttf"), 36)
const font_ubuntu_bold_36    = StyleFont(joinpath(_FONT_DIR, "Ubuntu-B.ttf"), 36)

# ── Liberation sans ───────────────────────────────────────────────────────────

const font_liberation_sans_regular_14 = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Regular.ttf"), 14)
const font_liberation_sans_italic_14  = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Italic.ttf"), 14)
const font_liberation_sans_bold_14    = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Bold.ttf"), 14)

const font_liberation_sans_regular_16 = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Regular.ttf"), 16)
const font_liberation_sans_italic_16  = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Italic.ttf"), 16)
const font_liberation_sans_bold_16    = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Bold.ttf"), 16)

const font_liberation_sans_regular_18 = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Regular.ttf"), 18)
const font_liberation_sans_italic_18  = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Italic.ttf"), 18)
const font_liberation_sans_bold_18    = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Bold.ttf"), 18)

const font_liberation_sans_regular_20 = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Regular.ttf"), 20)
const font_liberation_sans_italic_20  = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Italic.ttf"), 20)
const font_liberation_sans_bold_20    = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Bold.ttf"), 20)

const font_liberation_sans_regular_22 = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Regular.ttf"), 22)
const font_liberation_sans_italic_22  = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Italic.ttf"), 22)
const font_liberation_sans_bold_22    = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Bold.ttf"), 22)

const font_liberation_sans_regular_24 = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Regular.ttf"), 24)
const font_liberation_sans_italic_24  = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Italic.ttf"), 24)
const font_liberation_sans_bold_24    = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Bold.ttf"), 24)

const font_liberation_sans_regular_30 = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Regular.ttf"), 30)
const font_liberation_sans_italic_30  = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Italic.ttf"), 30)
const font_liberation_sans_bold_30    = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Bold.ttf"), 30)

const font_liberation_sans_regular_36 = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Regular.ttf"), 36)
const font_liberation_sans_italic_36  = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Italic.ttf"), 36)
const font_liberation_sans_bold_36    = StyleFont(joinpath(_FONT_DIR, "LiberationSans-Bold.ttf"), 36)

# ── Liberation serif ──────────────────────────────────────────────────────────

const font_liberation_serif_regular_14 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 14)
const font_liberation_serif_italic_14  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 14)
const font_liberation_serif_bold_14    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 14)

const font_liberation_serif_regular_16 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 16)
const font_liberation_serif_italic_16  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 16)
const font_liberation_serif_bold_16    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 16)

const font_liberation_serif_regular_18 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 18)
const font_liberation_serif_italic_18  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 18)
const font_liberation_serif_bold_18    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 18)

const font_liberation_serif_regular_20 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 20)
const font_liberation_serif_italic_20  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 20)
const font_liberation_serif_bold_20    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 20)

const font_liberation_serif_regular_22 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 22)
const font_liberation_serif_italic_22  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 22)
const font_liberation_serif_bold_22    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 22)

const font_liberation_serif_regular_24 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 24)
const font_liberation_serif_italic_24  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 24)
const font_liberation_serif_bold_24    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 24)

const font_liberation_serif_regular_30 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 30)
const font_liberation_serif_italic_30  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 30)
const font_liberation_serif_bold_30    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 30)

const font_liberation_serif_regular_36 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 36)
const font_liberation_serif_italic_36  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 36)
const font_liberation_serif_bold_36    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 36)

const font_liberation_serif_regular_42 = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Regular.ttf"), 42)
const font_liberation_serif_italic_42  = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Italic.ttf"), 42)
const font_liberation_serif_bold_42    = StyleFont(joinpath(_FONT_DIR, "LiberationSerif-Bold.ttf"), 42)

# ── DejaVu monospace ────────────────────────────────────────────────────────────
# Broad Unicode coverage (geometric shapes ▾▸▼►, arrows, emoticons ☺♥) absent
# from the Ubuntu/Liberation faces. A text in any font falls back to it for a
# glyph its own font lacks (`get_fallback_font_files`). A text whose glyphs must
# all share one face, such as a column of monospaced marks, uses it directly.

const font_dejavu_monospace_regular_14 = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono.ttf"), 14)
const font_dejavu_monospace_italic_14  = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Oblique.ttf"), 14)
const font_dejavu_monospace_bold_14    = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf"), 14)

const font_dejavu_monospace_regular_16 = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono.ttf"), 16)
const font_dejavu_monospace_italic_16  = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Oblique.ttf"), 16)
const font_dejavu_monospace_bold_16    = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf"), 16)

const font_dejavu_monospace_regular_18 = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono.ttf"), 18)
const font_dejavu_monospace_italic_18  = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Oblique.ttf"), 18)
const font_dejavu_monospace_bold_18    = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf"), 18)

const font_dejavu_monospace_regular_20 = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono.ttf"), 20)
const font_dejavu_monospace_italic_20  = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Oblique.ttf"), 20)
const font_dejavu_monospace_bold_20    = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf"), 20)

const font_dejavu_monospace_regular_22 = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono.ttf"), 22)
const font_dejavu_monospace_italic_22  = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Oblique.ttf"), 22)
const font_dejavu_monospace_bold_22    = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf"), 22)

const font_dejavu_monospace_regular_24 = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono.ttf"), 24)
const font_dejavu_monospace_italic_24  = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Oblique.ttf"), 24)
const font_dejavu_monospace_bold_24    = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf"), 24)

const font_dejavu_monospace_regular_36 = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono.ttf"), 36)
const font_dejavu_monospace_italic_36  = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Oblique.ttf"), 36)
const font_dejavu_monospace_bold_36    = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf"), 36)

const font_dejavu_monospace_regular_48 = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono.ttf"), 48)
const font_dejavu_monospace_italic_48  = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Oblique.ttf"), 48)
const font_dejavu_monospace_bold_48    = StyleFont(joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf"), 48)

# ── DejaVu sans ─────────────────────────────────────────────────────────────────
# Proportional companion. Adds the modern Emoticons block (😀…) as monochrome
# outlines on top of the symbol coverage above — for assistant/LLM text.

const font_dejavu_sans_regular_14 = StyleFont(joinpath(_FONT_DIR, "DejaVuSans.ttf"), 14)
const font_dejavu_sans_italic_14  = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Oblique.ttf"), 14)
const font_dejavu_sans_bold_14    = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Bold.ttf"), 14)

const font_dejavu_sans_regular_16 = StyleFont(joinpath(_FONT_DIR, "DejaVuSans.ttf"), 16)
const font_dejavu_sans_italic_16  = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Oblique.ttf"), 16)
const font_dejavu_sans_bold_16    = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Bold.ttf"), 16)

const font_dejavu_sans_regular_18 = StyleFont(joinpath(_FONT_DIR, "DejaVuSans.ttf"), 18)
const font_dejavu_sans_italic_18  = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Oblique.ttf"), 18)
const font_dejavu_sans_bold_18    = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Bold.ttf"), 18)

const font_dejavu_sans_regular_20 = StyleFont(joinpath(_FONT_DIR, "DejaVuSans.ttf"), 20)
const font_dejavu_sans_italic_20  = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Oblique.ttf"), 20)
const font_dejavu_sans_bold_20    = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Bold.ttf"), 20)

const font_dejavu_sans_regular_22 = StyleFont(joinpath(_FONT_DIR, "DejaVuSans.ttf"), 22)
const font_dejavu_sans_italic_22  = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Oblique.ttf"), 22)
const font_dejavu_sans_bold_22    = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Bold.ttf"), 22)

const font_dejavu_sans_regular_24 = StyleFont(joinpath(_FONT_DIR, "DejaVuSans.ttf"), 24)
const font_dejavu_sans_italic_24  = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Oblique.ttf"), 24)
const font_dejavu_sans_bold_24    = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Bold.ttf"), 24)

const font_dejavu_sans_regular_36 = StyleFont(joinpath(_FONT_DIR, "DejaVuSans.ttf"), 36)
const font_dejavu_sans_italic_36  = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Oblique.ttf"), 36)
const font_dejavu_sans_bold_36    = StyleFont(joinpath(_FONT_DIR, "DejaVuSans-Bold.ttf"), 36)

# ── Lucide icons ────────────────────────────────────────────────────────────────

# The icon font of the widget layer: every glyph is a picture, at a code point of
# the private use area. An icon draws its glyph at the size of its box, so this
# size is only the size of a label written in this font.
const font_lucide_icons_20 = StyleFont(joinpath(_FONT_DIR, "lucide.ttf"), 20)
