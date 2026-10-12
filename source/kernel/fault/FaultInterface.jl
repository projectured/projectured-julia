# Fragment of `FaultModule` — the contract: the open seams that code above
# answers, and the predicate that says which exceptions a barrier must never
# catch. Nothing here carries a body; `FaultDefaults.jl` holds what each one
# answers on its own.

"""
    append_fault!(target, record)

Show `record` on `target`, whatever showing it means there. Answer `false` when
the target did not show it; any other answer says that it did.

Use it through [`drain_faults!`](@ref) rather than directly: the drain calls it
for each target, once for a new record and again each time the count of the
record reaches a power of ten, on the editor's own task. A target that holds
cells may therefore write them, which a reactive computation may not.

The kernel answers `false`, so the drain reports a record that a target of no
known type was given at the next tier. A package that owns a log document adds
the method for its own type, so this layer never names one.

# Example

    append_fault!(log, record)

See also [`attach_fault_target!`](@ref), which says where a record goes.
"""
function append_fault! end

"""
    play_fault_sound!(backend)

Make the sound that says a fault reached the last tier that can be noticed.

Use it through [`report_fault!`](@ref) rather than directly. It is the tier
below the console, for the case where nothing a person looks at can carry the
report.

The kernel answers with the BEL character on `stderr`. A backend package adds
its own method where it can do better.

# Example

    play_fault_sound!(backend)

See also [`report_fault!`](@ref), which is what calls it.
"""
function play_fault_sound! end

"""
    get_fault_store(target) -> FaultStore or nothing

The store that collects the faults of `target`, or `nothing` where it keeps none.

Use it where code holds a target only as `Any` and must record a fault for it.
A tool that throws while it acts on its target is such a fault. The code then
records it and does not name the type that holds the store.

The default is `nothing`. A type that holds a store adds a method for itself.

# Example

    record_fault!(get_fault_store(target), :tool; origin = name, exception, traceback)

See also [`record_fault!`](@ref), which records a fault in the store.
"""
function get_fault_store end

"""
    is_fault_exception(exception) -> Bool

Whether a catch-all arm may take `exception` as a fault, rather than let it
through.

Answer `false` for an exception that means the program is to stop or can not go
on: a request to quit, an interrupt, a stack that ran out, a heap that ran out.
Catching one of those turns a clean stop into a hang, or hides a state no
barrier can repair.

The default is `true`, except for an interrupt, a stack overflow and an
out-of-memory error. A layer above that owns a control-flow exception adds a
method for it.

# Example

    is_fault_exception(exception) || rethrow()

See also [`run_fault_barrier!`](@ref), one of the arms that ask it.
"""
function is_fault_exception end
