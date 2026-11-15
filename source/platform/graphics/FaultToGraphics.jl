# Fragment of `GraphicsModule` — the mark that a fault barrier of the graphics domain draws.
#
# A `FaultReport` as drawn words. This is the last substitute of a chain, and it
# is the one that must not be left out: the step it belongs to answers the
# backend, so a bare `FaultReport` there reaches no further barrier at all.

"""
    FaultToGraphics(; font, color)

One `FaultReport` as a `GraphicsCanvas` holding one red line of text.

Give it to the last barrier of a chain, the one whose step answers the backend:

    FaultCatchingProjection(inner = TextToGraphics(measure = measure),
                            substitute = FaultToGraphics())
"""
@projection struct FaultToGraphics
    font::ImmutableCell{StyleFont} = get_theme_defaults(GraphicsTheme).fault_text.font
    color::ImmutableCell{StyleColor} = get_theme_defaults(GraphicsTheme).fault_text.color
end

# The mark stands inside the space that its slot gives at the left and at the top.
function print_document(p::FaultToGraphics, recursion, report::FaultReport,
                        ctx::PrinterContext)
    left, top, _, _ = ctx.space
    elements = CellVector(@computation Any[GraphicsText(format_fault_label(report), left, top;
                                                        font = p.font, color = p.color)])
    SimpleIoMap(p, report, GraphicsCanvas(elements, layout_none))
end
