# The layout draws each place. A place prints its node view in three stages: a
# viewing step prints the node with `SyntaxToText` and gives the `TextView` of its
# text, whose closed folds are the folds of the views; `TextFolding` hides the
# lines of those folds in this view; the text stage draws the view.
function make_syntax_node_view_projection_example(; measure = FontFileMeasure())
    stages = ChainingProjection(
        RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
        TextFolding(),
        RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
            TextView  => TextViewToGraphicsCanvas(),
            TextBlock => TextBlockToGraphicsCanvas(; measure),
        ])))
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout => VerticalLayoutToGraphicsCanvas(),
        SyntaxNodeView => stages,
    ]))
end
