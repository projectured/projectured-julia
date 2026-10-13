function make_julia_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(JuliaToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The code of a Julia program as a file tab shows it: the syntax printed with text
# folds, then numbered, folded and drawn with its gutter. The outer recursion
# prints the scroll pane and the marks of the gutter.
function make_julia_code_projection_example(; measure = FontFileMeasure())
    code = ChainingProjection(RecursiveProjection(JuliaToSyntax()),
                              RecursiveProjection(SyntaxToText(text_folds = true)),
                              TextLineNumbering(), TextFolding(), TextBlockToScrollLayout(; measure))
    RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type, Any}[
            JuliaDocument => code,
            TextBlock => TextToGraphics(; measure),
            TextGutter => TextGutterToGraphics(),
            GraphicsCanvas => GraphicsToGraphics()],
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure).dispatch)))
end
