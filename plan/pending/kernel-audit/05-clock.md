# Layer 05 — clock (`source/kernel/clock/`)

Commit 15b40434, 2026-09-27. Seal state: all sealed.

## Verdict

The clock layer is small, and its state is per instance: each `Editor` and each `PrinterContext` holds its own `Clock`, and the process shares no clock. The wall clock that the owner reified on 2026-09-25 works as its docstrings say, and its 49 tests pass. One medium risk remains. The heartbeat writes on a second task, and a write at a yield inside a computation can stop a transitive reader of the clock for good; the cause is the engine defect L03-2. The three low findings: the heartbeat measures with the system clock, which can step back; PAR-STORE-THEN-DRAIN has no line for the heartbeat; and no test shows that a heartbeat write reaches a reactive reader.

## Shape

- Purpose: the animation clock. A time in seconds in a reactive cell, a read that records a dependency, a read that records none, one write, and a heartbeat that writes real time for an owner with no frame loop.
- Files:

  | file | lines | seal | what it holds |
  | --- | ---: | --- | --- |
  | `ClockModule.jl` | 35 | 🔒 | module docstring, `using ..CellModule`, `using ..CellStructModule`, the export statement, the include |
  | `Clock.jl` | 180 | 🔒 | `Clock` (a `@cell_struct` with `time` and `heartbeat`), the two reads, `set_clock_time!`, `show`, `start_wall_clock!`, `stop_wall_clock!`, the heartbeat loop |

- Imports: `CellModule`, `CellStructModule`. Imported by: `ProjectionModule` (`PrinterContext.clock`) and `EditorModule` (`editor.clock`, one `set_clock_time!` in each frame, and `has_dependent_cells` on the time cell for the wait in `Feeds.jl`). Outside the kernel: `Video.jl`, `repl/record/driver.jl` and `RotatingVectorDocumentExample.jl`; in omnet-julia, `PacedClockLabel.jl` and two scripts.
- Public surface: 6 exported names. `get_clock_time` and `start_wall_clock!` have one user outside the layer, the rotating vector example. `stop_wall_clock!` has no user outside the test of the layer: that example never stops its clock, and the `WeakRef` ends the heartbeat.
- State: per instance. The field `heartbeat` holds the task of the heartbeat or `nothing`. No module-level mutable state; `_HEARTBEAT_INTERVAL` is a constant. The heartbeat runs on the thread of its starter, and the starter stays on that thread (tested).
- Tests: [ClockTest.jl](../../../test/kernel/clock/ClockTest.jl), one file, 49 assertions, all pass in the baseline run. They cover the two reads, the independence of two clocks, the write, `show`, the conversion to `Float64`, a time that is not a real number, start and stop, a second start and a second stop, a start that continues the time, a restart, the end of a heartbeat by the `WeakRef`, and the thread of the heartbeat. They do not cover a heartbeat write that reaches a computation (L05-4).

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 0 | 1 | 1 |
| Documentation | 0 | 0 | 1 |
| Tests | 0 | 0 | 1 |

## Findings

### L05-1 A heartbeat write at a yield inside a computation can stop a reader of the clock for good

