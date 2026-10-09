# Draw a find bar view: the view arranges the bar and the text, the widget rows
# draw the bar and its form of fields, and the text stage highlights or filters
# the text before `TextToGraphics` draws it. Pairs with `make_find_bar_document`.
function make_find_bar_projection(; measure=FontFileMeasure(), font=StyleFont("Ubuntu Mono", 20))
    w2g = WidgetToGraphics(font; measure=measure)
    stage = RecursiveProjection(TypeDispatchingProjection(
        HighlightedText => HighlightedTextToText(),
        FilteredText    => FilteredTextToText(),
        TextBlock       => IdentityProjection()))
    text = ChainingProjection(stage, TextToGraphics(measure=measure))
    RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type,Any}[
            FindBarView     => ChainingProjection(FindBarViewToWidget(), VerticalLayoutToGraphicsCanvas()),
            HighlightedText => text,
            FilteredText    => text,
        ],
        LayoutToGraphics().dispatch,
        make_object_field_widget_dispatch(w2g.dispatch),
    )))
end
