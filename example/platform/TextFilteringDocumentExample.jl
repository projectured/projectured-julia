# A text that keeps only its lines with "dolor". The pattern is a field of the
# document, so a form of it edits the filter.
function make_text_filtering_document_example()
    newline = TextNewline(font=StyleFont("Ubuntu Mono", 20))
    block = TextBlock(
        TextString("Lorem ipsum dolor sit amet,", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("consectetur adipiscing elit, sed do", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("tempor incididunt ut labore et dolore", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("magna aliqua. Ut enim ad minim veniam,", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("quis nostrud exercitation ullamco", StyleFont("Ubuntu Mono", 20), color_default),
        newline,
        TextString("laboris nisi ut aliquip ex ea commodo.", StyleFont("Ubuntu Mono", 20), color_default),
    )
    FilteredText(text = block, pattern = "dolor")
end
