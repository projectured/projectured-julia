# A small JSON text whose object and whose list fold, in a scroll pane. The fold of
# the list gives a placeholder that shows its brackets, `…],`, so the closed list
# reads as one line; the numbers of the lines after a closed fold stay.
function make_text_folding_document_example()
    font = StyleFont("Ubuntu Mono", 20)
    span(text) = TextString(text, font, color_default)
    placeholder(text) = TextBlock(TextString(text, font, color_default))
    list = TextFold(; line_count = 4, placeholder = placeholder("…],"))
    object = TextFold(; line_count = 8, placeholder = placeholder("…}"))
    lines = TextDocument[
        TextLine(span("{"); fold = object),
        TextLine(span("\"name\": \"gutter\","); indentation = 2),
        TextLine(span("\"lanes\": ["); indentation = 2, fold = list),
        TextLine(span("\"marker\","); indentation = 4),
        TextLine(span("\"number\","); indentation = 4),
        TextLine(span("\"fold\""); indentation = 4),
        TextLine(span("],"); indentation = 2),
        TextLine(span("\"scrolls\": true"); indentation = 2),
        TextLine(span("}"))]
    WidgetScrollPane(TextBlock(lines); size = Point2D(360, 160))
end
