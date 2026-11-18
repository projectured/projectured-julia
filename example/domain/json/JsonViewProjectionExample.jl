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

# A place prints its array view in four stages: JSON to syntax gives the view of the
# node of the array over the views of its elements, syntax to text the view of its
# text with the folds of the views, `TextFolding` hides the lines of those folds,
# and the text stage draws the view.
function make_json_array_view_projection_example(; measure = FontFileMeasure())
    stages = ChainingProjection(
        RecursiveProjection(ViewingProjection(JsonToSyntax())),
        RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
        TextFolding(),
        RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
            TextView  => TextViewToGraphicsCanvas(),
            TextBlock => TextBlockToGraphicsCanvas(; measure),
        ])))
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout => VerticalLayoutToGraphicsCanvas(),
        JsonArrayView  => stages,
    ]))
end

# A place prints its object view in the four stages of an array view. JSON to syntax
# gives the view of the node of the object over the views of the nodes of its
# entries, and the view of the node of an entry holds the view of the node of its
# value.
function make_json_object_view_projection_example(; measure = FontFileMeasure())
    stages = ChainingProjection(
        RecursiveProjection(ViewingProjection(JsonToSyntax())),
        RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
        TextFolding(),
        RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
            TextView  => TextViewToGraphicsCanvas(),
            TextBlock => TextBlockToGraphicsCanvas(; measure),
        ])))
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout => VerticalLayoutToGraphicsCanvas(),
        JsonObjectView => stages,
    ]))
end

# The general renderer draws each place: the row of a file view gives the band and
# the scroll pane, the row of the view of an undo buffer records each edit, and the
# rows of a view print the JSON views in the stages of a view.
make_json_file_view_projection_example(; measure = FontFileMeasure()) = NaturalToGraphics(; measure)
