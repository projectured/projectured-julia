# The pane-tree projection: two stages, exactly as the plan describes them.
#
#   1. `PaneToWidget` turns the layout tree into split panes and tabbed panes. A
#      tab's *content* passes through this stage untouched.
#   2. The renderer draws that widget tree, and every content document in it.
#
# So the second stage is what decides how a tab's content looks: this one knows
# widgets, layouts, and primitive documents (the empty text a fresh tab holds).
function make_pane_projection_example(; measure=truetype_measure_text, new_tab=default_new_pane_tab)
    font = font_ubuntu_regular_20
    widget = WidgetToGraphics(font; measure=measure)
    primitive = ChainingProjection(RecursiveProjection(PrimitiveToText()),
                                   TextToGraphics(measure=measure))
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type,Any}[PrimitiveDocument => primitive],
        LayoutToGraphics().dispatch,
        widget.dispatch,
    )))
    # The hover tracker gives the strip's buttons their crossings, exactly as the
    # widget gallery's projection does.
    ChainingProjection(
        RecursiveProjection(PaneToWidget(; new_tab=new_tab)),
        WidgetHoverTrackingProjection(inner=renderer),
    )
end
