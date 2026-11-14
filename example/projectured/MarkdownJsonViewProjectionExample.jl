# The stage that prints a Markdown document with a JSON part to the syntax. Each
# domain prints its own nodes with its own table, and neither table names the
# other; a collection of children copies, as it does in each of the two tables.
make_markdown_json_to_syntax() = TypeDispatchingProjection(Pair{Type,Any}[
    MarkdownDocument => MarkdownToSyntax(),
    JsonDocument     => JsonToSyntax(),
    Vector{Cell}     => CopyingProjection(),
])

# The layout draws each place. A place prints its view in four stages: the two
# domains to the syntax, which gives the view of the node of the document over the
# views of the nodes of its parts, syntax to text, `TextFolding`, and the text stage,
# which draws the view. The view of the document and the view of its JSON part
# print through the same stages.
function make_markdown_json_view_projection_example(; measure = FontFileMeasure())
    stages = ChainingProjection(
        RecursiveProjection(ViewingProjection(make_markdown_json_to_syntax())),
        RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
        TextFolding(),
        RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
            TextView  => TextViewToGraphicsCanvas(),
            TextBlock => TextBlockToGraphicsCanvas(; measure),
        ])))
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
        MarkdownRootView => stages,
        JsonArrayView    => stages,
    ]))
end
