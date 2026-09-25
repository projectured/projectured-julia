# The audit of the clock layer

The owner asked for a review of the whole shape of the clock layer
(`source/kernel/clock/`) and an audit against the rules in
`documentation/rule/`. The audit found one hazard, two reads that infer `Any`,
docstrings that do not match the code, history, names of higher layers in
docstrings, text that breaks the writing rules, and a wall clock without tests.
On 2026-09-25 the owner approved items 2 to 10 and gave permission to unseal
`ClockModule.jl` and `Clock.jl`. After a discussion on the same day, the owner
decided items 1, 2 and 9: the wall clock becomes an instance that its owner starts
and stops.

## Items

1. The heartbeat writes the wall clock, a reactive cell, from a background task
   that is sticky to the thread of the first caller. It breaks
   PAR-STORE-THEN-DRAIN. For discussion.
2. The heartbeat runs in every process that builds a `PrinterContext` without a
   clock, and it never stops. Part of the design of item 1.
3. `get_reactive_clock_time` and `get_clock_time` infer `Any`, and their
   docstrings say `Float64`.
4. The module docstring says that the heartbeat starts at module load and writes
   `Base.time()`. It starts at the first `get_wall_clock()` and writes the
   seconds since then. The invariant text says "reflecting OS time".
5. "Nothing else ever writes" the wall clock is a convention, not a guarantee.
6. History in `Clock.jl`, and a comment after the function that it describes.
7. Names of higher layers in the docstrings: the editor, `Document`, renders,
   navigation.
8. The writing rules: bullets, capitals, "thunk", a contraction, informal
   phrases, "It wants", a header of 135 characters, and no "Use it to" paragraph
   or example.
9. `get_wall_clock()` starts a task but has no `!`. Part of the design of item 1.
10. No test of the wall clock, of the conversion to `Float64`, or of a field that
    holds another type.

## Decisions

- **Items 2 and 9 go with item 1.** Both are about who writes the wall clock and
  when, which is the question of item 1.
- **The wall clock is reified (items 1, 2 and 9, decided on 2026-09-25).** No
  clock is shared by the whole process. `get_wall_clock` and `_WALL_CLOCK` go,
  and with them the exception for the wall clock in PAR-PER-EDITOR-STATE.
  - `start_wall_clock!(clock) -> clock` starts a heartbeat on the caller's task.
    The heartbeat writes the seconds since the start every 10 ms. A second start
    does nothing, so `clock = start_wall_clock!(Clock())` is the usual form.
  - `stop_wall_clock!(clock)` ends the heartbeat. A second stop does nothing.
  - `@async` pins the caller and the heartbeat to one thread, so they never run
    at the same moment. A probe showed it: a task on thread 3 became sticky, and
    its heartbeat ran on thread 3. So the owner must start the clock on the task
    that reads it, and the docstring says so.
  - The heartbeat holds only a `WeakRef` to its clock, so a clock that nobody
    stops ends its task when the collector frees it.
  - `Clock` gets a second field, `heartbeat`, a `MutableCell` that holds the
    task or `nothing`. A table in the module would be process-global state
    again. The field also shows in the keyword constructor, and its docstring
    says to leave it.
  - The guard for precompilation stays in `start_wall_clock!`.
  - The writes come at the owner's yield points, not between frames. An owner
    with a frame loop writes its clock once per frame instead, as the editor
    does for `editor.clock`. The heartbeat is for an owner without a loop.
- **The callers of `get_wall_clock`.**
  - The three default constructors of `PrinterContext` take a still `Clock()`.
    The editor replaces the default with `editor.clock` at once
    (`with_clock(PrinterContext(), editor.clock)`).
  - The rotating vector example starts its own wall clock, because its
    projection is the identity and never sees a printer context. It stays a
    `GraphicsCanvas`: the owner wants the example to stay in the graphics domain.
- **An example builds its document at first use (decided on 2026-09-25).** The
  inner constructor of `Example` called `make_document()` and `make_projection()`,
  and the examples are `const`s, so every document was built while its package
  precompiled and was frozen into the package image. No task can start then, so
  the rotating vector's clock would stand still in the gallery, which shows the
  cached instance. `Example` now builds `document` and `projection` at their first
  read, on the task that reads them, and keeps them. The owner had wanted to solve
  this in any case.
- **The heartbeat writes on every tick while it runs.** A heartbeat that skips its
  writes while no computation reads the clock gives wrong reads: a sample read
  never subscribes, so it gets an old time, and a new computation reads an old
  time for one tick (the owner found this). A clock moves only while an owner
  keeps it started: the owner stops it, or the `WeakRef` ends it with the clock.
  - The widget switch snaps to its new position and does not slide (the owner
    chose this over a clock owned by the switch projection). Its reader has no
    context that reaches its editor's clock, so it can not take a start time on
    that clock. The fields `duration`, `anim_from` and `anim_t0` stay, so the
    slide can come back without a change of the schema, and the docstring says
    that the switch snaps.
