function make_line_numbering_document_example()
    TextBlock(
        TextLine(TextString("Lorem ipsum dolor sit amet,", StyleFont("Ubuntu Mono", 20), color_default)),
        TextLine(TextString("consectetur adipiscing elit, sed do eiusmod", StyleFont("Ubuntu Mono", 20), color_default)),
        TextLine(TextString("tempor incididunt ut labore et dolore magna", StyleFont("Ubuntu Mono", 20), color_default)),
        TextLine(TextString("aliqua. Ut enim ad minim veniam, quis", StyleFont("Ubuntu Mono", 20), color_default)),
        TextLine(TextString("nostrud exercitation ullamco laboris nisi", StyleFont("Ubuntu Mono", 20), color_default)),
        TextLine(TextString("ut aliquip ex ea commodo consequat.", StyleFont("Ubuntu Mono", 20), color_default)),
    )
end
