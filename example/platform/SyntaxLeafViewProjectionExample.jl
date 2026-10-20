# The layout draws each place. A place prints its leaf view in two stages: a
# viewing step prints the leaf with `SyntaxToText` and gives the `TextView` of its
# text, and the text stage draws that view over the lines of the text.
function make_syntax_leaf_view_projection_example(; measure = FontFileMeasure())
    stages = ChainingProjection(
        RecursiveProjection(ViewingProjection(SyntaxToText())),
        RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
            TextView  => TextViewToGraphicsCanvas(),
            TextBlock => TextBlockToGraphicsCanvas(; measure),
        ])))
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout => VerticalLayoutToGraphicsCanvas(),
        SyntaxLeafView => stages,
    ]))
end