- **Follow-up, not in this plan.** A reader needs a context, as a printer has
  `PrinterContext`, so that it can reach its editor's clock. The owner thinks the
  intent can carry it, but that is not decided. With that context, the switch can
  slide again on its editor's clock.
- **A read narrows to `Float64`.** The field of a `@cell_struct` is a `Cell` of
  any value, so the read asserts the type: `clock.time::Float64`. A field that
  holds another type throws a `TypeError` at the read.

## Steps

- [x] 1. Unseal `ClockModule.jl` and `Clock.jl`, and add this plan.
- [x] 2. Items 3 to 8: the reads, the docstrings, the comments and the text.
- [x] 3. Item 10: the tests.
- [x] 4. The invariant text of item 4.
- [x] 5. Verification of items 3 to 8 and 10.
- [x] 6. The reified wall clock: the `heartbeat` field, `start_wall_clock!` and
  `stop_wall_clock!`, no `get_wall_clock`, and the tests of start, stop, restart
  and the end by `WeakRef`.
- [x] 7. The default constructors of `PrinterContext` take a still `Clock()`.
- [x] 8. `Example` builds its document and its projection at first use, and the
  rotating vector example starts its own wall clock.
- [x] 9. The widget switch snaps. Its slide helpers and its import of the clock
  module go, because nothing else uses them.
- [x] 10. The invariant text and the guides: PAR-PER-EDITOR-STATE, `agent.md`,
  `system-anatomy.md`, `kernel/architecture.md` and `cell.md`.
- [x] 11. Verification of items 1, 2 and 9.

## The re-audit before the seal

On 2026-09-25 the owner asked for a second review of the whole layer before the
seal. It found four points, and the owner approved the fixes:

- [x] A start set the time back: a clock at 100.0 went to 0.22, and a restart went
  from 0.29 to 0.09. The heartbeat now continues from the time that the clock
  holds, so a stop and a later start act as a pause and a resume.
- [x] `Clock(0)` must work. `Clock(time::Real)` converts to `Float64`, and the two
  reads convert any real number, with no call for a `Float64`. The keyword
  constructor, which `@cell_struct` makes, stores the value as it is, so only the
  reads cover every way to make a clock. A time that is not a real number throws
  a `MethodError` at the read.
- [x] `stop_wall_clock!` names the task to call it on.
- [x] The module docstring says "A clock must have one writer", a rule that no code
  enforces.

After the fixes: `test_kernel()` 2253 pass and the six known failures, `Clock` 49
assertions, the export and naming guards 0 violations, and the rotating vector
still moves.

## What the implementation found

- `show` must not narrow: a clock that holds another type must still show, so
  the display reads the cell without the type assertion.
- No code writes the field of a clock directly; every writer calls
  `set_clock_time!`, and `Feeds.jl` only asks whether the time cell has readers.

## Verification

- `test_kernel()`: 2232 pass, and the six known failures (five of Rule C, one of
  `MEvalBranch`). `Clock` has 28 assertions: `@inferred` reads, the `TypeError`
  of a time that is not a `Float64`, one wall clock, a heartbeat that moves it,
  and a heartbeat that starts again after its task ends.
- `test_substrate()`: 80862 pass, and the five known failures of the split pane
  drag test.
- The export and naming guards: 0 violations.
- The guard for precompilation has no test: a normal process can not run as a
  precompile process.

Items 1, 2 and 9:

- `test_kernel()`: 2243 pass, and the six known failures. `Clock` has 39
  assertions: start and stop, a second start and a second stop, a restart, the end
  of a heartbeat whose clock is freed, and a heartbeat on the thread of its
  starter.
- `test_substrate()`: 80862 pass, and the five known failures of the split pane
  drag test, as before the change.
- `test_printers()`: 194900 pass. The naming, export and documentation guards
  pass; the argument guard reports only the known `start_application!`.
- The rotating vector example: after the package loads, its document does not
  exist; the first read builds it in 0.263 s, compilation included (one run, not
  a measurement); a second read gives the same instance; the dot moves from
  (280, 177) to (274, 206) in half a second.
- omnet-julia, against the worktree: every package precompiles, and
  `test_presentation()` gives 1694 pass, 12 fail, 2 error and 1 broken, with the
  same failing tests as the run of `test_omnet()` with the old wall clock.
  omnet-julia's own environment does not load on `main`, because its manifest
  does not know that `ProjecturedFileSystem` now depends on `ProjecturedFocus`.

