# Fragment of `FaultModule` — the report cascade. A fault is reported at the
# first tier that works, and a tier that fails falls to the next one.

# The tiers, in the order they are tried:
#
#   1  a mark in the output document, where it failed
#   2  a target of the store                     — drain_faults!
#   3  the console                               — here
#   4  a sound                                   — here
#   5  nothing                                   — here
#
# Tiers 1 and 2 are not in this file. Code that can put a mark in its output puts
# it there and records the fault in the store. The drain hands each new record to
# the targets, and then calls `report_fault!` with `is_shown`, so a record that a
# target took goes no further, except to the sound of a device fault.

"""
    report_fault!(store, record; policy, backend, is_shown = false) -> Symbol

Report `record` at the first tier that works, and answer the tier it reached:
`:target`, `:console`, `:sound` or `:swallowed`.

`is_shown` says that a target of the store took the record, which is the tier
before the console. Then the console stays quiet. [`drain_faults!`](@ref) passes
it.

**This function never throws an ordinary exception.** It is the last thing that
runs when everything else failed, and sometimes that includes the code that was
meant to report. A test asserts it against a store that throws and a backend that
throws, both at once. An exception that means stop (`is_passthrough_exception`)
goes on, because it is a request to stop the editor.

A fault raised while a fault is reported does not recurse: the store carries a
depth, and a nested call stops after the console.

The sound plays when no tier before it showed the record, and also when the
fault came from a device, because a screen that draws nothing shows no target,
and a person has nothing else to notice.

# Example

    report_fault!(editor.faults, record; policy = editor.fault_policy,
                  backend = editor.backend)

See also [`drain_faults!`](@ref) and [`run_fault_barrier!`](@ref), which call it.
"""
function report_fault!(store, record; policy::FaultPolicy, backend, is_shown::Bool = false)
    try
        # A store that fails to count the depth gives depth 1, and the report goes
        # on to the console. A store that fails to leave it keeps the tier.
        is_entered = true
        depth = try
            _enter_fault_report!(store)
        catch exception
            is_passthrough_exception(exception) && rethrow()
            is_entered = false
            1
        end
        try
            tier = is_shown ? :target :
                   _report_on_console(policy, record) ? :console : :swallowed
            depth > 1 && return tier
            wants_sound = policy.is_sound_enabled &&
                          (tier === :swallowed || record.site === :device)
            if wants_sound && _report_by_sound(backend)
                tier === :swallowed && (tier = :sound)
            end
            return tier
        finally
            if is_entered
                try
                    _leave_fault_report!(store)
                catch exception
                    is_passthrough_exception(exception) && rethrow()
                end
            end
        end
    catch exception
        # Tier 5. Nothing left to try, and no ordinary exception may leave this
        # function. An exception that means stop goes on.
        is_passthrough_exception(exception) && rethrow()
        return :swallowed
    end
end

_enter_fault_report!(store::FaultStore) = (store.depth += 1; store.depth)
_enter_fault_report!(::Nothing) = 1

_leave_fault_report!(store::FaultStore) = (store.depth -= 1; nothing)
_leave_fault_report!(::Nothing) = nothing

# Tier 3. Through the logger and not a raw write, so the fields of the record
# reach every logger that the process installed.
function _report_on_console(policy::FaultPolicy, record::FaultRecord)
    policy.is_console_enabled || return false
    try
        @error("[fault] $(record.site) in $(record.origin): $(record.message)",
               _module = nothing, _file = nothing, key = record.key,
               count = record.count, reference = record.first_reference,
               traceback = record.traceback)
        true
    catch exception
        is_passthrough_exception(exception) && rethrow()
        false
    end
end

# Tier 4.
function _report_by_sound(backend)
    try
        play_fault_sound!(backend)
        true
    catch exception
        is_passthrough_exception(exception) && rethrow()
        false
    end
end

# The drain reports a target that could not take a record. It is the same tier 3,
# and it must not be allowed to raise from inside the drain either.
function _log_fault_report_failure(policy::FaultPolicy, target, exception)
    policy.is_console_enabled || return nothing
    try
        @error("[fault] a fault target refused a record",
               target = typeof(target), exception = exception)
    catch failure
        is_passthrough_exception(failure) && rethrow()
    end
    nothing
end
