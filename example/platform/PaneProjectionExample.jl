# The pane-tree projection: two stages, exactly as the plan describes them.
#
#   1. `PaneToWidget` turns the layout tree into split panes and tabbed panes. A
#      tab's *content* passes through this stage untouched.
#   2. The renderer draws that widget tree, and every content document in it.
#
# So the second stage is what decides how a tab's content looks: this one knows
# widgets, layouts, primitive documents, and the placeholder a fresh tab holds.
function make_pane_projection_example(; measure=FontFileMeasure(), new_tab=default_new_pane_tab)
    font = StyleFont("Ubuntu", 20)
    widget = WidgetToGraphics(font; measure=measure)
    primitive = ChainingProjection(RecursiveProjection(PrimitiveToText()),
                                   TextToGraphics(measure=measure))
    # A fresh tab holds a `DocumentNothing`. Its own rendering — the muted "empty
    # document" label — is `InsertionNothingToSyntaxLeaf`, which lives one tier
    # up, so this tier draws the placeholder through the object renderer instead.
    # A projection that knows the domain tier gives it the proper label (see the
    # `pane_json` example).
    object = ChainingProjection(
        RecursiveProjection(ObjectToSyntax(type_name_font=StyleFont("Ubuntu Mono", 20; italic = true),
                                           type_name_color=color_solarized_gray)),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure))
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type,Any}[PrimitiveDocument => primitive,
                       DocumentNothing   => object],
        LayoutToGraphics().dispatch,
        widget.dispatch,
    )))
    # Tab starts over at the ends, exactly as in the widget gallery's projection.
    ChainingProjection(
        RecursiveProjection(PaneToWidget(; new_tab=new_tab)),
        FocusCyclingProjection(inner=renderer),
    )
end
