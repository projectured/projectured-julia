# The layout draws each place. A place prints its string view in three stages, each
# a viewing step or the text stage: JSON to syntax gives the view of the leaf of the
# string, syntax to text the view of its text, and the text stage draws that view.
function make_json_string_view_projection_example(; measure = FontFileMeasure())
    stages = ChainingProjection(
        RecursiveProjection(ViewingProjection(JsonToSyntax())),
        RecursiveProjection(ViewingProjection(SyntaxToText())),
        RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
            TextView  => TextViewToGraphicsCanvas(),
            TextBlock => TextBlockToGraphicsCanvas(; measure),
        ])))
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout => VerticalLayoutToGraphicsCanvas(),
        JsonStringView => stages,
    ]))
end
