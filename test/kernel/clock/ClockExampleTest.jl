"""
The walkthrough of the clock layer: the REPL session that `print_clock_example`
prints, line for line.
"""

using Test
using ProjecturedKernelExample: print_clock_example

const _CLOCK_EXAMPLE_TEXT = """
# Type each line in a REPL after `using ProjecturedKernel.ClockModule`.

# The cells come from the cell layer.
julia> using ProjecturedKernel.CellModule

# A clock holds a time in seconds. It starts at zero.
julia> clock = Clock()
Clock(time = 0.0)

# get_reactive_clock_time records the read, so a computation that reads it follows each new time.
julia> angle = Cell(@computation 90 * get_reactive_clock_time(clock)); angle[]
0.0

julia> set_clock_time!(clock, 0.5); is_cell_valid(angle)
false

julia> angle[]
45.0

# A write of the time that the clock holds changes nothing.
julia> set_clock_time!(clock, 0.5); is_cell_valid(angle)
true

# get_clock_time records nothing. Take the start time of an animation with it.
julia> start = get_clock_time(clock); elapsed = Cell(@computation get_reactive_clock_time(clock) - start); elapsed[]
0.0

julia> set_clock_time!(clock, 2.0); elapsed[]
1.5

julia> sampled = Cell(@computation get_clock_time(clock)); sampled[]
2.0

julia> set_clock_time!(clock, 3.0); is_cell_valid(sampled)
true

# has_clock_readers tells whether a cell reads the clock.
julia> has_clock_readers(clock), has_clock_readers(Clock())
(true, false)

# Each clock is independent: a write to one moves no reader of another.
julia> other = Clock(); follower = Cell(@computation get_reactive_clock_time(other)); follower[]
0.0

julia> set_clock_time!(clock, 4.0); is_cell_valid(follower)
true

# set_clock_time! writes a Float64. The display shows the time.
julia> set_clock_time!(clock, 1//2); clock
Clock(time = 0.5)

# The field takes any value, and the reads convert a real number.
julia> clock.time = 3; get_clock_time(clock)
3.0

julia> clock.time = "text"; try get_clock_time(clock) catch exception; typeof(exception) end
MethodError

# The owner of the cells writes the time, and then reads them, once in each frame.
julia> [(set_clock_time!(clock, frame / 4); angle[]) for frame in 1:3]
3-element Vector{Float64}:
 22.5
 45.0
 67.5

"""

function test_clock_example()
@testset "Clock example" begin
    @test sprint(print_clock_example) == _CLOCK_EXAMPLE_TEXT
    # Each call runs in a new module, so a second call starts from a new clock.
    @test sprint(print_clock_example) == _CLOCK_EXAMPLE_TEXT
end
end
