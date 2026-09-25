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
    projection is the identity and never sees a printer context. The gallery
    must build it on the editor task, so the implementation checks where it is
    built.
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
- [ ] 6. The reified wall clock: the `heartbeat` field, `start_wall_clock!` and
  `stop_wall_clock!`, no `get_wall_clock`, and the tests of start, stop, restart
  and the end by `WeakRef`.
- [ ] 7. The default constructors of `PrinterContext` take a still `Clock()`.
- [ ] 8. The rotating vector example starts its own wall clock, and the task that
  builds it is the editor task.
- [ ] 9. The widget switch snaps.
- [ ] 10. The invariant text and the guides: PAR-PER-EDITOR-STATE, `agent.md`,
  `system-anatomy.md`, `kernel/architecture.md` and `cell.md`.
- [ ] 11. Verification of items 1, 2 and 9.

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
