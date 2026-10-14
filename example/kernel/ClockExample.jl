# The walkthrough of the clock layer.

const _CLOCK_WALKTHROUGH = [
    "# The cells come from the cell layer.",
    "using ProjecturedKernel.CellModule",
    "# A clock holds a time in seconds. It starts at zero.",
    "clock = Clock()",
    "# get_reactive_clock_time records the read, so a computation that reads it follows each new time.",
    "angle = Cell(@computation 90 * get_reactive_clock_time(clock)); angle[]",
    "set_clock_time!(clock, 0.5); is_cell_valid(angle)",
    "angle[]",
    "# A write of the time that the clock holds changes nothing.",
    "set_clock_time!(clock, 0.5); is_cell_valid(angle)",
    "# get_clock_time records nothing. Take the start time of an animation with it.",
    "start = get_clock_time(clock); elapsed = Cell(@computation get_reactive_clock_time(clock) - start); elapsed[]",
    "set_clock_time!(clock, 2.0); elapsed[]",
    "sampled = Cell(@computation get_clock_time(clock)); sampled[]",
    "set_clock_time!(clock, 3.0); is_cell_valid(sampled)",
    "# has_clock_readers tells whether a cell reads the clock.",
    "has_clock_readers(clock), has_clock_readers(Clock())",
    "# Each clock is independent: a write to one moves no reader of another.",
    "other = Clock(); follower = Cell(@computation get_reactive_clock_time(other)); follower[]",
    "set_clock_time!(clock, 4.0); is_cell_valid(follower)",
    "# set_clock_time! writes a Float64. The display shows the time.",
    "set_clock_time!(clock, 1//2); clock",
    "# The field takes any value, and the reads convert a real number.",
    "clock.time = 3; get_clock_time(clock)",
    "clock.time = \"text\"; try get_clock_time(clock) catch exception; typeof(exception) end",
    "# The owner of the cells writes the time, and then reads them, once in each frame.",
    "[(set_clock_time!(clock, frame / 4); angle[]) for frame in 1:3]",
]

"""
    print_clock_example(io::IO = stdout)

Print a REPL session that shows the clock layer: a clock, a computation that
follows each new time, a write of the same time, a start time that records
nothing, the question whether a cell reads a clock, two independent clocks, the
display and the conversion of a time, and a loop that writes the time once in
each frame.

Each line runs as it prints, so the value under a line is the value that the line
gives. To try the lines, type them in a REPL after
`using ProjecturedKernel.ClockModule`.

# Example

    julia> using ProjecturedKernelExample

    julia> print_clock_example()

See also the guide `kernel/clock`.
"""
print_clock_example(io::IO = stdout) = _print_walkthrough(io, ClockModule, _CLOCK_WALKTHROUGH)
