# Fragment of `WidgetModule` — the mark that a fault barrier of the widget domain draws.
#
# A `FaultReport` as a small alert widget, for a barrier whose step answers the
# widget domain. Same job as `FaultToSyntax` one domain across.

"""
    FaultToWidget(; width)

One `FaultReport` as a `WidgetAlert` in the destructive variant.

Give it to a widget-domain barrier as its substitute:

    FaultCatchingProjection(inner = WorkbenchToWidget(), substitute = FaultToWidget())
"""
@projection struct FaultToWidget
    width::ImmutableCell{Int} = 320
end

function print_document(p::FaultToWidget, recursion, report::FaultReport,
                        ctx::PrinterContext)
    # The alert says the whole fault when the pointer rests on it. A mark is
    # inert, so the selection never names the report itself; the widget it is
    # drawn as is what a person points at, and a widget answers with its own
    # `tooltip`.
    alert = WidgetAlert(Cell(@computation String(report.origin));
                        description = Cell(@computation report.message), icon = :warning, variant = :destructive, width = p.width,
                        tooltip = format_fault_report_message(report))
    SimpleIoMap(p, report, alert)
end
