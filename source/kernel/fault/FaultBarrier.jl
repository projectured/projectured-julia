# Fragment of `FaultModule` — the one catch. Everything that survives a fault
# survives it here.

"""
    run_fault_barrier(body, store, policy, backend, site; origin, reference, fallback)

Run `body`, and answer `fallback` rather than the exception when it throws.

Use it around one stage of work that the editor must survive: a frame stage, a
call into a backend, the evaluation of an operation. It is not what a projection
uses — a projection must answer a substitute document and so carries its own
catch, and calls [`record_fault!`](@ref) directly.

What it does, in order:

1. An exception that [`is_passthrough_exception`](@ref) names is re-raised at
   once. A request to quit must reach the loop that stops on it.
2. The consecutive count for `site` grows, so a circuit breaker above can read
   how long this has been going on. A run without a fault resets it.
3. The fault goes in the store, keyed, so the thousands of nodes one bug fails
   at become one record with a number.
4. A record that is new is reported by [`report_fault!`](@ref). A repeat is not,
   because a console that takes one line per frame is a fault of its own.

**`policy.is_barrier_enabled` false means it catches nothing.** A test editor
sets it false, so a broken projection fails its test rather than passing quietly.
That switch is the reason this whole feature can not make the suite lie.

# Example

    run_fault_barrier(editor.faults, editor.fault_policy, editor.backend, :print) do
        print!(editor)
    end

See also [`FaultPolicy`](@ref), [`record_fault!`](@ref) and
[`report_fault!`](@ref).
"""
function run_fault_barrier(body, store, policy::FaultPolicy, backend, site::Symbol;
                           origin = :editor, reference = nothing, fallback = nothing)
    policy.is_barrier_enabled || return body()
    try
        value = body()
        reset_consecutive_fault_count!(store, site)
        value
    catch exception
        is_passthrough_exception(exception) && rethrow()
        traceback = catch_backtrace()
        _count_fault!(store, site)
        record = record_fault!(store, site, origin, reference, exception, traceback)
        # No store means no place a record could be kept and no place a repeat
        # could be noticed, so the report is made from the exception itself.
        store === nothing &&
            (record = make_fault_record(site, origin, reference, exception, traceback))
        if record !== nothing && record.count == 1
            report_fault!(store, policy, backend, record)
        end
        fallback
    end
end

_count_fault!(store::FaultStore, site::Symbol) =
    (store.consecutive[site] = get(store.consecutive, site, 0) + 1)

_count_fault!(::Nothing, site::Symbol) = 0
