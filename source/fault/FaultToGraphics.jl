# Fragment of `FaultViewModule`.
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
    font::ImmutableCell{StyleFont} = font_dejavu_monospace_bold_16
    color::ImmutableCell{StyleColor} = color_solarized_red
end

function print_document(p::FaultToGraphics, recursion, report::FaultReport,
                        ctx::PrinterContext)
    elements = ComputedCellVector(() ->
        Any[GraphicsText(format_fault_label(report), 0, 0, p.font, p.color)])
    SimpleIoMap(p, report, GraphicsCanvas(elements, layout_none))
end
