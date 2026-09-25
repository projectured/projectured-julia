# The audit of the clock layer

The owner asked for a review of the whole shape of the clock layer
(`source/kernel/clock/`) and an audit against the rules in
`documentation/rule/`. The audit found one hazard, two reads that infer `Any`,
docstrings that do not match the code, history, names of higher layers in
docstrings, text that breaks the writing rules, and a wall clock without tests.
On 2026-09-25 the owner approved items 2 to 10 and gave permission to unseal
`ClockModule.jl` and `Clock.jl`. Item 1 comes after, in a discussion.

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
- **A read narrows to `Float64`.** The field of a `@cell_struct` is a `Cell` of
  any value, so the read asserts the type: `clock.time::Float64`. A field that
  holds another type throws a `TypeError` at the read.

## Steps

- [x] 1. Unseal `ClockModule.jl` and `Clock.jl`, and add this plan.
- [ ] 2. Items 3 to 8: the reads, the docstrings, the comments and the text.
- [ ] 3. Item 10: the tests.
- [ ] 4. The invariant text of item 4.
- [ ] 5. Verification.

## Verification

To fill in.
