# Syntax printed with text folds, then numbered, folded and drawn with its gutter.
# The syntax is a stage of its own, with its own recursion, so a child prints to
# text; the outer recursion prints the scroll pane and the marks of the gutter.
function make_syntax_folding_projection_example(; measure = FontFileMeasure())
    code = ChainingProjection(RecursiveProjection(SyntaxToText(text_folds = true)),
                              TextLineNumbering(), TextFolding(), TextBlockToScrollLayout(; measure))
    RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type, Any}[
            SyntaxDocument => code,
            TextBlock => TextToGraphics(; measure),
            TextGutter => TextGutterToGraphics(),
            GraphicsCanvas => GraphicsToGraphics()],
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure).dispatch)))
end
