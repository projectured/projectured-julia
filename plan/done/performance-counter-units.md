# The performance counters keep times and counts apart

> **Status (2026-09-24): DONE.** The counters keep times and counts apart, every
> reader forwards every key, and the layer exports 5 counter names and 8 frame
> names. `PerformanceCounter.jl` is unsealed until the owner seals the layer.

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
- [x] Step 2 — with the counters compiled out: `test_performance_counter()` 3
  pass, `test_frame_samples()` 32, `test_frame_statistics_feed()` 41,
  `test_tool_views()` 19, `test_kernel_layering()` 10, `test_declared_api()`
  111; `test_naming()`, `test_arguments()`, `test_documentation()` and
  `test_export_collisions()` pass. With `PROJECTURED_PERFORMANCE_COUNTERS=true`
  and `--compiled-modules=no`, because the switch is fixed at precompile time:
  `test_performance_counter()` 11 pass, `test_frame_samples()` 34 pass.
  `test_selection_localities()` fails on main too: 8998 pass and 11250 fail on
  `c6da5faf`, 9207 and 11516 here. Every example has the same outcome in both;
  only the examples that read files from the disk probe a different number of
  selections, because the worktree has other files. Decisions made while
  implementing:
  - The macro is `@measure_performance_time`: `measure_` is the verb that the
    naming table gives to measuring.
  - `get_performance_counters()` answers `(; counts, times)`, so no new
    exported type is needed.
  - The readers forward the keys in name order, so the order of the rows does
    not depend on the order of a dictionary.
  - The two timed stages in `EditorLoop.jl` put their expression in a `begin`
    block, because the longer macro name pushed the continuation lines past 90
    characters.
  - The comment on `@info` in `perf!` said that the logger avoids a closed
    pipe; it now says that the line reaches every logger that the process
    installed, as the fault cascade says.
- [x] Step 3 — the audit of `PerformanceModule.jl`, `PerformanceCounter.jl` and
  `FrameSample.jl` finds nothing more.
