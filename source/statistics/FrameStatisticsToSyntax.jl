# Fragment of `FrameStatisticsModule`.
#
# Projects a [`FrameStatistics`](FrameStatisticsDocument.jl) onto a
# `SyntaxNode` for display: a head line with the frame count, a header line,
# and one line per measurement. The DejaVu monospace font keeps the columns
# aligned, for the same reason the message log panel uses it. The colors suit
# the light background of a tab.
#
# Read-only. There is nothing to author here, so this is a plain leaf
# printer with no reader and no reference mappers.
@projection struct FrameStatisticsToSyntax
    header::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_bold_16, color_solarized_cyan)
    row::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    empty::ImmutableCell{StyleText} = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
end

# Column widths in characters: the name, then six number columns.
const _NAME_WIDTH = 16
const _NUMBER_WIDTH = 12

# A count prints as an integer; everything else keeps four significant
# digits, which tells 0.0021 s from 0.021 s and stays in its column.
_format_measurement_value(value::Float64) =
    isinteger(value) && abs(value) < 1e15 ? string(Int(value)) :
    string(round(value; sigdigits = 4))

"""
    print_document(p::FrameStatisticsToSyntax, recursion, statistics::FrameStatistics, ctx)

One `SyntaxNode` per line, joined by newlines. The lines are derived, not
copied: the outer node reads `statistics.frame_count` and the row cells
inside a `ComputedCellVector`, so a flush rebuilds exactly the lines whose
numbers changed.
"""
function print_document(p::FrameStatisticsToSyntax, recursion,
                        statistics::FrameStatistics, ctx::PrinterContext)
    children = ComputedCellVector(function ()
        rows = statistics.rows
        lines = SyntaxDocument[]
        push!(lines, SyntaxLeaf(TextString("$(statistics.frame_count) frames", p.header)))
        if isempty(rows)
            push!(lines, SyntaxLeaf(TextString("no frame yet", p.empty)))
            return lines
        end
        push!(lines, _header_line(p))
        for index in 1:length(rows)
            push!(lines, _measurement_line(p, rows[index]))
        end
        lines
    end)
    SimpleIoMap(p, statistics, SyntaxNode(children; sep=TextString("\n")))
end

function _header_line(p::FrameStatisticsToSyntax)
    columns = rpad("measurement", _NAME_WIDTH) *
              join(lpad(label, _NUMBER_WIDTH)
                   for label in ("count", "minimum", "maximum", "mean", "deviation", "total"))
    SyntaxLeaf(TextString(columns, p.header))
end

# One line: "frame_time   1234   0.0001   0.03   0.0021   0.0009   2.59".
function _measurement_line(p::FrameStatisticsToSyntax, row::FrameMeasurement)
    columns = rpad(row.name, _NAME_WIDTH) *
              lpad(string(row.count), _NUMBER_WIDTH) *
              join(lpad(_format_measurement_value(value), _NUMBER_WIDTH)
                   for value in (row.minimum, row.maximum, row.mean,
                                 row.standard_deviation, row.total))
    SyntaxLeaf(TextString(columns, p.row))
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that lets a tab draw a statistics table. The factory form, so every
# renderer builds its own projection instance.

function __init__()
    register_natural_syntax!(:statistics, () -> Pair{Type,Any}[FrameStatistics => FrameStatisticsToSyntax()])
    register_pred_type!(FrameStatistics)
end
