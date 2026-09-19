# Fragment of `FaultViewModule`.
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
    alert = WidgetAlert(Point2D(0, 0),
                        ComputedCell(() -> "⚠ " * report.origin),
                        ComputedCell(() -> report.message);
                        variant = :destructive, width = p.width)
    SimpleIoMap(p, report, alert)
end
