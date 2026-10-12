"""
The walkthrough of the fault layer: the REPL session that `print_fault_example`
prints, line for line.
"""

using Test
using ProjecturedKernelExample: print_fault_example

const _FAULT_EXAMPLE_TEXT = """
# Type each line in a REPL after `using ProjecturedKernel.FaultModule`.

# A store holds the faults that the barriers catch. An editor has one.
julia> store = FaultStore(capacity = 2); get_fault_records(store)
FaultRecord[]

# A policy says whether a barrier catches, and where a report goes. This one catches and is quiet.
julia> policy = FaultPolicy(is_console_enabled = false, is_sound_enabled = false); policy.is_barrier_enabled
true

# A barrier runs one stage of work. A body that works answers its own value.
julia> guard(body) = run_fault_barrier!(body, store; policy, backend = nothing, site = :print, origin = :Printer, fallback = :blank)
guard (generic function with 1 method)

julia> guard(() -> 6 * 7)
42

# A body that throws answers the fallback, and the store records the fault.
julia> guard(() -> error("no such node"))
:blank

julia> record = only(get_fault_records(store)); (record.site, record.origin, record.exception_type, record.message)
(:print, :Printer, :ErrorException, "no such node")

# The same fault again takes a count, not a second record. The key is the site, the origin and the type of the exception.
julia> guard(() -> error("no node at 7")); only(get_fault_records(store)).count
2

# The barrier counts the faults in a row on its site. A body that works sets the count to zero.
julia> get_consecutive_fault_count(store, :print)
2

julia> guard(() -> 1); get_consecutive_fault_count(store, :print)
0

# Code that must answer by the fault catches in place, and records the fault itself.
julia> record_fault!(store, :read; origin = :Reader, exception = BoundsError([1], 4)).count
1

# Once per frame the drain hands each new record to the targets of the store, and reports it. Then nothing is new.
julia> [record.origin for record in drain_faults!(store; policy)]
2-element Vector{Symbol}:
 :Printer
 :Reader

julia> isempty(drain_faults!(store; policy))
true

# A full store forgets the oldest record that the drain handed over, so a new fault has room.
julia> record_fault!(store, :device; origin = :Screen, exception = ErrorException("gone")); [record.origin for record in get_fault_records(store)]
2-element Vector{Symbol}:
 :Reader
 :Screen

julia> record_fault!(store, :tool; origin = :Search, exception = ErrorException("lost")); [record.origin for record in get_fault_records(store)]
2-element Vector{Symbol}:
 :Screen
 :Search

# Now every record waits for the drain, so a new fault counts into one overflow record.
julia> overflow = record_fault!(store, :tool; origin = :Index, exception = ErrorException("lost")); (overflow.origin, overflow.count)
(:FaultStore, 1)

# An exception that means stop passes every barrier.
julia> is_passthrough_exception(InterruptException()), is_passthrough_exception(ErrorException("x"))
(true, false)

# A strict policy catches nothing, so a test sees the exception.
julia> try run_fault_barrier!(() -> error("no such node"), store; policy = make_strict_fault_policy(), backend = nothing, site = :print) catch exception; exception end
ErrorException("no such node")

"""

function test_fault_example()
@testset "Fault example" begin
    @test sprint(print_fault_example) == _FAULT_EXAMPLE_TEXT
    # Each call runs in a new module, so a second call starts from no store.
    @test sprint(print_fault_example) == _FAULT_EXAMPLE_TEXT
end
end
