function make_text_document_example()
    regular = font_ubuntu_monospace_regular_24
    nl() = TextNewline(font=regular)
    document = TextText(
        TextString("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Cras eu nunc nibh. Cras imperdiet faucibus tortor ac dictum. Aliquam sit amet justo nec ligula lobortis ornare. Aenean a odio id dolor adipiscing interdum. Maecenas nec nisl neque. Suspendisse interdum rutrum neque, in volutpat orci varius in. Praesent a ipsum ac erat pulvinar adipiscing quis sit amet magna. Etiam semper vulputate mi ac interdum. Nunc a tortor non purus fringilla aliquam.", regular, color_default),
    )
    document
end

# A short, fixed multi-line text — one `TextString` span per line, separated by
# explicit `TextNewline`s, so there is no word wrapping. Paired with
# `make_plain_text_projection_example` (a bare `TextToGraphics`), this is the
# minimal pipeline for watching the renderer's dirty rectangle: moving the caret
# should repaint only the caret slivers, not the whole block.
function make_plain_text_document_example()
    regular = font_ubuntu_monospace_regular_24
    nl() = TextNewline(font=regular)
    TextText(
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
    regular = font_ubuntu_monospace_regular_24
    photo = _load_inline_image("projectured.png")
    icon  = _load_inline_image("file.png")
    document = TextText(
        TextString("Inline images flow with text ", regular, color_default),
        TextGraphics(photo, 64, 64),
        TextString(" and small icons ", regular, color_default),
        TextGraphics(icon, 24, 24),
        TextString(" sit on the same line as the surrounding words. The line height grows to fit the tallest glyph, and the cursor can be placed before or after each image.", regular, color_default),
    )
    document
end

# Build an ImageFile whose decoded RGBA pixels are produced lazily — the
# decode thunk runs only when the image is actually rendered (when an SDL
# video context exists), so constructing the example document never touches
# SDL. A decode failure degrades to `nothing` rather than throwing.
function _load_inline_image(name::AbstractString)
    path = joinpath(@__DIR__, "..", "..", "..", "image", name)
    img = ImageFile(path)
    setfn!(getfield(img, :raw), () -> begin
        try
            sdl_decode_image(path)
        catch
            nothing
        end
    end)
    img
end
