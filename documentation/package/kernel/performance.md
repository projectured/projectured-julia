# Performance

> **Kind:** reference · **Status:** current · **Stands on:** [architecture.md](architecture.md)

This guide says how the editor measures itself: the counters that count the work of the cells and time the stages of a frame, and the store that keeps the measurements of the last frames. It describes each fragment of the performance layer, `source/kernel/performance/`, and the main uses of its public names. The [statistics guide of the platform](../platform/statistics/statistics.md) describes the view that draws the measurements.

The performance layer is layer 2 of the kernel. It imports no other layer, and it loads before the cell layer, because the cell engine counts its reads, computations, invalidations and writes with it. Nothing in it is a cell, and nothing in it names a document.

## The switch

The counters are in the kernel only when the preference `performance_counters` of `ProjecturedKernel` was `true` when the kernel was compiled. It is `false` by default, so a normal build has no instrumentation. `PERFORMANCE_COUNTERS_ENABLED` holds the value that the kernel was compiled with:

```julia
using Preferences, ProjecturedKernel
set_preferences!(ProjecturedKernel, "performance_counters" => true)
# start Julia again: the package cache compiles the kernel with the counters
```

The package cache names a compiled kernel with a hash of its preferences. So the first start after a change compiles the kernel once, and a change back loads the kernel that was compiled before. The preference goes in the `LocalPreferences.toml` of the active environment.

Code above the layer reads `PERFORMANCE_COUNTERS_ENABLED` to skip work that only the counters need. The editor reads it before it logs the counts of a frame, and before it gives the counts to the frame store.

## The counters of a scope

`run_with_performance_counters(f)` binds a new counter store while `f` runs, and every cell operation inside `f` counts into it. `get_performance_counters()` answers copies of its counts and its times:

```julia
counters = run_with_performance_counters() do
    work()
    get_performance_counters()
end
get(counters.counts, :reads, 0)        # the cells that work() read
```

A store holds four counts from the start: `:reads`, `:computes`, `:invalidations` and `:writes`. `:computes` counts each computation that starts, also one that throws. Times are in nanoseconds, and a time never goes into the counts. Outside a scope there is no store, so the counters read empty, and a cell operation counts nothing. Without the counters, `run_with_performance_counters(f)` is `f()`.

The store is a `ScopedValue`: a binding of the task that ran the scope and of the tasks that it starts. So many editors in one process count apart. The store is a collector outside the reactive graph: a computation writes it, and a computation must never read it, so no cached value depends on it. The law names it beside the fault store (PAR-NO-WRITE-IN-THUNK in [architecture-invariants.md](../../rule/architecture-invariants.md)).

## Count and time your own work

`@count_performance key` adds one to the count `key`. `@measure_performance_time key expr` runs `expr`, adds the nanoseconds that it took to the time `key`, and answers the value of `expr`:

```julia
@count_performance :layout_passes
tree = @measure_performance_time :layout_time compute_layout(document)
```

Without the counters, `@count_performance` expands to `nothing` and `@measure_performance_time` to its expression, so a count costs nothing in a normal build. A key names a count or a time, never both: the frame store throws an `ArgumentError` for a name in both groups. The editor times its three stages as `:read_time`, `:evaluate_time` and `:print_time`.

## The frame store

A `FrameMeasurementStore` keeps the measurements of the last `capacity` frames, 1000 by default, in a ring. Each name has a column of values and a unit: `:second` for a time and `:count` for a count, from the group that first gave the name. A frame that did not measure a name holds `NaN` in its column. The store also counts the frames since the start.

```julia
store = FrameMeasurementStore(capacity = 1000)
record_frame_measurements!(store; times = [:frame_time => 0.016],
                           counts = [:reads => 120], end_time = time())
get_frame_count(store)                 # 1
get_frame_measurement_names(store)     # [:frame_time, :reads], in first-seen order
```

`record_frame_measurements!` takes its times in seconds and its counts as `name => value` pairs, and `end_time` in seconds, `time()` by default. These calls throw an `ArgumentError` and leave the store as it was:
- a name in the other group than the one that first gave it;
- a name in both groups of one call;
- a name that is not a `Symbol`, or a value that is not a number.

