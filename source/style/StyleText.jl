# Fragment of `StyleModule`.
#
# Combined text style value type. A `StyleText` bundles the two values needed to
# draw a run of text — a [`StyleFont`](@ref) and a [`StyleColor`](@ref) — so a
# renderer can take one argument instead of a loose `(font, color)` pair, and so a
# theme can expose *semantic* text styles (body, title, caption, label) rather
# than separate fonts and colors. Mirrors the plain-value convention of
# `StyleColor` / `StyleFont`.
# ── Document ──────────────────────────────────────────────────────────────────

"""
    StyleText(font, color)

How words are drawn: the font to draw them with, and the colour to draw them
in.

Use it to give a piece of text one look: a heading, a comment, a word a search
matched. A projection of text carries one of these for each run of words it
draws.

# Example

    StyleText(StyleFont("DejaVuSans.ttf", 14), color_black)

See also `StyleFont`, `StyleColor` and `GraphicsText`.

A text style value: the `font` to draw with and the `color` to draw in.
"""
# A value-document. `[DC]` binds the bare name to the default spelling, so
# `StyleText` is concrete and inlines in a config cell — which is what 455 uses of
# `ImmutableCell{StyleText}` ask for. It is not isbits, because it carries a font
# `String`; neither was the plain form, so that is neutral. `ACStyleText` names the
# cell layout, and `RCStyleText` is its reactive, selectable, editable spelling.
@document ImmutableCell [DC] struct StyleText
    font::StyleFont
    color::StyleColor
    selection::Nothing
end

# ── Construction ──────────────────────────────────────────────────────────────

make_style_text(font::StyleFont, color::StyleColor) = StyleText(font, color)

function Base.show(io::IO, style::StyleText)
    print(io, "StyleText(", style.font, ", ", style.color, ")")
end
