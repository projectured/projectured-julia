# The walkthrough of the fault layer.

const _FAULT_WALKTHROUGH = [
    "# A store holds the faults that the barriers catch. An editor has one.",
    "store = FaultStore(capacity = 2); get_fault_records(store)",
    "# A policy says whether a barrier catches, and where a report goes. This one catches and is quiet.",
    "policy = FaultPolicy(is_console_enabled = false, is_sound_enabled = false); policy.is_barrier_enabled",
    "# A barrier runs one stage of work. A body that works answers its own value.",
    "guard(body) = run_fault_barrier!(body, store; policy, backend = nothing, site = :print, origin = :Printer, fallback = :blank)",
    "guard(() -> 6 * 7)",
    "# A body that throws answers the fallback, and the store records the fault.",
    "guard(() -> error(\"no such node\"))",
    "record = only(get_fault_records(store)); (record.site, record.origin, record.exception_type, record.message)",
    "# The same fault again takes a count, not a second record. The key is the site, the origin and the type of the exception.",
    "guard(() -> error(\"no node at 7\")); only(get_fault_records(store)).count",
    "# The barrier counts the faults in a row on its site. A body that works sets the count to zero.",
    "get_consecutive_fault_count(store, :print)",
    "guard(() -> 1); get_consecutive_fault_count(store, :print)",
    "# Code that must answer by the fault catches in place, and records the fault itself.",
    "record_fault!(store, :read; origin = :Reader, exception = BoundsError([1], 4)).count",
    "# Once per frame the drain hands each new record to the targets of the store, and reports it. Then nothing is new.",
    "[record.origin for record in drain_faults!(store; policy)]",
    "isempty(drain_faults!(store; policy))",
    "# report_fault! reports one record at the first tier that works. The console and the sound are closed here.",
    "report_fault!(store, record; policy, backend = nothing)",
    "# A record that a target of the store took is shown already, so the console stays quiet for it.",
    "report_fault!(store, record; policy, backend = nothing, is_shown = true)",
    "# A full store forgets the oldest record that the drain handed over, so a new fault has room.",
    "record_fault!(store, :device; origin = :Screen, exception = ErrorException(\"gone\")); [record.origin for record in get_fault_records(store)]",
    "record_fault!(store, :tool; origin = :Search, exception = ErrorException(\"lost\")); [record.origin for record in get_fault_records(store)]",
    "# Now every record waits for the drain. A new fault answers nothing, and one overflow record counts it.",
    "record_fault!(store, :tool; origin = :Index, exception = ErrorException(\"lost\")) === nothing",
    "overflow = last(get_fault_records(store)); (overflow.origin, overflow.count)",
    "# An exception that means stop passes every barrier.",
    "is_passthrough_exception(InterruptException()), is_passthrough_exception(ErrorException(\"x\"))",
    "# A strict policy catches nothing, so a test sees the exception.",
    "try run_fault_barrier!(() -> error(\"no such node\"), store; policy = make_strict_fault_policy(), backend = nothing, site = :print) catch exception; exception end",
]

"""
    print_fault_example(io::IO = stdout)

Print a REPL session that shows the fault layer: a store and a quiet policy, a
barrier that answers a value and then its fallback, the count of one fault, the
count of the faults in a row, the drain, `report_fault!`, a full store that makes
room and then counts into its overflow record, and a strict policy that catches
nothing.

Each line runs as it prints, so the value under a line is the value that the line
gives. To try the lines, type them in a REPL after `using ProjecturedKernel.FaultModule`.
The console and the sound are closed in the policy, because they write to the
global logger and to the terminal, and not to `io`.

# Example

    julia> using ProjecturedKernelExample

    julia> print_fault_example()

See also [`print_cell_example`](@ref).
"""
print_fault_example(io::IO = stdout) = _print_walkthrough(io, FaultModule, _FAULT_WALKTHROUGH)
