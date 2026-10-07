# A few lines of code, each with a gutter: the number of the line, a breakpoint
# dot on one line, and a check box that a person switches on another, in a scroll
# pane smaller than the text, so the gutter stays at the left edge while the lines
# scroll.

# A breakpoint: a red dot, as a canvas of 10 by 10.
_make_text_gutter_breakpoint() =
    GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(10)), Cell(Int32(10)),
                   CellVector(Cell[Cell(GraphicsRect(0, 0, 10, 10; color = color_solarized_red, radius = 5))]),
                   layout_none, true, Cell(nothing))

function make_text_gutter_document_example()
    font = StyleFont("Ubuntu Mono", 20)
    code = [(0, "function greet(name)"),
            (4, "message = \"Hello, \" * name * \", from a text with a gutter\""),
            (4, "println(message)"),
            (4, "return message"),
            (0, "end"),
            (0, ""),
            (0, "greet(\"gutter\")")]
    lines = TextDocument[]
    for (n, (indentation, text)) in enumerate(code)
        marker = n == 2 ? _make_text_gutter_breakpoint() : n == 7 ? WidgetCheckbox(false) : nothing
        gutter = TextGutter(; marker, number = PrimitiveNumber(n))
        push!(lines, TextLine(TextString(text, font, color_default); indentation, gutter))
    end
    WidgetScrollPane(TextBlock(lines); size = Point2D(360, 120))
end