A capacity below 1 throws an `ArgumentError` too.

A store belongs to one editor, and only the task of that editor writes it, so it has no lock. It is not made of cells: a view that shows it polls `get_frame_count`, and draws again when the count grew.

## Summaries and single frames

`compute_frame_measurement_summary` answers a `FrameMeasurementSummary` of one name over the frames in the ring: its unit, the count of frames that measured it, and the minimum, the maximum, the mean, the standard deviation and the total of their values.

```julia
summary = compute_frame_measurement_summary(store, :frame_time)
(summary.mean, summary.maximum)        # the mean and the worst frame time
```

A frame that did not measure the name does not count. With no value, the minimum, the maximum and the mean are `NaN`; below two values, the standard deviation is `0.0`. A name that the store does not know throws a `KeyError`.

`collect_recent_frame_measurements` answers the single frames, oldest first, as new vectors: the frame numbers, the end times, and one column of `(; name, unit, values)` for each name:

```julia
recent = collect_recent_frame_measurements(store)
slowest = recent.frames[argmax(recent.columns[1].values)]
```

## Keep the frames

`write_frame_measurements!` writes the frames in the ring as CSV, to a stream or to a file path, and answers how many frames it wrote:

```julia
write_frame_measurements!("frames.csv", store)
```

The columns are `frame`, `end_time_s` and one column for each name. `end_time_s` counts the seconds from the end of the first frame that it writes. A time is in milliseconds, and its column name ends in `_ms`; every time is rounded to a microsecond. A field is empty where a frame did not measure the name.

## Layer structure

The layer is the folder [source/kernel/performance/](../../../source/kernel/performance/), and `PerformanceModule` is its one module.

```
performance/PerformanceModule.jl   (PerformanceModule): the module, its exports and its include order
    ├─ PerformanceCounter.jl : the switch, the counter store of a scope, and the two macros
    └─ FrameMeasurement.jl   : FrameMeasurementStore, its record, its summary, its frames and its CSV
```

The layer has no interface file: it declares no seam that a layer above answers.

## Where the layer is used

- The cell engine counts its reads, computations, invalidations and writes, in `ReactiveCell.jl`.
- The editor runs each frame in a scope of its own, in `EditorLoop.jl`, and times its read, evaluate and print stages there. With the counters, it logs the counts of each frame that applied an operation.
- Each editor has a `FrameMeasurementStore`, `editor.frame_measurements`. At the end of each frame, `record_frame_performance!` in `Feeds.jl` records the frame time. With the counters, it also records every count and every time of the frame, in seconds.
- The statistics view of the platform draws the store; see the [statistics guide of the platform](../platform/statistics/statistics.md).
- Code that waits for the first frame, such as the check of a release, polls `get_frame_count`.

## Try it

`print_performance_example()` in `ProjecturedKernelExample` prints a REPL session with the layer: the switch, a scope and a timed expression, the counters outside a scope, and a frame store with its records, its summaries, its unit rule, its ring and its CSV. Each line runs as it prints. A session can not show a count: the counts of a frame come from the cells of an editor, in a build with the counters.

```julia
using ProjecturedKernelExample
print_performance_example()
```

## Design decisions

- **The counters are compiled in only on request.** A cell read is the hottest path of the editor, so a normal build carries no counter there.
- **The switch is a preference.** The package cache tracks a preference, so a change compiles the kernel again by itself, and no build can keep a stale value. Preferences.jl is the one dependency of the kernel; every process that loads the platform loads it already.
- **Counts and times are kept apart.** The unit of every key is clear, and the frame store throws an `ArgumentError` for a name in both groups. See [plan/done/performance-counter-units.md](../../../plan/done/performance-counter-units.md).
- **The producer gives the unit, and a summary is one answer.** See [plan/done/frame-sample-api.md](../../../plan/done/frame-sample-api.md).
- **The counter store is a binding of a task, not a field of the editor.** A frame binds its own store, so a cell operation outside every frame counts nothing.
