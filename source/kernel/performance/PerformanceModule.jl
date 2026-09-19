"""
    PerformanceModule

What the editor measures about itself. Two instruments share the concept and
this namespace, and they differ by lifecycle:

- [`PerformanceCounter.jl`](PerformanceCounter.jl) — the conditionally-compiled
  counters. `with_performance_counters(f)` binds a fresh store for one frame's
  dynamic extent, and the reactive hot path counts into it through
  `@count_performance` / `@performance_time`.
- [`FrameSample.jl`](FrameSample.jl) — the per-editor `FrameSampleStore`. The
  loop folds one sample per frame into it (the frame time always, the counters
  above when they are compiled in), and a statistics feed flushes the
  summaries into a document on its own deadline.

Nothing here is a cell and nothing here names a document. The layer sits
below `cell` because the reactive engine is the first thing that counts.
"""
module PerformanceModule

using Base.ScopedValues: ScopedValue, with

export with_performance_counters, get_performance_counters, record_performance!,
    @performance_time, @count_performance, PERFORMANCE_COUNTERS_ENABLED
export MeasurementSummary, FrameSampleStore,
       record_measurement!, record_frame_sample!, compute_standard_deviation,
       find_measurement_summary, get_measurement_names,
       count_unflushed_samples, mark_samples_flushed!

include("PerformanceCounter.jl")
include("FrameSample.jl")

end # module
