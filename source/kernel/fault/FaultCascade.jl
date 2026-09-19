# Fragment of `FaultModule` — the report cascade. A fault is reported at the
# first tier that works, and a tier that fails falls to the next one.

# The tiers, in the order they are tried:
#
#   1  in the output document, where it failed   — the barrier projection, above
#   2  in the message log on the screen          — the store plus drain_faults!
#   3  on the console                            — here
#   4  a sound                                   — here
#   5  nothing                                   — here
#
# Tiers 1 and 2 are not in this file, because neither needs a fallback: putting
# a mark in the output is what the projection barrier already did, and putting a
# record in the store is what `record_fault!` already did. This function is what
# happens when a person can still be told and neither of those reaches one.

"""
    report_fault!(store, policy, backend, record) -> Symbol

Report `record` at the first tier that works, and answer the tier it reached:
`:console`, `:sound` or `:swallowed`.

**This function never throws.** It is the one function in the system with that
contract, because it is the last thing that runs when everything else failed —
including, sometimes, the thing that was meant to report. A test asserts it
against a store that throws, a target that throws and a backend that throws, all
at once.

A fault raised while a fault is reported does not recurse: the store carries a
depth, and a nested call goes straight to the console and stops.

The sound plays when the console tier failed, and also when the fault came from
a device, because a screen that draws nothing is exactly the case where a person
has nothing else to notice.

# Example

    report_fault!(editor.faults, editor.fault_policy, editor.backend, record)

See also [`run_fault_barrier`](@ref), which is what calls it.
"""
function report_fault!(store, policy::FaultPolicy, backend, record)
    try
        record === nothing && return :swallowed
        depth = _enter_fault_report!(store)
        try
            depth > 1 && return _report_on_console(policy, record) ? :console : :swallowed
            tier = _report_on_console(policy, record) ? :console : :swallowed
            wants_sound = policy.is_sound_enabled &&
                          (tier === :swallowed || record.site === :device)
            if wants_sound && _report_by_sound(backend)
                tier === :console || (tier = :sound)
            end
            return tier
        finally
            _leave_fault_report!(store)
        end
    catch
        # Tier 5. Nothing left to try, and nothing this function may raise.
        return :swallowed
    end
end

report_fault!(store, policy::FaultPolicy, backend, ::Nothing) = :swallowed

_enter_fault_report!(store::FaultStore) = (store.depth += 1; store.depth)
_enter_fault_report!(::Nothing) = 1

_leave_fault_report!(store::FaultStore) = (store.depth -= 1; nothing)
_leave_fault_report!(::Nothing) = nothing

# Tier 3. The logger, never a raw write: `execute_julia_code` redirects the
# global streams while it runs, and a raw write can land in a closed pipe.
function _report_on_console(policy::FaultPolicy, record::FaultRecord)
    policy.is_console_enabled || return false
    try
        @error "[fault] $(record.site) in $(record.origin): $(record.message)" _module = nothing _file = nothing key = record.key count = record.count reference = record.first_reference traceback = record.traceback
        true
    catch
        false
    end
end

# Tier 4.
function _report_by_sound(backend)
    try
        play_fault_sound!(backend)
        true
    catch
        false
    end
end

# The drain reports a target that could not take a record. It is the same tier 3,
# and it must not be allowed to raise from inside the drain either.
function _log_fault_report_failure(target, exception)
    try
        @error "[fault] a fault target refused a record" target = typeof(target) exception = exception
    catch
    end
    nothing
end
