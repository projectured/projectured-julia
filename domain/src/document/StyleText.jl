"""
    StyleTextModule

Combined text style value type. A `StyleText` bundles the two values needed to
draw a run of text — a [`StyleFont`](@ref) and a [`StyleColor`](@ref) — so a
renderer can take one argument instead of a loose `(font, color)` pair, and so a
theme can expose *semantic* text styles (body, title, caption, label) rather
than separate fonts and colors. Mirrors the plain-value convention of
`StyleColor` / `StyleFont`.
"""
module StyleTextModule

import ..FontModule: StyleFont
import ..ColorModule: StyleColor

export StyleText, make_style_text

# ── Document ──────────────────────────────────────────────────────────────────

"""
    StyleText(font, color)

A text style value: the `font` to draw with and the `color` to draw in.
"""
struct StyleText
    font::StyleFont
    color::StyleColor
end

# ── Construction ──────────────────────────────────────────────────────────────

make_style_text(font::StyleFont, color::StyleColor) = StyleText(font, color)

function Base.show(io::IO, style::StyleText)
    print(io, "StyleText(", style.font, ", ", style.color, ")")
end

end # module