- Category: Correctness · Severity: Medium · Confidence: Confirmed for the mechanism; Suspected for a real occurrence (it needs a computation that yields)
- Where: [Clock.jl:171](../../../source/kernel/clock/Clock.jl#L171) 🔒, [Clock.jl:120](../../../source/kernel/clock/Clock.jl#L120) 🔒
- Evidence: The heartbeat is a task on the thread of its owner. It calls `set_clock_time!` at each yield of the owner, also at a yield inside a computation. Let P read a computed cell Q, and let Q read the clock. When P yields, the write marks Q invalid, and the walk stops at P, because P computes. P returns and becomes valid, while Q stays invalid. Every later tick stops at Q, so P never computes again, and its animation stops with no error (L03-2). The rotating vector example has this shape: `sin_link` reads `dot.cy`, and `dot.cy` reads the clock ([RotatingVectorDocumentExample.jl:118](../../../example/platform/RotatingVectorDocumentExample.jl#L118)); its computations do not yield, so it shows the shape and not the failure. The docstring accepts that "a frame that yields can see two times" (Clock.jl:123-124). A reader that stops for good is a different result, and the docstring does not state it.
- Rule: PAR-MONOTONE-INVALIDATION (the engine breaks it under this write).
- Fix: The engine fix of L03-2. Until then, add one sentence to the docstring of `start_wall_clock!`: a computation that reads the clock must not yield.
- Reach: `ReactiveCell.jl` 🔒 (L03-2), `Clock.jl` 🔒 (the docstring).

### L05-2 The heartbeat measures with the system clock, which can step back

- Category: Correctness · Severity: Low · Confidence: Confirmed
- Where: [Clock.jl:138](../../../source/kernel/clock/Clock.jl#L138) 🔒, [Clock.jl:176](../../../source/kernel/clock/Clock.jl#L176) 🔒
- Evidence: `start = Base.time() - get_clock_time(clock)` and `set_clock_time!(clock, Base.time() - start)`. `Base.time()` gives the system time of day. A step of the system clock, by hand or by a time server, moves the animation time back or forward by the same amount. The docstring says "The time never goes back" ([Clock.jl:107](../../../source/kernel/clock/Clock.jl#L107)). `time_ns()` is monotonic.
- Rule: bug; PAR-HONEST-DOCS.
- Fix: Take `start` and each tick from `time_ns()`, converted to seconds.
- Reach: `Clock.jl` 🔒.

### L05-3 PAR-STORE-THEN-DRAIN has no line for the heartbeat, which writes a cell on a second task

- Category: Documentation · Severity: Low · Confidence: Confirmed
- Where: [architecture-invariants.md:243](../../../documentation/rule/architecture-invariants.md#L243)
- Evidence: The rule says that a producer on any task "never touches a cell" (line 248) and that "Only the editor task writes a document a running editor shows" (line 251). The heartbeat of a clock in a shown document, such as the rotating vector example, writes the time cell on its own task. The owner decided this design on 2026-09-25 (plan/done/clock-layer-audit.md), and PAR-PER-EDITOR-STATE names `start_wall_clock!`. The rule that the heartbeat departs from does not name it, and PAR-CITE-EXCEPTIONS-ONLY asks that an accepted exception is flagged where the rule is.
- Rule: PAR-STORE-THEN-DRAIN; PAR-CITE-EXCEPTIONS-ONLY.
- Fix: Add one sentence to PAR-STORE-THEN-DRAIN: the heartbeat of a wall clock is the accepted exception, on the thread of the task that reads the clock, with no yield inside a computation that reads it.
- Reach: `architecture-invariants.md`.

### L05-4 No test shows that a heartbeat write reaches a computation

- Category: Tests · Severity: Low · Confidence: Confirmed
- Where: [ClockTest.jl:109](../../../test/kernel/clock/ClockTest.jl#L109)
- Evidence: Every test set of the wall clock reads with `get_clock_time`, which records no dependency. No test reads `get_reactive_clock_time` in a computation while a heartbeat runs, which is the purpose of the heartbeat. The docstring of the test file names two properties ("the sample/subscribe split", "clock independence"), and the file has twelve test sets.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: Add a test set: start a heartbeat, read a computed cell of the clock, wait with a bound until `is_cell_up_to_date` is false, and read a larger value. Make the docstring of the file name what it tests.
- Reach: `ClockTest.jl`.

## Accepted before, not raised again

All from plan/done/clock-layer-audit.md, decided on 2026-09-25:

- The heartbeat writes a reactive cell from a second task on the thread of its owner (item 1, the reified wall clock), and "a frame that yields can see two times".
- The heartbeat writes on each tick while it runs, with no check for readers.
- The field `heartbeat` shows in the constructors, and its docstring says to leave it.
- "A clock must have one writer" is a rule that no code enforces.
- A read of the clock on another thread races with the heartbeat; the docstring says so.
- The guard for precompilation has no test, because a normal process can not run as a precompile process.
- The field takes a value of any type; the reads convert a real number and throw for another value.
- The widget switch snaps and does not slide (outside the layer).

## Checked and clean

- PAR-PER-EDITOR-STATE: the process shares no clock. `Editor` makes its own `Clock()`, and each default `PrinterContext` makes a still `Clock()`. The editor writes its clock once per frame on its own task.
- No module-level mutable state; a heartbeat that nobody stops ends when the collector frees its clock (tested).
- A start continues from the time that the clock holds, and a second start or a second stop does nothing (tested).
- The layering: the layer imports only the cell and struct layers; the guard gives 10 of 10 in the baseline.
- The export statement lists the names in the order of `Clock.jl`; the module docstring and the fragment header say what the fragment holds.
- PAR-NO-CONSUMER-DOCS: the prior audit removed the names of the editor and of documents; "so one process can run many editors at once" states a reason, which the rule allows.
- The naming: `get_`/`set_` for the reads and the write, `!` on `start_wall_clock!` and `stop_wall_clock!`, and a verb in each private name.
- `Base.show` is qualified, and it reads with `peek`, so a display records no dependency.
- No history comment, no line over 90 characters, no definition over three positional arguments.
- No sealed file changed after its seal (451acbe2, 2026-09-25).
- Baseline: `Clock` 49 pass, 0 fail, 0 error.
