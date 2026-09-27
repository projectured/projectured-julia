# Layer 02 — performance (`source/kernel/performance/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed (3 of 3).

## Verdict

The performance layer is small and imports only `Base.ScopedValues`. No source file changed after the seal of 2026-09-24 (f5140f4b).
The counter store is per dynamic extent of one frame, and the frame measurement store is per editor. Both are correct for PAR-PER-EDITOR-STATE.
The most important finding is the compile-time switch. The layer reads it from an environment variable at precompile time, and the package cache does not track that variable. So a person who follows PAR-PROFILE-WITH-COUNTERS can get no counters with no message, or can keep the instrumentation in later sessions.
No default test runs the counted branch.
`record_frame_measurements!` changes the store before it rejects a name that is in both groups. That breaks its own comment and a decision of the owner, and `PerformanceCounter.jl` allows such a name.
No finding is High, and no open plan covers a finding except the export block.

## Shape

- Purpose: what the editor measures about itself. The counters of the reactive engine and the stage times exist only when the switch compiles them in, and each frame binds a fresh store for them. The ring of frame measurements belongs to one editor.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `PerformanceModule.jl` | 31 | 🔒 | module head: docstring, 2 export statements, 2 includes |
  | `PerformanceCounter.jl` | 109 | 🔒 | the switch, the scoped counter store, `with_performance_counters`, `get_performance_counters`, `@count_performance`, `@measure_performance_time` |
  | `FrameMeasurement.jl` | 259 | 🔒 | `FrameMeasurementStore` (a ring of 1000 frames), `FrameMeasurementSummary`, the CSV writer |

