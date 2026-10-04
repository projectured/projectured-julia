function make_text_to_string_document_example()
    nl = TextNewline(font=StyleFont("Ubuntu Mono", 14))
    TextBlock(
        TextString("Hello", StyleFont("Ubuntu Mono", 14; weight = 700), StyleColor(0.0, 0.33, 0.8, 1.0)),
        TextString(", ", StyleFont("Ubuntu Mono", 14), color_default),
        TextString("world", StyleFont("Ubuntu Mono", 14), StyleColor(0.8, 0.33, 0.0, 1.0)),
        TextString("!", StyleFont("Ubuntu Mono", 14), color_default),
        nl,
        TextString("Line two.", StyleFont("Ubuntu Mono", 14), color_default),
    )
end
