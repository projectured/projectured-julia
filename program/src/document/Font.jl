"""
    FontModule

Font style value type and named font constants. Fonts are identified by a
file path and a point size.
"""
module FontModule

export StyleFont, make_style_font, font_scaled_size, _FONT_SCALE, _FONT_DIR,
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
       font_liberation_serif_regular_42, font_liberation_serif_italic_42, font_liberation_serif_bold_42

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

# ── DPI-based font scale ──────────────────────────────────────────────────────

# Multiplier applied to every StyleFont.size before opening, measuring, or
# hit-testing, so that named fonts (e.g. `font_*_24`) look ~the same physical
# size on every display. Set by the SDL backend from SDL_GetDisplayDPI at
# window open; defaults to 1.0 (no scaling).
const _FONT_SCALE = Ref(1.0)

"""
    font_scaled_size(size::Integer) -> Int

Logical font size multiplied by the current display-DPI font scale.
"""
font_scaled_size(size::Integer) = max(1, round(Int, size * _FONT_SCALE[]))

# ── Font directory ─────────────────────────────────────────────────────────────

const _FONT_DIR = joinpath(@__DIR__, "../../../font")

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

end # module
