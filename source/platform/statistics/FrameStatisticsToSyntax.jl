# Fragment of `FrameStatisticsModule` — the projection of a
# [`FrameStatistics`](FrameStatisticsDocument.jl) onto a `SyntaxNode`: a head
# line with the frame counts, a header line, and one line for each measurement.
# The DejaVu monospace font keeps the columns aligned, for the same reason the
# message log panel uses it. The default colors suit the light background of a
# tab.
#
# Read-only. There is nothing to author here, so this is a plain leaf printer
# with no reader and no reference mappers.
#
# The projection holds its styles and no theme; `make_frame_statistics_projection`
# fills them from a theme.
@projection UntrackedCell struct FrameStatisticsToSyntax
    header_text::StyleText = get_frame_statistics_style(nothing, :header_text)
    row_text::StyleText = get_frame_statistics_style(nothing, :row_text)
    empty_text::StyleText = get_frame_statistics_style(nothing, :empty_text)
end

"""
    make_frame_statistics_projection(; theme = nothing) -> FrameStatisticsToSyntax

The projection of the statistics table, with the styles of `theme`: a
`FrameStatisticsTheme`, scaled or not, or the default styles for `nothing`.
"""
function make_frame_statistics_projection(; theme = nothing)
    get_style(name) = get_frame_statistics_style(theme, name)
    FrameStatisticsToSyntax(; header_text = get_style(:header_text), row_text = get_style(:row_text),
                            empty_text = get_style(:empty_text))
end

# Column widths in characters: the name, the unit, then six number columns.
const _NAME_WIDTH = 16
const _UNIT_WIDTH = 6
const _NUMBER_WIDTH = 12

"""
    print_document(p::FrameStatisticsToSyntax, recursion, statistics::FrameStatistics, ctx)

One `SyntaxNode` for each line, joined by newlines. The lines are derived, not
copied: the outer node reads `statistics.frame_count` and the row cells inside
a computed `CellVector`, so a flush rebuilds exactly the lines whose numbers
changed.
"""
function print_document(p::FrameStatisticsToSyntax, recursion,
                        statistics::FrameStatistics, ctx::PrinterContext)
    children = CellVector(Computation(function ()
        rows = statistics.rows
        lines = SyntaxDocument[]
        push!(lines, SyntaxLeaf(TextString(_format_head_line(statistics), p.header_text)))
        if isempty(rows)
            push!(lines, SyntaxLeaf(TextString("no frame yet", p.empty_text)))
            return lines
        end
        push!(lines, _header_line(p))
        for index in 1:length(rows)
            push!(lines, _measurement_line(p, rows[index]))
        end
        lines
    end))
    SimpleIoMap(p, statistics, SyntaxNode(children; sep=TextString("\n")))
end

# "1234 frames, the rows cover the last 1000": the frames since the start, and
# how many of them the rows summarize when that is fewer.
function _format_head_line(statistics::FrameStatistics)
    frame_count = statistics.frame_count
    rows = statistics.rows
    covered = isempty(rows) ? 0 : maximum(rows[index].count for index in 1:length(rows))
    covered < frame_count ? "$(frame_count) frames, the rows cover the last $(covered)" :
                            "$(frame_count) frames"
end

function _header_line(p::FrameStatisticsToSyntax)
    columns = rpad("measurement", _NAME_WIDTH) * rpad("unit", _UNIT_WIDTH) *
              join(lpad(label, _NUMBER_WIDTH)
                   for label in ("frames", "minimum", "maximum", "mean", "deviation",
                                 "total"))
    SyntaxLeaf(TextString(columns, p.header_text))
end

# One line: "frame_time      ms          1000        2.13       45.02 …".
function _measurement_line(p::FrameStatisticsToSyntax, row::FrameStatisticsRow)
    unit = row.unit === :second ? "ms" : ""
    columns = rpad(row.name, _NAME_WIDTH) * rpad(unit, _UNIT_WIDTH) *
              lpad(string(row.count), _NUMBER_WIDTH) *
              join(lpad(text, _NUMBER_WIDTH) for text in _format_measurement_values(row))
    SyntaxLeaf(TextString(columns, p.row_text))
end

# The minimum, the maximum, the mean, the deviation and the total of a row, as
# text. A time shows in milliseconds with two decimals, and its total with
# none. A count shows as a whole number, and its mean and deviation with one
# decimal. A row that no recent frame measured shows a dash.
function _format_measurement_values(row::FrameStatisticsRow)
    row.count == 0 && return fill("-", 5)
    if row.unit === :second
        return [@sprintf("%.2f", row.minimum * 1000),
                @sprintf("%.2f", row.maximum * 1000),
                @sprintf("%.2f", row.mean * 1000),
                @sprintf("%.2f", row.standard_deviation * 1000),
                @sprintf("%.0f", row.total * 1000)]
    end
    [@sprintf("%.0f", row.minimum), @sprintf("%.0f", row.maximum),
     @sprintf("%.1f", row.mean), @sprintf("%.1f", row.standard_deviation),
     @sprintf("%.0f", row.total)]
end
