function make_text_document_example()
    regular = StyleFont("Ubuntu Mono", 20)
    nl() = TextNewline(font=regular)
    TextBlock(
        TextString("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Cras eu nunc nibh. Cras imperdiet faucibus tortor ac dictum. Aliquam sit amet justo nec ligula lobortis ornare. Aenean a odio id dolor adipiscing interdum. Maecenas nec nisl neque. Suspendisse interdum rutrum neque, in volutpat orci varius in. Praesent a ipsum ac erat pulvinar adipiscing quis sit amet magna. Etiam semper vulputate mi ac interdum. Nunc a tortor non purus fringilla aliquam.", regular, color_default),
    )
end

# A short, fixed multi-line text — one `TextString` span per line, separated by
# explicit `TextNewline`s, so there is no word wrapping. Paired with
# `make_plain_text_projection_example` (a bare `TextToGraphics`), this is the
# minimal pipeline for watching the renderer's dirty rectangle: moving the caret
# should repaint only the caret slivers, not the whole block.
function make_plain_text_document_example()
    regular = StyleFont("Ubuntu Mono", 20)
    nl() = TextNewline(font=regular)
    TextBlock(
        TextString("The quick brown fox", regular, color_default), nl(),
        TextString("jumps over the lazy dog.", regular, color_default), nl(),
        TextString("Move the caret around and", regular, color_default), nl(),
        TextString("watch the dirty rectangle:", regular, color_default), nl(),
        TextString("only the caret should repaint,", regular, color_default), nl(),
        TextString("not the whole block.", regular, color_default), nl(),
        TextString("Each line is its own span;", regular, color_default), nl(),
        TextString("there is no word wrapping here.", regular, color_default),
    )
end

# Inline images (and icons) flowing with text. A large image and a small icon
# sit on the same baseline as the surrounding words; the line grows to the
# tallest glyph and the cursor can land before or after each image.
function make_text_with_image_example()
    regular = StyleFont("Ubuntu Mono", 20)
    photo = _load_inline_image("projectured.png")
    icon  = _load_inline_image("file.png")
    TextBlock(
        TextString("Inline images flow with text ", regular, color_default),
        TextGraphics(photo, 64, 64),
        TextString(" and small icons ", regular, color_default),
        TextGraphics(icon, 24, 24),
        TextString(" sit on the same line as the surrounding words. The line height grows to fit the tallest glyph, and the cursor can be placed before or after each image.", regular, color_default),
    )
end

# Build an ImageFile whose decoded RGBA pixels are produced lazily — the
# decode thunk runs only when the image is actually rendered (when an SDL
# video context exists), so constructing the example document never touches
# SDL. A decode failure degrades to `nothing` rather than throwing.
function _load_inline_image(name::AbstractString)
    path = joinpath(@__DIR__, "..", "..", "asset", "image", name)
    img = ImageFile(path)
    set_cell_computation!(getfield(img, :raw), () -> begin
        try
            decode_image(path)
        catch
            nothing
        end
    end)
    img
end

# ── Atomic text documents ───────────────────────────────────────────────────
# One minimal `TextBlock` per text structure — the hand-authored building blocks
# the discovered catalog turns into `text/<name>/{text,graphics}` examples,
# mirroring the JSON leaf/compound atoms (`make_json_string_document_example`, …).
# The default text projection (WordWrapping → TextToGraphics) renders a `TextBlock`
# root, so every atom is a block that exercises one span/structure type: a plain
# `TextString`, an explicit line break (`TextNewline`), inter-word `TextSpacing`,
# an inline `TextGraphics` image, and a `TextLine`-structured (indented) block.
# `make_document` is a thunk, so each derived example gets a fresh instance.

_atom_font() = StyleFont("Ubuntu Mono", 20)

make_text_string_document_example() =
    TextBlock(TextString("Hello", _atom_font(), color_default))

make_text_newline_document_example() =
    TextBlock(
        TextString("first", _atom_font(), color_default),
        TextNewline(font=_atom_font()),
        TextString("second", _atom_font(), color_default),
    )

make_text_spacing_document_example() =
    TextBlock(
        TextString("left", _atom_font(), color_default),
        TextSpacing(4; font=_atom_font()),
        TextString("right", _atom_font(), color_default),
    )

make_text_graphics_document_example() =
    TextBlock(
        TextString("logo ", _atom_font(), color_default),
        TextGraphics(_load_inline_image("file.png"), 24, 24),
    )

make_text_line_document_example() =
    TextBlock(
        TextLine(TextString("alpha", _atom_font(), color_default); indentation=2),
        TextLine(TextString("beta",  _atom_font(), color_default); indentation=4),
    )

# ── Bare span documents ─────────────────────────────────────────────────────
# `TextString`/`TextNewline`/`TextLine` each have their own printer
# (`TextStringToString`, `TextNewlineToString`, `TextLineToString`) that takes
# the span directly, not wrapped in a `TextBlock`. The atoms above exercise a
# span as one element of a block; these stand alone as the span itself.
# `_atom` disambiguates the factory name from the block-wrapped one above.

make_text_string_atom_document_example() = TextString("Hello")

make_text_newline_atom_document_example() = TextNewline(font=_atom_font())

make_text_line_atom_document_example() =
    TextLine(TextString("alpha", _atom_font(), color_default); indentation=2)
