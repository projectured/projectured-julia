# Fragment of `ProjectionAlgebraModule` — the documents of the algebra: the report
# that a fault barrier puts in the output where a part failed.

"""
    FaultReport(; site, origin, message, retry = nothing)
    FaultReport(record; retry = nothing)

One fault, as a document.

It is what `FaultCatchingProjection` puts in the output where a part failed. A
report keeps the slot the part had, so the parent's layout still places it and
every other part still draws. Each domain draws it with a mark of its own:
`FaultToSyntax`, `FaultToText`, `FaultToWidget` and `FaultToGraphics`.

A report can not be edited. Its projection maps no reference, so the selection
does not walk into one. `retry` is the operation that tries the part again, which
the barrier that made the report gives it, and `nothing` for a report that no
barrier made.

The kernel's `FaultRecord` is the same fault as a value. This is the same fault
as a document: the kernel records, and a projection shows.

# Example

    FaultReport(record)

See also `FaultCatchingProjection`, which is what makes one, and `FaultLog`.
"""
@document struct FaultReport
    site::String = "print"
    origin::String = "unknown"
    message::String = ""
    retry::Any = nothing
end

# The keyword form, not the positional one: every field of this document
# declares a default, and `@document` emits no positional constructor for a
# struct whose required-field count is zero.
FaultReport(record::FaultRecord; retry = nothing) =
    FaultReport(site = String(record.site), origin = String(record.origin),
                message = record.message, retry = retry)

"""
    format_fault_label(report) -> String

The one line a mark shows: what failed, and what it said.
"""
format_fault_label(report::FaultReport) = "⚠ $(report.origin): $(report.message)"

"""
    format_fault_report_message(report) -> String

The whole fault, over three lines: what failed, where it was caught, and what it
said. A mark shows one line, which a long message does not fit in; this is what a
window shows.
"""
format_fault_report_message(report::FaultReport) =
    "⚠ $(report.origin)\ncaught in the $(report.site)\n\n$(report.message)"
