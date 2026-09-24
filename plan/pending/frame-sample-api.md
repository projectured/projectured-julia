# The frame sample API: units as data, one summary, no flush counter

> **Status (2026-09-24): IN PROGRESS.** No step is done yet.

The frame sample store of the kernel performance layer exports 12 names. Three
of its shapes are weak:

- `is_frame_time_measurement(name)` reads the unit from the spelling of a name.
  The view, the plot flush and the CSV writer each ask it, and the view turns a
  `String` back into a `Symbol` to ask. The producer knew the unit and lost it
  at `record_frame_sample!`.
- `count_unflushed_frame_samples` and `mark_frame_samples_flushed!` keep a
  counter for one consumer in the kernel store, and the table and the plot
  share it: a plot opened after the table flushed waits for the next frame.
- `FrameMeasurementSummary` is mutable and exposes its fold, so a reader needs
  `compute_frame_standard_deviation` to get the deviation.

## Decisions of the owner (2026-09-24)

- The producer gives the unit, in two groups:
  `record_frame_sample!(store; times, counts, end_time)`. A time is in seconds.
- Each document keeps the frame count that it last showed, and the store keeps
  no flush counter.
- The summary is an immutable answer with its unit and its standard deviation.

## The API after the change

```
FrameSampleStore(; capacity = 1000)
record_frame_sample!(store; times = (), counts = (), end_time = time())
get_frame_count(store)
get_frame_measurement_names(store)
compute_frame_measurement_summary(store, name) -> FrameMeasurementSummary
collect_recent_frame_samples(store)      # each column carries its unit
write_frame_samples!(io_or_path, store)
FrameMeasurementSummary                  # the type of the answer
```

Gone: `is_frame_time_measurement`, `compute_frame_standard_deviation`,
`count_unflushed_frame_samples`, `mark_frame_samples_flushed!`.

## Steps

### Step 1 — the store, the producer and the statistics package

- `FrameSample.jl`: the store keeps a unit for each name, `:second` or
  `:count`, from the group that first gave the name. A name given later in the
  other group is an error. The fold is private, and the summary is immutable:
  `unit`, `count`, `minimum`, `maximum`, `mean`, `standard_deviation`, `total`.
  The store has no flush counter.
- `Feeds.jl`: `record_frame_measurements!` gives the frame time and the stage
  times as `times`, and the reactive counters as `counts`.
- `ProjecturedStatistics`: a `FrameMeasurement` row carries its `unit`. The
  table flushes when a view shows it and its `frame_count` is behind the store.
  The plot flushes when a view shows it and its last frame is behind the store.
  The view and the plot read the unit of a row or a column.

Test: `test_frame_samples()`, `test_frame_statistics_feed()`,
`test_tool_views()`, `test_kernel_layering()`, `test_export_collisions()`.

### Step 2 — the guides, the audit, the plan

Update `statistics.md` and `editor.md`. Audit `PerformanceModule.jl` and
`FrameSample.jl` again. Move this plan to `plan/done/`.

## Progress

- [ ] Step 1
- [ ] Step 2
