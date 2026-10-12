# The re-audit of the performance layer

The owner, 2026-10-12, after the seal of the fault layer: "continue with next layer".
The performance layer, `source/kernel/performance/`, is layer 2 of the kernel. It goes
through the audit with four checks (SEALING.md, "The audit protocol").

The audit ran on main 01ba6251e. Two auditors read the code: one did the architecture
check, and one did the test, example and guide checks. The lead read the code behind
every Medium finding and confirmed each one. The tests pass:
`test_performance_counter` 9 of 9, `test_frame_measurements` 34 of 34.

## Result

The layer does not pass.

| File | Architecture | Tests |
| --- | --- | --- |
| `performance/PerformanceModule.jl` | A-2 | passes |
| `performance/PerformanceCounter.jl` | A-3, A-4, A-5, A-7; L02-1 open | T-1, T-4, T-5, T-6 |
| `performance/FrameMeasurement.jl` | A-1, A-4, A-5, A-6 | T-2, T-3, T-7 … T-13 |

The layer has no walkthrough (E-1) and no guide (G-1).

**What a default build shows.** The counters are compiled in only when
`PROJECTURED_PERFORMANCE_COUNTERS=true` was set when the kernel was precompiled. By
default it is not set: `run_with_performance_counters(f)` is `f()`,
`get_performance_counters()` is empty, and `@count_performance` expands to `nothing`. A
test sees a counter store only through private names. The frame store is fully
visible.

## Check 1: the architecture

- **A-1 (Medium)** — `record_frame_measurements!` promises that "a call that is an
  error leaves the store as it was" (`FrameMeasurement.jl:84-85`). The checks before the
  change cover only the units and a name in both groups. A value that `Float64` can
  not convert, or a name that is not a `Symbol`, throws after the frame count grew:
  the slot is `NaN` in every column, and its end time is stale. Fix: check those two
  before the change too, and throw an `ArgumentError`.
- **A-2 (Low)** — the export block (L02-4, never fixed): both statements are out of the
  order of definition, and the file is on `EXPORT_UNMIGRATED`.
- **A-3 (Low)** — the counter store is safe only as a collector that a computation
  writes and never reads. The layer does not say so, and the law says that the fault
  store is the only store that a computation writes. Fix: one sentence in the
  docstring of `get_performance_counters`, and one in the law
  (PAR-NO-WRITE-IN-THUNK).
- **A-4 (Low)** — docstring examples name the editor: `run_frame!(editor)`,
  `run_print_stage!(editor)`, `editor.frame_measurements`. The example
  `.counts[:reads]` throws `KeyError` in a default build.
- **A-5 (Low)** — L02-7 is only partly fixed. `PERFORMANCE_COUNTERS_ENABLED` has a
  comment and no docstring, and three names have no paragraph "Use it to":
  `record_frame_measurements!`, `FrameMeasurementSummary`, `FrameMeasurementStore`.
  The `ArgumentError` of `FrameMeasurementStore(capacity = 0)` is in no docstring.
- **A-6 (Low)** — the header of `FrameMeasurement.jl` repeats the docstring of the store,
  and its claim of "one lookup and one store for each measurement" is false.
- **A-7 (Low)** — the counter store takes one key as a count and as a time; the frame
  store then refuses the frame. Fix: the two macro docstrings say that a key names a
  count or a time, never both.

The other requirements pass. Of the re-audit of 2026-09-27: L02-2, L02-3, L02-5, L02-6
and L02-8 stay fixed; L02-4 is A-2; L02-7 is A-5; L02-1 is open.

## Check 2: the tests

- **T-1 (Medium)** — `@count_performance` has no test, and no test sees the effect of
  `PERFORMANCE_COUNTERS_ENABLED`. A test in a scope that the private names bind can
  assert the count when the switch is on and none when it is off.
- **T-2 (Medium)** — no test names `FrameMeasurementSummary`, and its promise of `NaN`
  for a name with no value is not asserted.
- **T-3 (Medium)** — `write_frame_measurements!(path, store)` has no test, and three
  guides tell a person to use it.
- **T-4 … T-13 (Low)** — the value of a scope; the copies of `get_performance_counters`;
  the answer of `record_frame_measurements!`; the default `end_time`; the other
  direction of the unit error; the copy of the names; the names of the columns; the
  default capacity and the `ArgumentError` of capacity 0; an empty store in the CSV.
  T-6, the counted branch, waits for L02-1.

## Check 3: the examples

