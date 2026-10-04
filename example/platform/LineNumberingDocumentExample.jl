function make_line_numbering_document_example()
    newline = TextNewline(font=StyleFont("Ubuntu Mono", 20))
    TextBlock(
        TextString("Lorem ipsum dolor sit amet,", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("consectetur adipiscing elit, sed do eiusmod", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("tempor incididunt ut labore et dolore magna", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("aliqua. Ut enim ad minim veniam, quis", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("nostrud exercitation ullamco laboris nisi", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("ut aliquip ex ea commodo consequat.", StyleFont("Ubuntu Mono", 20), color_default),
    )
end
