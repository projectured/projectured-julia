# The layout draws each place, a place draws its view, and a view draws its caret
# over the drawing of its content, which the row of `TextBlock` prints.
make_text_view_places_projection_example(; measure = FontFileMeasure()) =
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout => VerticalLayoutToGraphicsCanvas(),
        TextView       => TextViewToGraphicsCanvas(),
        TextBlock      => TextBlockToGraphicsCanvas(; measure),
    ]))
