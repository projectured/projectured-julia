function make_line_numbering_document_example()
    newline = TextNewline(font=font_ubuntu_monospace_regular_20)
    TextBlock(
        TextString("Lorem ipsum dolor sit amet,", font_ubuntu_monospace_regular_20, color_default),
        newline,
        TextString("consectetur adipiscing elit, sed do eiusmod", font_ubuntu_monospace_regular_20, color_default),
        newline,
        TextString("tempor incididunt ut labore et dolore magna", font_ubuntu_monospace_regular_20, color_default),
        newline,
        TextString("aliqua. Ut enim ad minim veniam, quis", font_ubuntu_monospace_regular_20, color_default),
        newline,
        TextString("nostrud exercitation ullamco laboris nisi", font_ubuntu_monospace_regular_20, color_default),
        newline,
        TextString("ut aliquip ex ea commodo consequat.", font_ubuntu_monospace_regular_20, color_default),
    )
end
