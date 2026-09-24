"""
    PerformanceModule

What the editor measures about itself. Two instruments share this namespace,
and they differ by lifecycle:

- [`PerformanceCounter.jl`](PerformanceCounter.jl) — the conditionally-compiled
  counters. `with_performance_counters(f)` binds a fresh counter store for the
  dynamic extent of `f`. `@count_performance` adds to its counts, and
  `@measure_performance_time` adds to its times.
- [`FrameSample.jl`](FrameSample.jl) — the `FrameSampleStore`, one for each
  editor, which keeps the measurements of the last frames and summarizes them.

Nothing here is a cell, and nothing here names a document. The module imports
nothing from the kernel, so every layer above it can count.
"""
module PerformanceModule

using Base.ScopedValues: ScopedValue, with

export PERFORMANCE_COUNTERS_ENABLED, with_performance_counters,
       @count_performance, @measure_performance_time, get_performance_counters
export FrameSampleStore, record_frame_sample!,
       get_frame_count, get_frame_measurement_names,
       FrameMeasurementSummary, compute_frame_measurement_summary,
       collect_recent_frame_samples, write_frame_samples!

include("PerformanceCounter.jl")
include("FrameSample.jl")

end # module
