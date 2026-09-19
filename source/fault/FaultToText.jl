# Fragment of `FaultViewModule`.
#
# A `FaultReport` as one text block, for a barrier whose step answers the text
# domain. Same job as `FaultToSyntax` one domain further on.

"""
    FaultToText(; style)

One `FaultReport` as a red `TextBlock` of one line.

Give it to a text-domain barrier as its substitute:

    FaultCatchingProjection(inner = SyntaxToText(), substitute = FaultToText())
"""
@projection struct FaultToText
    style::ImmutableCell{StyleText} =
        StyleText(font_dejavu_monospace_bold_16, color_solarized_red)
end

function print_document(p::FaultToText, recursion, report::FaultReport,
                        ctx::PrinterContext)
    SimpleIoMap(p, report,
                TextBlock(() -> Any[TextString(format_fault_label(report), p.style)]))
end
