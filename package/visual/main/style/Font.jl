"""
    FontModule

Font style value type and named font constants. Fonts are identified by a
file path and a point size.
"""
module FontModule

import ..CellModule: Cell, set_value!

export StyleFont, make_style_font, font_scaled_size, font_logical_size, font_device_size,
       _DISPLAY_SCALE, _BASE_DISPLAY_SCALE, _USER_ZOOM, _FONT_ZOOM,
       recompute_display_scale!, adjust_user_zoom!, adjust_font_zoom!, _FONT_DIR,
       font_inconsolata_regular_18,
       font_ubuntu_monospace_regular_14, font_ubuntu_monospace_italic_14, font_ubuntu_monospace_bold_14,
       font_ubuntu_monospace_regular_16, font_ubuntu_monospace_italic_16, font_ubuntu_monospace_bold_16,
       font_ubuntu_monospace_regular_18, font_ubuntu_monospace_italic_18, font_ubuntu_monospace_bold_18,
       font_ubuntu_monospace_regular_20, font_ubuntu_monospace_italic_20, font_ubuntu_monospace_bold_20,
       font_ubuntu_monospace_regular_22, font_ubuntu_monospace_italic_22, font_ubuntu_monospace_bold_22,
       font_ubuntu_monospace_regular_24, font_ubuntu_monospace_italic_24, font_ubuntu_monospace_bold_24,
       font_ubuntu_monospace_regular_36, font_ubuntu_monospace_italic_36, font_ubuntu_monospace_bold_36,
       font_ubuntu_monospace_regular_48, font_ubuntu_monospace_italic_48, font_ubuntu_monospace_bold_48,
       font_ubuntu_regular_14, font_ubuntu_italic_14, font_ubuntu_bold_14,
       font_ubuntu_regular_16, font_ubuntu_italic_16, font_ubuntu_bold_16,
       font_ubuntu_regular_18, font_ubuntu_italic_18, font_ubuntu_bold_18,
       font_ubuntu_regular_20, font_ubuntu_italic_20, font_ubuntu_bold_20,
       font_ubuntu_regular_22, font_ubuntu_italic_22, font_ubuntu_bold_22,
       font_ubuntu_regular_24, font_ubuntu_italic_24, font_ubuntu_bold_24,
       font_ubuntu_regular_36, font_ubuntu_italic_36, font_ubuntu_bold_36,
       font_liberation_sans_regular_14, font_liberation_sans_italic_14, font_liberation_sans_bold_14,
       font_liberation_sans_regular_16, font_liberation_sans_italic_16, font_liberation_sans_bold_16,
       font_liberation_sans_regular_18, font_liberation_sans_italic_18, font_liberation_sans_bold_18,
       font_liberation_sans_regular_20, font_liberation_sans_italic_20, font_liberation_sans_bold_20,
       font_liberation_sans_regular_22, font_liberation_sans_italic_22, font_liberation_sans_bold_22,
       font_liberation_sans_regular_24, font_liberation_sans_italic_24, font_liberation_sans_bold_24,
       font_liberation_sans_regular_30, font_liberation_sans_italic_30, font_liberation_sans_bold_30,
       font_liberation_sans_regular_36, font_liberation_sans_italic_36, font_liberation_sans_bold_36,
       font_liberation_serif_regular_14, font_liberation_serif_italic_14, font_liberation_serif_bold_14,
       font_liberation_serif_regular_16, font_liberation_serif_italic_16, font_liberation_serif_bold_16,
       font_liberation_serif_regular_18, font_liberation_serif_italic_18, font_liberation_serif_bold_18,
       font_liberation_serif_regular_20, font_liberation_serif_italic_20, font_liberation_serif_bold_20,
       font_liberation_serif_regular_22, font_liberation_serif_italic_22, font_liberation_serif_bold_22,
       font_liberation_serif_regular_24, font_liberation_serif_italic_24, font_liberation_serif_bold_24,
       font_liberation_serif_regular_30, font_liberation_serif_italic_30, font_liberation_serif_bold_30,
       font_liberation_serif_regular_36, font_liberation_serif_italic_36, font_liberation_serif_bold_36,
       font_liberation_serif_regular_42, font_liberation_serif_italic_42, font_liberation_serif_bold_42,
       font_dejavu_monospace_regular_14, font_dejavu_monospace_italic_14, font_dejavu_monospace_bold_14,
       font_dejavu_monospace_regular_16, font_dejavu_monospace_italic_16, font_dejavu_monospace_bold_16,
       font_dejavu_monospace_regular_18, font_dejavu_monospace_italic_18, font_dejavu_monospace_bold_18,
       font_dejavu_monospace_regular_20, font_dejavu_monospace_italic_20, font_dejavu_monospace_bold_20,
       font_dejavu_monospace_regular_22, font_dejavu_monospace_italic_22, font_dejavu_monospace_bold_22,
       font_dejavu_monospace_regular_24, font_dejavu_monospace_italic_24, font_dejavu_monospace_bold_24,
       font_dejavu_monospace_regular_36, font_dejavu_monospace_italic_36, font_dejavu_monospace_bold_36,
       font_dejavu_monospace_regular_48, font_dejavu_monospace_italic_48, font_dejavu_monospace_bold_48,
       font_dejavu_sans_regular_14, font_dejavu_sans_italic_14, font_dejavu_sans_bold_14,
       font_dejavu_sans_regular_16, font_dejavu_sans_italic_16, font_dejavu_sans_bold_16,
       font_dejavu_sans_regular_18, font_dejavu_sans_italic_18, font_dejavu_sans_bold_18,
       font_dejavu_sans_regular_20, font_dejavu_sans_italic_20, font_dejavu_sans_bold_20,
       font_dejavu_sans_regular_22, font_dejavu_sans_italic_22, font_dejavu_sans_bold_22,
       font_dejavu_sans_regular_24, font_dejavu_sans_italic_24, font_dejavu_sans_bold_24,
       font_dejavu_sans_regular_36, font_dejavu_sans_italic_36, font_dejavu_sans_bold_36

