# The animation clock

> **Kind:** reference · **Status:** current · **Stands on:** [cell.md](cell.md), [struct.md](struct.md)

This guide says what a clock holds, how a computation reads it, who writes it and
when, and how a document that animates gets the clock of the editor that shows it.
The layer is the folder [source/kernel/clock/](../../../source/kernel/clock/), and
`ClockModule` is its one module. It uses the cell layer and the struct layer, and
nothing else.

## A clock

A `Clock` holds a time in seconds in a reactive cell. It is a `@cell_struct` with one
field, `time`, and not a document: it is state of an editor, which no person edits,
and no projection shows. Each clock is independent. A write to one clock moves only
the cells that read that clock, so one process can hold many clocks, and the process
has no clock that all share.

```julia
clock = Clock()                         # Clock(time = 0.0)
Clock(2)                                # Clock(time = 2)
Clock(time = 0.25)                      # Clock(time = 0.25)
```

The field takes a value of any type, and the two reads convert a real number to a
`Float64`. A time that is not a real number makes a read throw a `MethodError`.
`set_clock_time!` stores a `Float64`. The display shows the time as the constructor
takes it, and it records no dependency. The field holds a time: a clock made with a
computation drops it at the first write, and its display runs it.

## The two reads

A clock has two reads, for two uses:

- `get_reactive_clock_time(clock)` records the read, as `clock.time` does. A
  computation that reads the time this way computes again after each write of a new
  time. Use it in a computation that animates.
- `get_clock_time(clock)` records nothing. Use it to take the start time of an
  animation, so that the code that takes it does not run again at each write.

```julia
start = get_clock_time(clock)
elapsed = Cell(@computation get_reactive_clock_time(clock) - start)
set_clock_time!(clock, start + 1.5)
elapsed[]                               # 1.5
```

A write of the time that the clock holds changes nothing, as for any cell of plain
data: no reader computes again. `has_clock_readers(clock)` tells whether a cell reads
the clock with `get_reactive_clock_time` or `clock.time`.

## The one writer

A clock has one writer, the task that owns the cells that read it. The writer writes
the time with `set_clock_time!`, and then it reads the cells, so every read of one
read phase sees one time (`PAR-SINGLE-WRITER`). A computation never writes a clock,
and another task does not write it either: it posts its change to the owner, and the
owner applies it in its next write phase (`PAR-STORE-THEN-DRAIN`).

```julia
angle = Cell(@computation 90 * get_reactive_clock_time(clock))
origin = time_ns()                      # a monotonic time, which never steps back
for frame in 1:3
    set_clock_time!(clock, (time_ns() - origin) / 1e9)   # the write phase
    angle[]                                             # the read phase
end
```

## The clock of an editor

Each editor has a clock of its own, `editor.clock`. The loop of the editor writes it
at the start of each frame, before `drain_feeds!` and before it reads anything. The
time comes from `get_frame_clock_time(backend, wall_time)`: the time since the loop
started, from the monotonic `time_ns`, unless the backend keeps a time of its own. A
video recorder answers the time of the frame that it writes next, so an animation
moves one frame of time per frame, however long a frame takes to make.

The editor waits for input between frames. While `has_clock_readers(editor.clock)` is
true, it wakes at least each `FRAME_INTERVAL`, a thirtieth of a second, so that an
animation moves. While nothing reads the clock, it sleeps until the next input, the
next wake, the next timer, or the next deadline of a feed. It still writes the clock
in each frame, so a read that records nothing sees the current time.

A printer reads the clock of its editor from its context, `ctx.clock`.
`with_clock(ctx, clock)` gives a context with another clock. So a projection that
animates reads `get_reactive_clock_time(ctx.clock)` in a computation, and it moves
in each editor that shows it.

## A document that animates

A document that holds its own animation, a cell that reads a clock, must read the
clock of the editor that shows it. Give the document and the editor the same clock,
with the keyword `clock` of `make_editor`, `build_editor` and `run_editor!`:

```julia
clock = Clock()
run_editor!(make_rotating_vector_document(; clock), IdentityProjection(); clock)
```

A document built with a clock that no editor writes stands still at its first frame.
The rotating vector example builds such a document by default, for the example
registry. For a new editor, build the document again with the clock of that editor.

## Layer structure

```
cell/CellModule.jl                (CellModule): the cells
struct/CellStructModule.jl        (CellStructModule): @cell_struct, used by ↓
clock/ClockModule.jl              (ClockModule): the animation clock
        └─ Clock.jl           : Clock, the two reads, the write, and has_clock_readers
```

`Clock.jl` holds the struct, `get_reactive_clock_time`, `get_clock_time`,
`set_clock_time!`, `has_clock_readers` and the `show` method.

## Try it

`print_clock_example()` in `ProjecturedKernelExample` prints a REPL session with the
layer: a clock, a computation that follows each new time, a write of the same time, a
start time that records nothing, `has_clock_readers`, two independent clocks, the
display and the conversion of a time, and a loop that writes the time once in each
frame. Each line runs as it prints. Type the lines yourself after
`using ProjecturedKernel.ClockModule`.

```julia
using ProjecturedKernelExample
print_clock_example()
```

Public surface: `Clock`, `get_reactive_clock_time`, `get_clock_time`,
`set_clock_time!` and `has_clock_readers`.
