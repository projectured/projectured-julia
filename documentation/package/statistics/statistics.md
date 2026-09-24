# Frame statistics

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../kernel/editor.md), [log.md](../log/log.md), [chart.md](../chart/chart.md)

`ProjecturedStatistics` shows what the editor loop measures about itself, such as the time of a frame, as a table and as a plot in a tab. This document says how the two documents get their numbers without a cost when no view is open, and how a person gets the frames out of the program.

## How it works

The kernel records each frame in a `FrameSampleStore` on the editor, `editor.frame_samples`. The store keeps the last 1000 frames in a ring: one column for each measurement name, and one column of frame end times. A frame that did not measure a name holds `NaN` for it. This package only reads that store.

**The producer gives the unit.** `record_frame_sample!` takes the times, in seconds, and the counts in two groups, and the store keeps the unit of each name: `:second` or `:count`. A summary and a column of the ring carry that unit, so no reader guesses a unit. A document holds times in seconds, and a view shows them in milliseconds.

`FrameStatistics` holds `rows`, one `FrameMeasurement` for each measurement name, and `frame_count`, the number of frames since the start when the table last showed them. A row has its unit, the count, the minimum, the maximum, the mean, the standard deviation and the total over the frames that the ring holds. So the first frames, which include compilation, leave the table once 1000 newer frames arrive.

`FramePlot` holds the frame numbers of the ring, and one column in seconds for each time measurement. A column is one cell, for the same reason as a column of a chart series.

One table and one plot exist for each session, `get_session_frame_statistics()` and `get_session_frame_plot()`. The insertion names `statistics` and `frame plot` give them.

`FrameStatisticsFeed` moves the numbers into the two documents:

- It flushes a document only when a view reads that document **and** the frame count that the document last showed differs from the count of the store. Each document keeps its own count: the table in `frame_count`, and the plot as the number of its last frame. So a plot opened after the table flushed gets its frames at once, with no new frame. The test for a view is `has_dependents` on a cell that every view reads: `frame_count` of the table, and `names` of the plot. So an editor with no statistics tab and no plot tab records the frames and formats nothing.
- It never wakes the editor. Its data comes only with frames, so a wake would make frames that feed themselves. Instead `compute_wake_deadline` returns the flush interval, 0.25 seconds by default, while a view is open.
- `flush_frame_statistics!` updates a row field by field, and it writes a field only when its number changed. A cell write invalidates its readers even when the value is the same, so an unchanged number must not be written.
- `flush_frame_plot!` writes new columns on each flush, and it writes the names only when they changed.

`FrameStatisticsToSyntax` prints a head line with the frame count, a column header, and one line for each row, in DejaVu Sans Mono so that the columns align. The `unit` column says `ms` for a time. A time prints in milliseconds with two decimals, and its total with none. A count prints as a whole number, and its mean and deviation with one decimal. When the ring holds fewer frames than the session had, the head line says how many the rows cover.

`FramePlotToChart` projects the plot onto a `Chart` with one line for each time measurement: the frame number on x, and the time in milliseconds on y. It builds the chart once. The list of lines derives from `names`, and the columns of each line derive from `frames` and `columns`, so a flush repaints the plot and prints nothing again.

`write_frame_samples!(path, editor.frame_samples)` writes the frames of the ring as CSV, with a time in milliseconds in a column whose name ends in `_ms`. `collect_recent_frame_samples` gives the same frames as vectors.

## How it fits

`ProjecturedStatistics` depends on the kernel for the feed contract and the performance layer, on `ProjecturedSyntax` and `ProjecturedText` for the table, on `ProjecturedChart` and `ProjecturedProjection` for the plot, and on `ProjecturedNatural` for its rows. `ProjecturedShell` gives the editor a `FrameStatisticsFeed` in `run_with_window_tools`, and the toolbar has a button that opens the table and one that opens the plot.

The package registers two natural rows. The syntax row `:statistics` draws a `FrameStatistics` with `FrameStatisticsToSyntax`. The graphics row `:frame_plot` draws a `FramePlot` through `FramePlotToChart`, `ChartToChartPlot` and `ChartPlotToGraphicsCanvas`. It also registers both documents as `.pred` types, so a saved window can hold their tabs. `MessageLog` has the same registrations; see [log.md](../log/log.md).

`pred_arguments` saves nothing: the numbers of one session are not the numbers of the next.

## Design decisions

- **A feed can ask whether anyone looks.** `has_dependents` on a cell of the target document answers it, so the feed needs no registry of tabs.
- **This feed has a deadline, not a wake.** The log feed wakes on each message; this feed would wake itself. [log.md](../log/log.md) is the other side of the comparison.
- **The table summarizes the recent frames.** A summary since the start keeps the compile time of the first frames in its maximum for the whole session.
- **The producer gives the unit.** The producer knows which values are times, so it gives them in a group of their own. A unit that a reader reads from the spelling of a name breaks when a measurement gets a name that does not follow the rule.
- **The plot is a projection into the chart domain.** `FramePlot` holds no chart. `FramePlotToChart` is the edge between the two domains, as `PAR-DOMAINS-INDEPENDENT` asks.

## Usage

```julia
run_window_editor(document, projection, "Title"; backend = SdlBackend(),
                  feeds = Feed[FrameStatisticsFeed()])
```

Then open a tab and type `statistics` or `frame plot`, or press the toolbar button. To keep the frames, evaluate `write_frame_samples!("frames.csv", editor.frame_samples)`. `example/projectured/FeedExamples.jl` builds the table view with `FrameStatisticsToSyntax()`.

- Test: `test_frame_samples()` in `test/kernel/performance/FrameSampleTest.jl` covers the ring, the summary, the units and the CSV text. `test/projectured/editor/FrameStatisticsFeedTest.jl` covers the flush of both documents, the gate of each document, the text of the table and the lines of the plot, and `test_tool_views()` in `test/projectured/projection/ToolViewTest.jl` checks that a tab draws each document. The package has no suite of its own.

## Limits

- `run_with_window_tools` makes the feed with the default interval. No setting changes it.
- The ring holds 1000 frames. `Editor` makes its store with the default capacity, and no setting changes it.
- The plot shows only time measurements. The counters are in the table and in the CSV file.
