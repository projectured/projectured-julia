# The text prints to a `ScrollLayout` whose left edge is the gutter, and the
# scroll pane keeps that edge in view. The recursion prints each mark: a number
# through the text, a dot as graphics, the check box as a widget.
function make_text_gutter_projection_example(; measure = FontFileMeasure())
    RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type, Any}[
            TextBlock => TextBlockToScrollLayout(; measure),
            TextGutter => TextGutterToGraphics(),
            PrimitiveNumber => ChainingProjection(PrimitiveNumberToText(), TextToGraphics(; measure)),
            GraphicsCanvas => GraphicsToGraphics()],
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure).dispatch)))
end
