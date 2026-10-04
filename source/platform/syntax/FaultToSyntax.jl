# Fragment of `SyntaxModule` — the mark that a fault barrier of the syntax domain draws.
#
# A `FaultReport` as one syntax leaf: a warning sign, what failed, and what it
# said. This is the substitute a syntax-domain step of a pipeline hands to its
# `FaultCatchingProjection`, and it is what keeps the fault from spreading — the
# step that follows receives an ordinary `SyntaxLeaf` and prints it without ever
# learning that a fault exists.
#
# Read-only. A mark is inert by design: there is nothing to author in it, so this
# is a plain leaf printer with no reader and no reference mappers.

"""
    FaultToSyntax(; style)

One `FaultReport` as a red `SyntaxLeaf`.

Give it to a syntax-domain barrier as its substitute:

    FaultCatchingProjection(inner = JsonToSyntax(), substitute = FaultToSyntax())

See also `FaultCatchingProjection`, which says why a substitute is not optional.
"""
@projection struct FaultToSyntax
    style::ImmutableCell{StyleText} = get_theme_defaults(SyntaxTheme).fault_text
end

function print_document(p::FaultToSyntax, recursion, report::FaultReport,
                        ctx::PrinterContext)
    text = Cell(@computation TextString(format_fault_label(report), p.style))
    SimpleIoMap(p, report, SyntaxLeaf(text))
end