- **E-1 (Medium)** — no walkthrough. A REPL session can show the frame store fully, and
  the counters only as far as the default build has them: a scope answers the value of
  its body, a timed expression its value, and the counters read empty. The test of the
  full text puts the value of `PERFORMANCE_COUNTERS_ENABLED` in its one line, so it
  passes in both builds. The auditor ran a draft of 17 lines in both builds.

## Check 4: the guide

- **G-1 (Medium)** — no guide `documentation/package/kernel/performance.md`. The section
  "PerformanceModule: the counters" of `cell.md` holds true text that moves to it; it
  has nothing on the frame store, which `statistics.md` describes.
- **G-2 (Low)** — `cell.md` speaks of demos that read the counts, and none does; it says
  "compile again" but not how, and a restart loads the old image.
- **G-3 (Low)** — after the move, `cell.md`, `architecture.md` and the package index
  point to the new guide.

## Decisions for the owner

1. **L02-1 — how the counter switch reaches the package cache.** Today the switch is an
   environment variable that the package cache does not track, so a change needs a
   rebuild that no text names, and a stale image gives no message.
   - A: a compile-time preference with Preferences.jl. The cache tracks it. The kernel
     gets its first dependency.
   - B: a run-time switch for each editor. The counters are always compiled in, and
     every cell read looks up the store. The cost needs a measurement.
   - C: the switch stays as it is. The guide and the docstring name the rebuild, and a
     load with the counters compiled in says so once.
   - **Recommended (the lead's): C.** On 2026-09-29 the lead recommended A. The fact
     that moved the view: the owner's rule of 2026-10-08 that a new dependency comes
     from an adapter, not from the platform, and the kernel is below the platform. B
     costs every cell read.
2. **A-3 — one sentence in the law.** PAR-NO-WRITE-IN-THUNK names the fault store as the
   only store that a computation writes; the counter store is a second one, with the
   same two properties: no cell depends on it, and no computation reads it.
   **Recommended (the lead's): yes.**

## Steps

- [x] 1. The fixes: A-1, A-2, A-4 … A-7, and A-3 after decision 2. The owner agreed
  to decision 2 on 2026-10-12. A-1: the check before the change also throws an
  `ArgumentError` for a name that is not a `Symbol` and a value that is not a number.
  A-3: the docstring of `get_performance_counters` and the law name the counter store
  as the second store that a computation writes. The examples use `work()`,
  `parse(Int, text)` and a variable `store` in place of the editor.
- [x] 2. The tests T-1 … T-13, except T-6, and the walkthrough `print_performance_example`
  (E-1). T-6, the counted branch, now runs in a build with the preference on; no
  default job sets it. The walkthrough test puts the value of
  `PERFORMANCE_COUNTERS_ENABLED` in the one line that shows it, so it passes in both
  builds. Checked in both: the default build (15, 55, 2, 3) and a copy of
  `environment/all` with the preference on (23, 55, 2, 5).
- [ ] 3. The guide `documentation/package/kernel/performance.md` (G-1 … G-3), with its
  guide check by an independent auditor.
  - [x] The guide, on the model of the fault guide. The section of `cell.md` moved to
    it, and `cell.md`, `architecture.md` and the package index point to it. The
    survey finds no export that the guide does not name. The words "refuses" and
    "knows" left the guide and the layer.
- [ ] 4. L02-1 as decided.
  - [x] **The owner, 2026-10-12: "use Preferences.jl and fix it with that"** (A), after
    the lead counted its users: 263 packages of General depend on it directly, and
    every process that loads the platform loads it through PrecompileTools. The
    switch is the preference `performance_counters` of `ProjecturedKernel`, read with
    `@load_preference` at compile time and typed `Bool`. The kernel has its first
    dependency, Preferences, with `[compat]` "1"; `package-rules.md` and the law
    (PAR-PROFILE-WITH-COUNTERS) say so. Julia names a compiled image with a hash of
    the preferences (`compilecache_path`, `prefs_blob`), so the image with the
    counters and the one without them both stay. Eleven environments that list the
    kernel were resolved: here `environment/all`, `environment/readme-data-frame` and
    four test packages, in omnet-julia `environment/all` and two test packages, in
    inet-julia `environment/all` and one test package. Checked: the default build
    reads `false`, and the package graph test passes 398 of 398; a copy of
    `environment/all` with the preference on reads `true`, and the counted tests pass
    (`test_performance_counter` 17, `test_editor_frame_performance` 5).
- [ ] 5. The tests, the guards, a second audit, and the seal on the owner's word.
