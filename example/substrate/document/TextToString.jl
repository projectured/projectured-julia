function make_text_to_string_document_example()
    nl = TextNewline(font=font_ubuntu_monospace_regular_14)
    TextBlock(
        TextString("Hello", font_ubuntu_monospace_bold_14, StyleColor(0.0, 0.33, 0.8, 1.0)),
        TextString(", ", font_ubuntu_monospace_regular_14, color_default),
        TextString("world", font_ubuntu_monospace_regular_14, StyleColor(0.8, 0.33, 0.0, 1.0)),
        TextString("!", font_ubuntu_monospace_regular_14, color_default),
        nl,
        TextString("Line two.", font_ubuntu_monospace_regular_14, color_default),
    )
end
