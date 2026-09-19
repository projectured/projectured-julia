# Fragment of `FaultModule` — the contract: the two seams a package above
# answers, and the predicate that says which exceptions a barrier must never
# catch. Nothing here carries a body; `FaultDefaults.jl` holds what each one
# answers on its own.

"""
    append_fault!(target, record)

Show `record` on `target`, whatever showing it means there.

Use it through [`drain_faults!`](@ref) rather than directly: the drain calls it
once per new record, per target, on the editor's own task. A target that holds
cells may therefore write them, which a reactive thunk may not.

The kernel answers nothing. A package that owns a log document adds the method
for its own type, so this layer never names one.

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

The kernel answers with the BEL character on the stream the logger captured at
start. A backend package adds its own method where it can do better.

# Example

    play_fault_sound!(editor.backend)

See also [`report_fault!`](@ref), which is what calls it.
"""
function play_fault_sound! end

"""
    get_fault_store(target) -> FaultStore or nothing

The store that collects the faults of `target`, or `nothing` where it keeps none.

Use it where code holds something an editor owns but may not name the editor
itself. The kernel's agent layer is the case: it drives a tool against a target
it only knows as `Any`, and a tool that throws is a fault like any other.

The default is `nothing`. The editor layer answers it for `Editor`.

# Example

    record_fault!(get_fault_store(target), :tool, name, nothing, exception, traceback)

See also [`get_fault_policy`](@ref).
"""
function get_fault_store end

"""
    get_fault_policy(target) -> FaultPolicy

What `target` does with a fault. The default is the strict policy, so anything
that answers nothing of its own catches nothing of its own.
"""
function get_fault_policy end

"""
    is_passthrough_exception(exception) -> Bool

Whether a barrier must let `exception` through rather than catch it.

Answer `true` for an exception that means the program is to stop or can not go
on: a request to quit, an interrupt, a stack that ran out, a heap that ran out.
Catching one of those turns a clean stop into a hang, or hides a state no
barrier can repair.

The default is `false`. A layer above adds a method for the control-flow
exception it owns, exactly as it adds a `reroot_operation` method.

# Example

    is_passthrough_exception(exception) && rethrow()

See also [`run_fault_barrier`](@ref), which is what asks.
"""
function is_passthrough_exception end
