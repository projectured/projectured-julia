# The performance counters keep times and counts apart

> **Status (2026-09-24): IN PROGRESS.** Step 1 is done.

The counter part of the kernel performance layer writes nanoseconds from
`@performance_time` and counts from `@count_performance` into one
`Dict{Symbol,Int}`. Two readers each keep a list of keys and a conversion:
`perf!` divides the three stage times by `1e6`, and `record_frame_measurements!`
divides the same keys by `1e9` and lists the four counts again. A new
`@performance_time` key is lost in both, with no error. The frame part took the
unit from the producer in `plan/done/frame-sample-api.md`; this plan does the
same for the counters.

The review of the layer found three more points in the same file:

- `record_performance!` has no caller outside its test.
- `@performance_time` breaks the verb-first rule of the naming law; only a
  declarative macro is exempt.
- `get_performance_counters` says that the extra keys come from
  `record_performance!`, `@count_performance` names its consumer, and the
  optional `store` argument of `with_performance_counters` has no caller.

## Decisions of the owner (2026-09-24)

- `PerformanceCounter.jl` is unsealed for this plan.
- The counter store keeps times and counts apart, and every reader forwards
  every key of each group.
- `record_performance!` goes, `@performance_time` takes a verb-first name, and
  the text points are fixed.

## The API after the change

```
PERFORMANCE_COUNTERS_ENABLED
with_performance_counters(f)
get_performance_counters() -> (; counts, times)   # two Dict{Symbol,Int}; times in ns
@count_performance key
@measure_performance_time key expr
```

## Steps

### Step 1 — unseal the file

Change the mark of `performance/PerformanceCounter.jl` in `SEALING.md` to ⬜,
with the owner's permission.

### Step 2 — the store, its readers and the guides

- `PerformanceCounter.jl`: a store holds `counts` and `times`.
  `@count_performance` writes `counts`, `@measure_performance_time` writes
  `times` in nanoseconds, and `get_performance_counters` answers copies of both.
  `record_performance!` and the `store` argument go.
- `EditorLoop.jl`: the three stages use `@measure_performance_time`, and `perf!`
  logs every count and every time.
- `Feeds.jl`: `record_frame_measurements!` forwards every time, in seconds, and
  every count, in name order.
- `FrameSample.jl`: the header says what one frame costs.
- The tests and the guides that name the old API: `cell.md`, `editor.md` and the
  example in `naming-rules.md`.

Test: `test_performance_counter()`, `test_frame_samples()`,
`test_frame_statistics_feed()`, `test_kernel_layering()`, `test_declared_api()`,
the printer locality test, `test_naming()`, `test_arguments()`,
`test_documentation()`, `test_export_collisions()`. The counters are compiled
out by default, so the counting branch runs once more with
`PROJECTURED_PERFORMANCE_COUNTERS=true`.

### Step 3 — the audit and the plan

Audit the three files of the layer again. Move this plan to `plan/done/`.

## Progress

- [x] Step 1
- [ ] Step 2
- [ ] Step 3