# ── Document ──────────────────────────────────────────────────────────────────

"""
    StyleFont(filename, size)

A font style value consisting of a file path and a point size.
"""
struct StyleFont
    filename::String
    size::Int
end

# ── Construction ──────────────────────────────────────────────────────────────

make_style_font(filename::AbstractString, size::Integer) = StyleFont(filename, size)

# ── Readability scaling: display scale + zoom knobs ─────────────────────────────
#
# `_DISPLAY_SCALE` is the *effective* logical→device factor everything reads. It
# is the product of two independently-set inputs:
#
#   _BASE_DISPLAY_SCALE — the display's DPI scale, detected once by the SDL
#                         backend at window open (the role this factor played
#                         before user zoom existed).
#   _USER_ZOOM          — the user's *uniform* readability zoom (Ctrl+=/-/0),
#                         1.0 by default. Magnifies everything because it feeds
#                         the device-edge scale uniformly.
#
# `recompute_display_scale!()` folds them back into `_DISPLAY_SCALE`. Keep these
# as plain `Ref`s: layout never reads the display scale (it is scale-invariant —
# see plan/done/global-display-scale.md), so changing it needs no reactive
# invalidation, only a backend repaint.
const _BASE_DISPLAY_SCALE = Ref(1.0)
const _USER_ZOOM          = Ref(1.0)
const _DISPLAY_SCALE      = Ref(1.0)

recompute_display_scale!() = (_DISPLAY_SCALE[] = _BASE_DISPLAY_SCALE[] * _USER_ZOOM[])

# `_FONT_ZOOM` is the *font-only* readability zoom (Ctrl+Alt+=/-/0): it scales the
# *logical* size of text so text-derived layout reflows bigger while fixed
# geometry (paddings, image boxes, explicit spacing) stays put. Unlike the
# display scale, layout DOES read it (`font_logical_size`), so it must be a
# reactive `Cell` — writing it invalidates the text-layout cells that read it
# during their thunks, which is what makes a font-zoom change relayout. A plain
# value would leave those cached layouts stale (see package/kernel/doc/cell.md).
const _FONT_ZOOM = Cell(1.0)

"""
    font_scaled_size(size::Integer) -> Int

Device-pixel size at which a logical font `size` must be *rasterized* so that,
once the renderer is scaled by [`_DISPLAY_SCALE`](@ref), the glyph lands 1:1 on
device pixels and stays crisp. Backend-only: layout measures and positions text
in logical pixels (via [`font_logical_size`](@ref)), never through this.
"""
font_scaled_size(size::Integer) = max(1, round(Int, size * _DISPLAY_SCALE[]))

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
    font_device_size(font::StyleFont) -> Int

A font's size in *device* pixels: the logical (font-zoomed) size scaled by the
display factor. The size the backend rasterizes glyphs at. Equals
`font_scaled_size(font.size)` at the default font zoom.
"""
font_device_size(font::StyleFont) = max(1, round(Int, font.size * _FONT_ZOOM[] * _DISPLAY_SCALE[]))

# Discrete, browser-like zoom factors and a stepper that snaps `cur` to the
# nearest one then moves `delta` steps (clamped). `delta == 0` resets to 1.0.
const _ZOOM_STEPS = (0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0)
function _stepped_zoom(cur::Real, delta::Integer)
    delta == 0 && return 1.0
    i = argmin(abs.(collect(_ZOOM_STEPS) .- cur))
    _ZOOM_STEPS[clamp(i + delta, 1, length(_ZOOM_STEPS))]
end

"""
    adjust_user_zoom!(delta::Integer) -> Float64

Step the uniform display zoom (+1 in, -1 out, 0 reset) and refold it into
`_DISPLAY_SCALE`. Returns the new `_USER_ZOOM`.
"""
function adjust_user_zoom!(delta::Integer)
    _USER_ZOOM[] = _stepped_zoom(_USER_ZOOM[], delta)
    recompute_display_scale!()
    _USER_ZOOM[]
end

"""
    adjust_font_zoom!(delta::Integer) -> Float64

Step the font-only zoom (+1 in, -1 out, 0 reset). Writes the reactive `_FONT_ZOOM`
cell via `set_value!`, which invalidates the text-layout cells that read it so the
next print relayouts. Returns the new font zoom.
"""
function adjust_font_zoom!(delta::Integer)
    set_value!(_FONT_ZOOM, _stepped_zoom(_FONT_ZOOM[], delta))
    _FONT_ZOOM[]
end

# ── Font directory ─────────────────────────────────────────────────────────────

const _FONT_DIR = joinpath(@__DIR__, "../../../../asset/font")

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
# from the Ubuntu/Liberation faces. Used for the fold markers and anywhere a glyph
# outside basic Latin must render under the monochrome SDL_ttf pipeline.

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

end # module
