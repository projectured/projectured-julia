function make_text_filtering_document_example()
    newline = TextNewline(font=font_ubuntu_monospace_regular_24)
    document = TextText(
        TextString("Lorem ipsum dolor sit amet,", font_ubuntu_monospace_regular_24, color_default),
        newline,
        TextString("consectetur adipiscing elit, sed do", font_ubuntu_monospace_regular_24, color_default),
        newline,
        TextString("tempor incididunt ut labore et dolore", font_ubuntu_monospace_regular_24, color_default),
        newline,
        TextString("magna aliqua. Ut enim ad minim veniam,", font_ubuntu_monospace_regular_24, color_default),
        newline,
        TextString("quis nostrud exercitation ullamco", font_ubuntu_monospace_regular_24, color_default),
        newline,
        TextString("laboris nisi ut aliquip ex ea commodo.", font_ubuntu_monospace_regular_24, color_default),
    )
    return document
end
