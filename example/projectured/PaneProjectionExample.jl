# The pane-tree projection of the domain tier: the same two stages the visual
# tier's `make_pane_projection_example` has, but with a renderer that knows every
# source domain.
#
#   1. `PaneToWidget` turns the layout tree into split panes and tabbed panes. A
#      tab's *content* passes through this stage untouched.
#   2. `NaturalToGraphics` draws that widget tree, and every content document in
#      it — json, xml, prose, a table, whatever a tab holds.
function make_pane_json_projection_example(; measure=FontFileMeasure(), new_tab=default_new_pane_tab)
    font = StyleFont("Ubuntu", 20)
    # Tab titles and the plain-text tabs are `PrimitiveString`s. The natural
    # table prints a primitive through the syntax fabric, which quotes a string;
    # a title and a note are prose, so route them straight to text instead.
    primitive = ChainingProjection(RecursiveProjection(PrimitiveToText()),
                                   TextToGraphics(measure=measure))
    renderer = NaturalToGraphics(measure=measure, font=font, extra=Pair{Type,Any}[
        PrimitiveDocument => primitive,
    ])
    # Tab starts over at the ends, exactly as in the visual tier's pane projection.
    ChainingProjection(
        RecursiveProjection(PaneToWidget(; new_tab=new_tab)),
        FocusCyclingProjection(inner=renderer),
    )
end

# The projection of `make_widget_tabs_document_example`. The document is already a
# widget, so there is no first stage: the natural renderer draws the tabbed pane
# and, through the same recursion, whichever domain document each tab holds.
function make_widget_tabs_projection_example(; measure=FontFileMeasure())
    renderer = NaturalToGraphics(measure=measure, font=StyleFont("Ubuntu", 20))
    FocusCyclingProjection(inner=renderer)
end

# The projection of `make_widget_split_document_example`. Like the tabbed-pane
# example, the document is already a widget, so the natural renderer draws the
# split and each side's own domain through the same recursion.
function make_widget_split_projection_example(; measure=FontFileMeasure())
    renderer = NaturalToGraphics(measure=measure, font=StyleFont("Ubuntu", 20))
    FocusCyclingProjection(inner=renderer)
end

# The projection of `make_widget_split_tabs_document_example`. Same shape as the
# other two: the document is a widget already, so the natural renderer draws the
# split, the two tab groups, and each page's own domain.
function make_widget_split_tabs_projection_example(; measure=FontFileMeasure())
    renderer = NaturalToGraphics(measure=measure, font=StyleFont("Ubuntu", 20))
    FocusCyclingProjection(inner=renderer)
end
