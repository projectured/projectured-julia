# The lines are numbered, folded and drawn with their gutters in a chain. A block
# of lines goes to that chain, and a block of spans, the text of a mark, to the
# text, so the recursion prints the numbers and the triangles.
function make_text_folding_projection_example(; measure = FontFileMeasure())
    lines = ChainingProjection(TextLineNumbering(), TextFolding(), TextBlockToScrollLayout(; measure))
    RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type, Any}[
            TextBlock => PredicateDispatchingProjection(
                (block -> length(block.elements) > 0 && block.elements[1] isa TextLine) => lines,
                (_ -> true) => TextToGraphics(; measure)),
            TextGutter => TextGutterToGraphics(),
            GraphicsCanvas => GraphicsToGraphics()],
        WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure).dispatch)))
end
