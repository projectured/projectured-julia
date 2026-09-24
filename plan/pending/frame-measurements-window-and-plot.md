# Frame measurements: frame names, a window of recent frames, milliseconds and a plot

> **Status (2026-09-24): IN PROGRESS.** Steps 1 to 5 are done.

The editor measures each frame into `editor.frame_samples`, a `FrameSampleStore`
of the kernel performance layer. The store keeps only running summaries since
the start, so no single frame can be written out or plotted. The statistics tab
shows every value in seconds with four significant digits, and it does not say
the unit. The exported names of the store do not say that they are about frames.

This plan gives the names a `frame` word, keeps the last 1000 frames, makes the
table summarize those frames, shows times in milliseconds with a unit column,
and adds a plot of the frame times.

## Decisions of the owner (2026-09-24)

- The names in the table of step 1.
- The unit of a measurement follows its name: a name that ends in `_time` is a
  time in seconds. Every other measurement is a count.
- The window holds 1000 frames.
- The table summarizes the window, not every frame since the start.
- The plot is part of this work.

## Constraints

- `performance/PerformanceCounter.jl` is sealed. No step changes it.
- The window is bounded: 1000 frames, whatever the length of the session.
- The kernel store stays outside the reactive graph and names no document
  (`PAR-STORE-THEN-DRAIN`, `PAR-NO-CONSUMER-DOCS`).
- The plot is a projection into the chart domain. A statistics document holds
  no chart (`PAR-DOMAINS-INDEPENDENT`).
- A document holds times in seconds. A view converts them to milliseconds.

## Steps

### Step 1 — the names say `frame`, and the audit findings of the layer

| Now | New |
| --- | --- |
| `MeasurementSummary` | `FrameMeasurementSummary` |
| `record_measurement!` | private: `_record_frame_measurement!` |
| `compute_standard_deviation` | `compute_frame_standard_deviation` |
| `find_measurement_summary` | `find_frame_measurement_summary` (step 2 replaces it) |
| `get_measurement_names` | `get_frame_measurement_names` |
| `count_unflushed_samples` | `count_unflushed_frame_samples` |
| `mark_samples_flushed!` | `mark_frame_samples_flushed!` |

Rename with `julia-rename.jl`. The same step fixes the audit findings of the
two unsealed files:

- the docstrings of `PerformanceModule.jl` and `FrameSample.jl` name the code
  above the layer;
- the header of `FrameSample.jl` says one sentence twice;
- `find_measurement_summary` has a docstring with no sentence;
- `get_measurement_names` returns the vector of the store itself;
- the two export blocks of `PerformanceModule.jl` indent differently.

Test: `test_frame_samples()`, `test_kernel_layering()`.

### Step 2 — the window of recent frames

`FrameSampleStore(; capacity = 1000)` keeps, besides the names:

- one circular column of values for each measurement name, and a `NaN` where a
  frame did not measure that name;
- one circular column of frame end times, in seconds of `time()`;
- the number of frames since the start, and the number since the last flush.

The running summaries go. A summary is computed from the window when a reader
asks for it, so `find_frame_measurement_summary` becomes
`compute_frame_measurement_summary(store, name)`: the verb follows the work.
`FrameMeasurementSummary` and its fold stay, and the fold runs over the window.

New exported names:

- `record_frame_sample!(store, measurements; end_time = time())` — the frame
  end time is a keyword, so a test can give it.
- `get_frame_count(store)` — the frames since the start.
- `get_recent_frame_samples(store)` — the window in time order: the frame
  numbers, the end times, and one column for each measurement.
- `is_frame_time_measurement(name)` — `true` for a name that ends in `_time`.
  The unit convention lives in this one place.
- `write_frame_samples!(io, store)` — the window as CSV: `frame`, `end_time_s`
  from the first frame of the window, then one column for each measurement, a
  time in milliseconds with a `_ms` suffix.

Test: `test_frame_samples()` covers the wrap of the ring, a name that appears
late, the summary of the window, and the CSV text.

### Step 3 — the table summarizes the window

