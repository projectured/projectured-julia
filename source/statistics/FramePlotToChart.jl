# Fragment of `FrameStatisticsModule` — the projection of a `FramePlot` onto a
# `Chart`: one line for each time measurement, in milliseconds, over the frame
# numbers.
#
# Read-only. There is nothing to author in a plot of measurements, so this is a
# printer with no reader and no reference mappers of its own.

"""
    FramePlotToChart()

Projects a [`FramePlot`](@ref) onto a `Chart` of the frame times: frame number
on x, time in milliseconds on y, one line for each time measurement.

The chart is built once. Its list of series derives from `plot.names`, and the
columns of each series derive from `plot.frames` and `plot.columns`, so a flush
repaints the lines and prints nothing again.

# Example

    projection = ChainingProjection(FramePlotToChart(), ChartToChartPlot(),
                                    ChartPlotToGraphicsCanvas(measure = measure))

See also [`FrameStatisticsToSyntax`](@ref), which shows the same measurements
as a table.
"""
struct FramePlotToChart <: Projection end

function print_document(p::FramePlotToChart, recursion, plot::FramePlot,
                        ctx::PrinterContext)
    series = ComputedCellVector(function ()
        [_make_frame_time_series(plot, index, name)
         for (index, name) in enumerate(plot.names)]
    end)
    # The generated constructor, because the keyword form copies the series
    # into a new vector and the list would no longer derive from the plot.
    chart = Chart("Frame times", series,
                  ChartAxis(; title = "frame"), ChartAxis(; title = "time (ms)"),
                  ChartLegend(; position = :inside, anchor = :northwest),
                  ChartStyle(), :aligned, 0.0, nothing, nothing)
    SimpleIoMap(p, plot, chart)
end

# One line: the column `index` of the plot in milliseconds, over the frame
# numbers. Both columns derive from the plot.
_make_frame_time_series(plot::FramePlot, index::Integer, name::AbstractString) =
    ChartLineSeries(name, Computed(() -> plot.frames),
                    Computed(() -> _get_frame_time_milliseconds(plot, index)),
                    true, :linear, :solid, 1, :none, 4, nothing, true, nothing)

# A column that a flush has not written yet reads as no value for each frame,
# so the two columns of a line always have one length.
function _get_frame_time_milliseconds(plot::FramePlot, index::Integer)
    columns = plot.columns
    index <= length(columns) || return fill(NaN, length(plot.frames))
    columns[index] .* 1000
end