- Imports: `Base.ScopedValues: ScopedValue, with`; nothing from the kernel. Imported by: `CellModule` (layer 3, `@count_performance` in `ReactiveCell.jl`) and `EditorModule` (layer 22). Outside the kernel: `FrameStatisticsModule` (`ProjecturedStatistics`).
- Public surface: 13 exported names. 5 have a user in code outside the kernel: `FrameMeasurementStore`, `get_frame_count`, `get_frame_measurement_names`, `compute_frame_measurement_summary`, `collect_recent_frame_measurements` (all in `source/statistics/`). `with_performance_counters` and `get_performance_counters` have a user outside the kernel only in a test (`PrinterLocalityTest.jl`). 4 have users only in the kernel: `PERFORMANCE_COUNTERS_ENABLED`, `@count_performance`, `@measure_performance_time`, `record_frame_measurements!`. 2 have no user in code: `FrameMeasurementSummary` (the return type of the summary) and `write_frame_measurements!` (a REPL call that `editor.md` documents). `omnet-julia` and `inet-julia` use no name of this layer.
- State: `_counters` is a global `ScopedValue` whose value is `nothing` outside a scope. `run_editor!` binds a fresh store for each frame ([EditorLoop.jl:175](../../../source/kernel/editor/EditorLoop.jl#L175)). Each editor runs its loop on its own task, so two editors never share a store. `Editor` makes one `FrameMeasurementStore` ([Editor.jl:94](../../../source/kernel/editor/Editor.jl#L94)), and only its task writes it and reads it (the statistics feed drains on the editor task). The counter store has no lock, and a task started inside a frame inherits it. A threaded cell read inside a frame would race on its dictionaries, but the cell engine is not thread-safe either, so the counters add no new hazard. No such read exists today (`MeaningSearch.jl` starts threaded tasks that read no cell). The growth has a limit: one column of `capacity` values for each distinct measurement name, and the names come from code.
- Tests: `test/kernel/performance/`, 2 files. The baseline gives 3 passes for `PerformanceCounter` (the compiled-out branch only) and 32 for the frame measurement store. The tests cover the ring, the summary, the units, the CSV text and a unit clash between two calls. No test covers the counted branch, a name in both groups of one call, `capacity < 1` or the file form of `write_frame_measurements!`.

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 2 | 0 |
| Architecture | 0 | 0 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 0 | 2 |
| Tests | 0 | 1 | 1 |
| **Total** | **0** | **3** | **5** |

## Findings

### L02-1 The counter switch comes from an environment variable that the package cache does not track

- Category: Correctness · Severity: Medium · Confidence: Confirmed (by the cache rules of Julia; the plan that last changed the file had to use `--compiled-modules=no`)
- Where: [PerformanceCounter.jl:19-23](../../../source/kernel/performance/PerformanceCounter.jl#L19) 🔒
- Evidence:

  ```julia
  const PERFORMANCE_COUNTERS_ENABLED =
      get(ENV, "PROJECTURED_PERFORMANCE_COUNTERS", "false") == "true"
  ```

  The constant goes into the package image of `ProjecturedKernel`. Julia does not rebuild an image when an environment variable changes. The effect goes both ways. A person who sets the variable and starts Julia loads the old image and gets no counters and no message. `perf!` returns at once ([EditorLoop.jl:13](../../../source/kernel/editor/EditorLoop.jl#L13)). An image that Julia built while the variable was `true` keeps the counters in every later session, until something else rebuilds the kernel. Then each cell read pays for a scoped lookup and two dictionary operations, and `perf!` logs every frame that applied an operation. The comment says "Set PROJECTURED_PERFORMANCE_COUNTERS=true and recompile", and `cell.md` says the same ([cell.md:287-292](../../../documentation/package/kernel/cell.md#L287)). No document says how to recompile. [performance-counter-units.md](../../../plan/done/performance-counter-units.md) ran the counted tests "with `PROJECTURED_PERFORMANCE_COUNTERS=true` and `--compiled-modules=no`, because the switch is fixed at precompile time".
- Rule: PAR-PROFILE-WITH-COUNTERS (a person must be able to profile an edit with the counters); PAR-HONEST-DOCS.
- Fix: read the switch as a compile-time preference, as the workload level of the leaf packages is read, because the package cache tracks a preference. The kernel has no dependency today, so the owner must choose between that and a documented rebuild step. The rebuild step would be `--compiled-modules=no`, or a delete of the kernel image, at the constant and in `cell.md`. In both cases, a message at load that names the state of the switch shows a stale image.
- Reach: `PerformanceCounter.jl` 🔒; possibly `package/ProjecturedKernel/Project.toml`; `cell.md`, `editor.md`.

### L02-2 record_frame_measurements! changes the store before it rejects a name in both groups

- Category: Correctness · Severity: Medium · Confidence: Confirmed
- Where: [FrameMeasurement.jl:85-98](../../../source/kernel/performance/FrameMeasurement.jl#L85) 🔒, [FrameMeasurement.jl:100-109](../../../source/kernel/performance/FrameMeasurement.jl#L100) 🔒, [FrameMeasurement.jl:120-123](../../../source/kernel/performance/FrameMeasurement.jl#L120) 🔒
- Evidence: the comment says "The check runs before the frame changes the store, so a wrong call leaves the store as it was". The owner decided the same ([frame-sample-api.md:75-77](../../../plan/done/frame-sample-api.md#L75)). But `_check_frame_units` compares a name only with the units that the store already knows (`get(store.units, name, unit)`). A new name in both `times` and `counts` of one call passes both checks. Then `frame_count` grows, the call clears the slot and makes the column with the unit `:second`, and line 122 throws "in both groups". Line 96 never writes `end_times[slot]`, so the ring holds a frame with an old end time, or `NaN`. The call also writes no count that comes after that name. Scenario: `PerformanceCounter.jl` keeps counts and times in two dictionaries, so one key can be in both, for example `@count_performance :print_time` beside `@measure_performance_time :print_time`. `record_frame_performance!` ([Feeds.jl:53-68](../../../source/kernel/editor/Feeds.jl#L53)) forwards both groups. The first frame leaves a broken slot, and each later frame throws in the `:report` barrier (or ends a strict run).
- Rule: bug; the decision of the owner in plan/done/frame-sample-api.md.
- Fix: in `record_frame_measurements!`, check before any change that no name of `times` is also a name of `counts`. Add the case to the test.
- Reach: `FrameMeasurement.jl` 🔒, `FrameMeasurementTest.jl`.

### L02-3 No default test runs the counted branch of the counters

- Category: Tests · Severity: Medium · Confidence: Confirmed
- Where: [PerformanceCounterTest.jl:18-30](../../../test/kernel/performance/PerformanceCounterTest.jl#L18), [FrameMeasurementTest.jl:140-153](../../../test/kernel/performance/FrameMeasurementTest.jl#L140)
- Evidence: both tests take the counted branch only when `PERFORMANCE_COUNTERS_ENABLED` is true, and the default image has it false (L02-1). The baseline shows 3 passes for `PerformanceCounter`, which is the compiled-out branch. So `_bump_count!`, `_bump_time!`, the scoped store, the compiled-in form of both macros and the forward of the counts to the frame store run in no default suite. A defect there shows only when a person profiles.
- Rule: PAR-NEW-CODE-SHIPS-TESTS; PAR-PROFILE-WITH-COUNTERS.
- Fix: test the store with no switch. Call `PerformanceModule._bump_count!` and `_bump_time!` inside `Base.ScopedValues.with(PerformanceModule._counters => PerformanceModule._make_performance_counter_store())`, and read `get_performance_counters()`. Alternatively, run the counted test in a child process with the variable set and `--compiled-modules=no`.
- Reach: tests only.

### L02-4 The export block of PerformanceModule does not follow the order of the fragments

- Category: Architecture · Severity: Low · Confidence: Confirmed
- Where: [PerformanceModule.jl:21-26](../../../source/kernel/performance/PerformanceModule.jl#L21) 🔒
- Evidence: the first statement lists `get_performance_counters` after the two macros. `PerformanceCounter.jl` defines it before them (line 78, against lines 90 and 101). The second statement lists `FrameMeasurementStore` before `FrameMeasurementSummary`, and `get_frame_count` and `get_frame_measurement_names` before `compute_frame_measurement_summary`. That is against the order of definition at lines 18, 50, 85, 134, 166 and 175. [exports.jl:62](../../../test/suite/exports.jl#L62) lists the file in `EXPORT_UNMIGRATED`.
- Rule: code-quality-rules.md §1 (the export block).
- Fix: list each statement in the order of definition.
- Reach: `PerformanceModule.jl` 🔒, `test/suite/exports.jl`.
- Planned: plan/pending/export-block-rule.md (line 83: 2 violations, sealed).

### L02-5 with_performance_counters uses the with_ form that the naming rules keep for a derived copy

- Category: Naming · Severity: Low · Confidence: Confirmed
- Where: [PerformanceCounter.jl:62](../../../source/kernel/performance/PerformanceCounter.jl#L62) 🔒
- Evidence: naming-rules.md says "Derived copies are `with_<stem>`: … return a copy with one aspect changed" (`with_property`, `with_selection`, and `with_clock` of `PrinterContext`). `with_performance_counters(f)` makes no copy. It binds a scope and runs `f`. The fault plan rejected `with_fault_barrier` for this reason: "The naming law reserves `with_<stem>` for a derived copy … and this function runs a body" ([the-editor-survives-a-fault.md:810-813](../../../plan/done/the-editor-survives-a-fault.md#L810)). The two names now follow two rules.
- Rule: naming-rules.md (Functions, `with_<stem>`); PAR-NAMING-LAW.
- Fix: a verb-first name that the owner picks, for example `run_with_performance_counters`. Use `workspace/bin/julia-rename.jl`, then update the prose.
- Reach: `PerformanceCounter.jl` 🔒, `PerformanceModule.jl` 🔒, `editor/EditorLoop.jl`, 3 test files, `cell.md`, `editor.md`, `system-anatomy.md`, `architecture-invariants.md`, and the text of 3 plans in `plan/pending/`.

### L02-6 The law and the guides describe the counters inexactly

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [architecture-invariants.md:895-898](../../../documentation/rule/architecture-invariants.md#L895), [architecture-invariants.md:903-906](../../../documentation/rule/architecture-invariants.md#L903), [architecture-invariants.md:922-925](../../../documentation/rule/architecture-invariants.md#L922), [cell.md:298-300](../../../documentation/package/kernel/cell.md#L298), [architecture.md:163](../../../documentation/package/kernel/architecture.md#L163), [architecture.md:193-194](../../../documentation/package/kernel/architecture.md#L193)
- Evidence:
  - PAR-PER-EDITOR-STATE lists "per-frame performance counters" among the state that "must live on the `Editor` instance". Later in the same section it says that they are task-local. It also says so as history: "`PerformanceModule` was likewise migrated off its process-global `_perf` dict". The code keeps them per scope, not on the `Editor`.
  - PAR-PROFILE-WITH-COUNTERS says that the loop "resets and logs … each frame". `perf!` logs only when the switch compiled the counters in and the frame applied an operation ([EditorLoop.jl:12-26](../../../source/kernel/editor/EditorLoop.jl#L12)). The rule does not name the switch at all (L02-1).
  - `cell.md` says that the loop "reports it every frame", and its link for `run_editor!` points at `EditorModule.jl`, but the function is in `EditorLoop.jl`.
  - The folder row of `architecture.md` names only the counters, not the frame measurement store. Line 193 calls `PerformanceModule` "a new sub-module added within a layer", but it is a layer of its own.
- Rule: PAR-HONEST-DOCS; writing-rules.md (the present state only).
- Fix: correct each text. Say that the counters live in the scope of one frame of one editor, and that the log needs the switch and an operation.
- Reach: `architecture-invariants.md`, `cell.md`, `architecture.md`. No sealed file.

### L02-7 Most exported names have no "Use it to" paragraph, and the counter fragment opens with 17 lines of comment

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [PerformanceCounter.jl:1-17](../../../source/kernel/performance/PerformanceCounter.jl#L1) 🔒, [PerformanceCounter.jl:54-108](../../../source/kernel/performance/PerformanceCounter.jl#L54) 🔒, [FrameMeasurement.jl:7-175](../../../source/kernel/performance/FrameMeasurement.jl#L7) 🔒
- Evidence: code-quality-rules.md §1 gives a declared name four parts: the first sentence, "Use it to", an example and "See also". Only `collect_recent_frame_measurements` and `write_frame_measurements!` have them all. `with_performance_counters`, `get_performance_counters`, `@count_performance`, `@measure_performance_time`, `record_frame_measurements!`, `compute_frame_measurement_summary`, `get_frame_count`, `get_frame_measurement_names` and `FrameMeasurementSummary` have no "Use it to" and no example. A model that searches for "profile an edit" or "how slow are the frames" therefore does not find them. The same section asks a fragment to open with a one-line comment. `PerformanceCounter.jl` opens with 17 lines, and lines 11-17 repeat the module docstring and the docstring of `with_performance_counters`.
- Rule: code-quality-rules.md §1 (a declared name documents its use; the fragment header); PAR-TIGHT-COMMENTS.
- Fix: add "Use it to" and an example to the names that a person or a model calls to profile. Cut the header to its first line and to the switch.
- Reach: `PerformanceCounter.jl` 🔒, `FrameMeasurement.jl` 🔒.

### L02-8 The frame measurement test file holds two editor tests and imports a name that the editor does not export

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: [FrameMeasurementTest.jl:8-14](../../../test/kernel/performance/FrameMeasurementTest.jl#L8), [FrameMeasurementTest.jl:129-153](../../../test/kernel/performance/FrameMeasurementTest.jl#L129)
- Evidence: the file loads `ProjectionModule`, `IoMapModule`, `DocumentModule`, `DeviceModule`, `EditorModule` and `ProjecturedKernelExample`, and defines a document and a projection. The two last test sets test `record_frame_performance!` of `editor/Feeds.jl`. `EditorModule` does not export that name ([EditorModule.jl:32-38](../../../source/kernel/editor/EditorModule.jl#L32)), and line 13 imports it by name.
- Rule: naming-rules.md ("A test is named for the file it tests"); PAR-MODULE-BOUNDARY-IS-API (an import names only exported symbols).
- Fix: move the two test sets to `test/kernel/editor/`. Export `record_frame_performance!`, or test it through `run_frame!`.
- Reach: tests; `editor/EditorModule.jl` if `EditorModule` exports the name.

## Accepted before, not raised again

- Counts and times are kept apart, `record_performance!` is gone, and the macro that measures a time is `@measure_performance_time` (plan/done/performance-counter-units.md, owner decisions of 2026-09-24).
- The counter store is task-local, not a field of `Editor` (plan/done/per-editor-animation-clock.md, and the text of PAR-PER-EDITOR-STATE). L02-6 raises only the inexact text.
- The producer gives the unit, the summary is one immutable answer, and the ring holds 1000 frames (plan/done/frame-sample-api.md). The names say "measurement", not "sample" (702e7ba1).
- The default build compiles the counters out. L02-1 raises only the stale cache, not the default.

## Checked and clean

- Seal: no source file of `source/kernel/performance/` changed after f5140f4b. After the seal, only `PerformanceCounterTest.jl` changed, in the rename of `Computed` to `@computation` (e2f84938, e6761f70, c3220fd3).
- PAR-PER-EDITOR-STATE: one counter store for each frame scope, and one frame store for each editor. No code fills a module-level dictionary or counter at run time.
- PAR-NO-PROJECTION-GLOBALS: the only global, `_counters`, is a `ScopedValue` that holds nothing outside a scope.
- PAR-PROFILE-WITH-COUNTERS: with the switch compiled in, the loop binds a fresh store each frame, logs it, and forwards every key to the frame store.
- Macro hygiene: `_bump_count!`, `_bump_time!` and `time_ns` are not escaped, so they resolve in `PerformanceModule` at every call site. With the switch off, `@count_performance` does not evaluate its key.
- 1-based ring: `_get_frame_slot` uses `mod1`, and the window `max(1, n - capacity + 1):n` holds exactly the last `capacity` frames (tested). The summary uses Welford's method with the sample deviation (`count - 1`), which is correct.
- Types: every dictionary and vector of both stores has a concrete type, and the scoped value has the small union `Union{Nothing, _PerformanceCounterStore}`.
- PAR-MODULE-DOCSTRING: the module file opens with a docstring, and each fragment opens with a comment that names `PerformanceModule`.
- History comments and rule citations: none.
- Code-quality §4 and §5: no definition takes more than three positional arguments, every file is under 500 lines, and no line is over 90 characters.
- Layer order: the layer imports nothing from the kernel, so the cell layer can count.
