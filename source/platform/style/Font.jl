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

# ── Readability zoom ──────────────────────────────────────────────────────────
#
# Two zooms change the size of text on the screen. The uniform zoom (Ctrl+= and
# Ctrl+-) is the `zoom` of the `Display` of an editor. A backend multiplies it
# into the ratio of device pixels to logical pixels, and layout does not read it.
# The font zoom (Ctrl+Alt+= and Ctrl+Alt+-) is `_FONT_ZOOM` below. Both zooms
# step through `_ZOOM_STEPS` with `step_zoom`.

# `_FONT_ZOOM` is the *font-only* readability zoom (Ctrl+Alt+=/-/0): it scales the
# *logical* size of text so text-derived layout reflows bigger while fixed
# geometry (paddings, image boxes, explicit spacing) stays put. Unlike the
# uniform zoom, layout DOES read it (`font_logical_size`), so it must be a
# reactive `Cell` — writing it invalidates the text-layout cells that read it
# during their thunks, which is what makes a font-zoom change relayout. A plain
# value would leave those cached layouts stale (see package/kernel/doc/cell.md).
const _FONT_ZOOM = Cell(1.0)

"""
    font_logical_size(font::StyleFont) -> Int

A font's size in *logical* pixels after the font-only zoom — what layout must use
in place of the raw `font.size`. At the default zoom (`_FONT_ZOOM == 1.0`) this is
exactly `font.size`, so every layout substitution is a no-op until the user zooms.
Reads the reactive `_FONT_ZOOM` cell, so callers inside computed cells relayout
when font zoom changes.
"""
font_logical_size(font::StyleFont) = max(1, round(Int, font.size * _FONT_ZOOM[]))

"""
    font_device_size(font::StyleFont, ratio::Real) -> Int

A font's size in device pixels: its logical size after the font zoom, times
`ratio`, the number of device pixels in one logical pixel. A backend rasterizes
the glyphs at this size, so that they land one to one on the device pixels.
"""
font_device_size(font::StyleFont, ratio::Real) =
    max(1, round(Int, font.size * _FONT_ZOOM[] * ratio))

# The zoom factors that `step_zoom` steps through, as in a web browser.
const _ZOOM_STEPS = (0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0)

"""
    step_zoom(zoom::Real, delta::Integer) -> Float64

The zoom `delta` steps away from `zoom` in the table of zoom factors: `+1` zooms
in, `-1` zooms out, and `0` gives `1.0`. A `zoom` between two factors counts as
the nearest one, and the result stays inside the table.
"""
function step_zoom(zoom::Real, delta::Integer)
    delta == 0 && return 1.0
    i = argmin(abs.(collect(_ZOOM_STEPS) .- zoom))
    _ZOOM_STEPS[clamp(i + delta, 1, length(_ZOOM_STEPS))]
end

"""
    adjust_font_zoom!(delta::Integer) -> Float64

Step the font-only zoom (+1 in, -1 out, 0 reset). Writes the reactive `_FONT_ZOOM`
cell via `set_cell_value!`, which invalidates the text-layout cells that read it so the
next print relayouts. Returns the new font zoom.
"""
function adjust_font_zoom!(delta::Integer)
    set_cell_value!(_FONT_ZOOM, step_zoom(_FONT_ZOOM[], delta))
    _FONT_ZOOM[]
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
