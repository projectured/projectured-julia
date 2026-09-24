# Fragment of `FaultModule` — the barrier around one stage of work. It catches a
# fault, records it and answers a fallback.

"""
    run_fault_barrier(body, store; policy, backend, site, counter, origin, reference,
                      fallback)

Run `body`, and answer `fallback` rather than the exception when it throws.

Use it around one stage of work that the editor must survive: a frame stage, a
call into a backend, the evaluation of an operation. It is not what a projection
uses — a projection must answer a substitute document and so carries its own
catch, and calls [`record_fault!`](@ref) directly.

What it does, in order:

1. An exception that [`is_passthrough_exception`](@ref) names is re-raised at
   once. A request to quit must reach the loop that stops on it.
2. The consecutive count for `counter` grows, so a circuit breaker above can
   read how long this has been going on. A run without a fault resets it.

   `counter` defaults to `site` and exists because one site can have two halves
   that fail on their own. The device seam is read by one call and written by
   another; with one counter between them, a read that works resets the count a
   write that failed just raised, and the breaker never trips.
3. The fault goes in the store, keyed, so the thousands of nodes one bug fails
   at become one record with a number.
4. Reporting is left to [`drain_faults!`](@ref) and the frame that calls it,
   because the drain is the one place that knows which records are new and it
   is where the projection barrier's records arrive too. One reporter, one line
   per new fault. A barrier given no store has no drain behind it, so that one
   reports for itself.

**`policy.is_barrier_enabled` false means it catches nothing.** An editor that a
test makes has it false, so a broken projection fails its test rather than
passing quietly.

# Example

    run_fault_barrier(editor.faults; policy = editor.fault_policy,
                      backend = editor.backend, site = :print) do
        print!(editor)
    end

See also [`FaultPolicy`](@ref), [`record_fault!`](@ref) and
[`report_fault!`](@ref).
"""
function run_fault_barrier(body, store; policy::FaultPolicy, backend, site::Symbol,
                           counter::Symbol = site, origin = :editor, reference = nothing,
                           fallback = nothing)
    policy.is_barrier_enabled || return body()
    try
        value = body()
        reset_consecutive_fault_count!(store, counter)
        value
    catch exception
        is_passthrough_exception(exception) && rethrow()
        traceback = catch_backtrace()
        _count_fault!(store, counter)
        record_fault!(store, site; origin, reference, exception, traceback)
        # No store means no drain will ever see this, so the report is made here
        # and now, from the exception itself.
        if store === nothing
            record = make_fault_record(site; origin, reference, exception, traceback)
            report_fault!(store, record; policy, backend)
        end
        fallback
    end
end

_count_fault!(store::FaultStore, counter::Symbol) =
    (store.consecutive[counter] = get(store.consecutive, counter, 0) + 1)

_count_fault!(::Nothing, counter::Symbol) = 0
