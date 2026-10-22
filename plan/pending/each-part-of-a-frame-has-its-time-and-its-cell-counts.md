# Each part of a frame has its time and its cell counts

Status: in progress, 2026-10-22, on the branch `frame-parts`, in the worktree
`projectured-julia-frame-parts`.

## The ask

The owner, 2026-10-22, looked at the frame statistics of a binary with the
performance counters, and asked which count belongs to which part of the frame
loop: "cell_reads during what? the reader, the evaluator or the printer of the
frame loop?". Today the counts without a prefix are of the whole frame, and only
the device read and the device write have counts of their own
(`plan/done/a-frame-measures-its-device-read-and-write.md`). To a table of seven
parts that do not overlap, each with its time and its cell counts, the owner
answered: "yes, it makes sense but the UI should change, the tables will become
huge". To the layout below: "looks good but use similar mechanism to select what
is displayed in the table (e.g. mean | minimum| maximum | total vs show: [time ▾])".

## The facts

1. **The stages of a frame overlap with the device halves.** `_time_frame_stage`
   (`Feeds.jl`) times the stages `:feed`, `:report`, `:read`, `:evaluate` and
   `:print`. `_time_device_half` times `take_from_devices!` inside the read stage
   and `write_to_devices!` inside the print stage. So `:read_time` holds
   `:device_read_time`, and `:print_time` holds `:device_write_time`.
2. **The counts are of the scope of the frame.** `run_measured_frame!` binds one
   counter store. The cell engine counts six keys into it (`ReactiveCell.jl`):
   `:reads`, `:checks`, `:computes`, `:stops`, `:invalidations` and `:writes`.
   The record copies every key of the scope under its own name. Only the two
   device halves split four of the six.
3. **The frame store is flat and sealed.** `FrameMeasurement.jl` keeps one
   column for each name, with its unit. It has no notion of a part. It is sealed,
   and this plan does not change it.
4. **The page is one summary table and one frame table.** `FrameStatisticsToWidget.jl`
   shows one summary row for each name, and one frame column for each name. With
   the counters there are 26 names, and with this plan about 60.
5. **A choice control exists.** `WidgetToggleGroup` shows a row of segments, one
   pressed, and writes the choice into a field of a target document.

## The model

- **Eight parts, in the order of the loop.** `feed` (`drain_feeds!`), `report`
  (`report_frame_faults!`), `input` (`take_from_devices!`), `reader` (the rest of
  the read stage: the reader of the projection), `evaluate`
  (`run_evaluate_stage!`), `print` (the rest of the print stage: `print_document`
  and a retry), `paint` (`write_to_devices!`, where the lazy print runs), and
  `frame`, the whole frame. The first seven do not overlap; `frame` holds them
  and the small work between them.
- **Seven measures.** `time`, and with the counters the six cell counts:
  `cell_reads`, `cell_checks`, `cell_computes`, `cell_stops`,
  `cell_invalidations` and `cell_writes`.
- **A name is `<part>_<measure>`.** For example `reader_time`,
  `paint_cell_computes`, `frame_cell_reads`. `frame_time` keeps its name and
  meaning. These names go: `read_time`, `device_read_time`, `device_write_time`,
  the eight `device_…` counts, and the six keys of the scope under their own
  names. `print_time` keeps its name and loses the paint.
- **The producer gives the shape.** The editor layer exports the parts and the
  measures in loop order, and the function that makes the name of a part and a
  measure. The view reads them and never reads a shape from the spelling of a
  name, by the rule that the producer gives the unit.
- **The other measurements stay as they are.** `held_time`,
  `garbage_collection_time`, `compile_time`, `yielded_time`, `allocated_bytes`,
  and every key that `@count_performance` or `@measure_performance_time` adds
  beyond the six cell counts.
- **The page.** Three parts, and two choices of one kind, a
  `WidgetToggleGroup` with the look `:row`:

  ```
  Frame statistics   366 frames                                        [Pause]

  Parts of a frame        [mean | minimum | maximum | deviation | total]
  part      time (ms)  reads   checks  computes  stops  invalidations  writes
  feed        4.49       …
  …
  paint      10.48    20893.5    …      566.3      …        0.0          7.6
  frame      45.77    28249.5  1325.1   603.0    728.0   1034.5         32.8

  Process, over the last 1000 frames
  measurement              unit  frames  minimum  maximum  mean  deviation  total
  …

  Frames, newest first    [time | reads | checks | computes | stops | invalidations | writes]
  frame  frame  feed  report  input  reader  evaluate  print  paint
  ```

  The summary choice holds the five statistics that a row keeps, `deviation`
  among them. The frame choice holds only the measures that the store has, so
  without the counters it holds `time` alone. The two choices are fields of the
  `FrameStatistics` document, view state as `anchor` is. A change of the frame
  choice builds the columns of the frame table again; a new frame still prints
  only its own row.

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves.

1. [ ] **The record.** In `Feeds.jl`, `Editor.jl` and `EditorLoop.jl`: the
   stages keep their cell counts beside their times, the record gives each part
   its time and its counts as `<part>_<measure>`, with `reader` and `print` as
   their stage less `input` and `paint`, and the exported table of parts and
   measures. Tests in `test/kernel/editor/FeedsTest.jl`: each part records its
   time; the seven parts add up to no more than the frame; with the counters each
   part records its six counts, and a cell read in the paint counts in `paint`
   and in `frame` only. Run the editor tests of the frame performance, the feeds,
   the fault barriers and the held frames, without and with the counters. The
   guides `editor.md` and `performance.md`. Commit.
2. [ ] **The page.** In `source/platform/statistics/`: the two choice fields of
   `FrameStatistics`, the table of the parts, the table of the process, the frame
   table with one column for each part, and the two toggle groups. Tests of the
   statistics slice and `FrameStatisticsFeedTest`: the parts table has a row for
   each part in loop order and the summary choice changes its numbers; the
   process table holds every other name; the frame choice changes the columns,
   and a new frame still prints only its own row. The statistics guide. Commit.
3. [ ] **A live check.** An SDL window on the offscreen driver shows the page,
   without and with the counters; a picture of each goes into the plan with the
   numbers. The plan moves to `plan/done/`. Commit.

## Not in this plan

- The slow frame report, which names its slowest stage as it does now.
- The `[perf]` line of `_log_performance_counters!`.
- A split of the keys that `@count_performance` adds beyond the six cell counts.