`flush_frame_statistics!` writes the summaries of the window, and
`frame_count` becomes the frames since the start. The view header says how
many frames the rows cover. `statistics.md` says what a row covers.

Test: the frame statistics feed test.

### Step 4 — milliseconds, a unit column and rounding

`FrameStatisticsToSyntax` adds a `unit` column. A time row shows `ms`, with two
decimals, and the total with no decimal. A count row shows the count, the
minimum and the maximum as integers, and the mean and the deviation with one
decimal. The same projection draws the statistics overlay, so both change.

Test: `test_tool_views()` and the frame statistics feed test.

### Step 5 — the plot

- `FramePlot`, a document of `ProjecturedStatistics`: the frame numbers, and
  one column in seconds for each time measurement of the window.
- `FramePlotToChart`, a projection from `FramePlot` to a `Chart` with one
  `ChartLineSeries` for each column, in milliseconds, frame number on x. The
  columns of each series derive from the document, so a flush repaints the plot
  and prints nothing again.
- A natural graphics row: `FramePlot` draws through `FramePlotToChart`,
  `ChartToChartPlot` and `ChartPlotToGraphicsCanvas`.
- One plot for the session, `get_session_frame_plot()`, the insertion name
  `frame plot`, and a toolbar button next to Statistics.
- `FrameStatisticsFeed` flushes the plot too, only while a view shows it.
- `ProjecturedStatistics` depends on `ProjecturedChart`. `ProjecturedChart`
  does not depend on it, so the graph of packages has no cycle.

Test: a printer test of `FramePlotToChart`, and the feed test.

### Step 6 — the guides, the audit, the plan

Update `statistics.md` and every guide that names an old name. Audit the two
unsealed files of the layer again. Move this plan to `plan/done/`.

## Progress

- [x] Step 1 — renamed with `julia-rename.jl`; `test_frame_samples()` 16 pass,
  `test_performance_counter()` 3 pass, `test_kernel_layering()` 10 pass. The
  two fold tests call the store, because the fold helper is private now.
- [x] Step 2 — `test_frame_samples()` 29 pass, `test_kernel_layering()` 10 pass,
  `test_declared_api()` 111 pass. Decisions made while implementing:
  - The reader of the window is `collect_recent_frame_samples`, not
    `get_recent_frame_samples`: it builds new columns with a loop, and the
    naming law gives `get_` only to a value at a known place.
  - `compute_frame_measurement_summary` answers a summary with a count of zero
    for a name that no frame measured, not `nothing`.
  - `write_frame_samples!` also takes a path, so one call from the evaluator
    writes a file.
  - The flush of the table had to call the new summary in this step, so the
    table summarizes the window from this step on. The flush now writes a field
    only when its number changed: a cell write invalidates its readers even
    when the value is the same, so the old docstring claim was not true.
- [x] Steps 3, 4 and 5 — one commit, because the three steps change the same
  statistics files. `test_frame_statistics_feed()` 35 pass, `test_tool_views()`
  19 pass. An offscreen render of the table and of the plot, with 1200
  synthetic frames, shows the unit column, the milliseconds and the lines.
  Decisions made while implementing:
  - The head line keeps its form `N frames`, and adds `, the rows cover the
    last M` when the ring holds fewer frames than the session had.
  - The number column `count` is `frames`, so it does not read as the unit of
    a count measurement. A row that no recent frame measured shows a dash.
  - `__init__` moved from `FrameStatisticsToSyntax.jl` to the module file,
    where code-quality section 1 puts it. It registers both rows.
  - The feed tests the `names` cell of the plot, not `frames`: a plot with no
    series reads only `names`, so a test on `frames` never gave the first flush.
  - `FramePlotToChart` calls the generated `Chart` constructor, because the
    keyword constructor copies the list of series and breaks its derivation.
  - The CSV rounds a time to a microsecond (a separate commit): the first
    render showed sixteen digits and floating-point noise.
  - `test_export_collisions()` fails on `format_fault_message`, which the
    kernel `FaultModule` and `FaultViewModule` both export. It fails on main
    too, and this plan does not change it.
- [ ] Step 6
