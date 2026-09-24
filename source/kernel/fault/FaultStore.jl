# Fragment of `FaultModule` — the per-editor collection of faults, and the drain
# that hands new ones to whatever shows them.

"""
    FaultStore(; capacity = 64)

Where a fault goes the moment it is caught. One per editor.

**A store is deliberately not made of cells, and that is what makes the whole
design work.** A printer does not throw when `print_document` runs; it throws
later, inside the thunk that derives its output, while the renderer reads it. So
the barrier must catch inside the thunk — and a thunk may not write a cell
(`PAR-NO-WRITE-IN-THUNK`), because a write in the middle of a computation
invalidates consumers half way through and leaves the graph inconsistent.

A store has no dependents, so a write to it invalidates nothing and the rule it
protects is not in play. The write is keyed, so a thunk that runs ten times for
one logical fault leaves one record. And the thunk's own answer does not depend
on the store, so its cached value stays correct. `PAR-PURE-THUNK` and
`PAR-NO-WRITE-IN-THUNK` each carry the paragraph that says so.

The editor loop then calls [`drain_faults!`](@ref) once per frame, on its own
task, outside every thunk. That call may write cells, and it is what puts a
fault into a log document.

A store has no lock, so all code that writes it must run on the thread of the
editor task. A task that the editor task starts with `@async` runs on that
thread.

`capacity` bounds the number of distinct keys. A new key that does not fit is
counted in `dropped` rather than kept: the first faults are the ones that name
the cause, so the store keeps those.

# Example

    store = FaultStore()
    attach_fault_target!(store, log)
    record_fault!(store, :print; origin = JsonToSyntax, reference, exception,
                  traceback = catch_backtrace())
    drain_faults!(store)

See also [`record_fault!`](@ref), [`drain_faults!`](@ref) and
[`run_fault_barrier`](@ref).
"""
mutable struct FaultStore
    records::Dict{UInt64, FaultRecord}
    order::Vector{UInt64}
    undrained::Vector{UInt64}
    queued_counts::Dict{UInt64, Int}
    targets::Vector{Any}
    consecutive::Dict{Symbol, Int}
    capacity::Int
    dropped::Int
    depth::Int
    # The wake of the editor this store belongs to, or `nothing`. Called the
    # moment a record is queued for the drain, so a sleeping editor runs the
    # frame whose report shows the fault. A function and not an editor,
    # because this layer sits below everything and names nothing above Base.
    wake::Any
end

FaultStore(; capacity::Integer = 64) =
    FaultStore(Dict{UInt64, FaultRecord}(), UInt64[], UInt64[],
               Dict{UInt64, Int}(), Any[], Dict{Symbol, Int}(),
               Int(capacity), 0, 0, nothing)

"""
    get_fault_records(store) -> Vector{FaultRecord}

Every record the store holds, oldest first.
"""
get_fault_records(store::FaultStore) = [store.records[key] for key in store.order]
get_fault_records(::Nothing) = FaultRecord[]

"""
    attach_fault_target!(store, target) -> store

Say that `target` is to be shown every new fault. A target already attached is
not attached twice.
"""
function attach_fault_target!(store::FaultStore, target)
    any(existing -> existing === target, store.targets) || push!(store.targets, target)
    store
end

attach_fault_target!(::Nothing, target) = nothing

"""
    attach_fault_wake!(store, wake) -> store

Hand the store the wake function of its editor. `record_fault!` calls it the
moment a record is queued for the drain — a new key, or a count that grew by
an order of magnitude — and not on a plain count bump, so a fault that
repeats does not wake the editor at each occurrence.
"""
attach_fault_wake!(store::FaultStore, wake) = (store.wake = wake; store)

attach_fault_wake!(::Nothing, wake) = nothing

# Best effort, and it must stay that: `record_fault!` runs inside reactive
# thunks and inside barriers, so a wake that throws must not throw through
# them (PAR-REPORT-NEVER-THROWS).
function _notify_fault_wake!(store::FaultStore)
    wake = store.wake
    wake === nothing && return nothing
    try
        wake()
    catch
    end
    nothing
end

# How many times a count has to grow before it is worth showing again. A fault
# at three thousand places would otherwise write the log three thousand times,
# and a write in every frame makes the editor draw again in every frame.
# One bucket per power of ten writes it four times instead, and the number a
# person reads is right to an order of magnitude.
_get_fault_count_bucket(count::Integer) = count <= 0 ? 0 : floor(Int, log10(count))

"""
    record_fault!(store, site; origin, reference = nothing, exception,
                  traceback = nothing) -> FaultRecord or nothing

Put one fault in the store and answer the record it belongs to.

A key the store already holds takes a count rather than a second record, so the
thousands of nodes one bug fails at become one line with a number. The message
and the traceback are formatted for a new key alone, because formatting a
traceback is expensive and a repeat needs neither.

It is safe to call from inside a reactive thunk, which is the whole reason the
store exists. It is also safe to call with `nothing` as the store, so a
projection that was given none still runs.

Answers `nothing` when there is no store, or when the store is full and the key
is new.

# Example

    record_fault!(store, :print; origin = p.inner, reference = ctx.reference, exception,
                  traceback = catch_backtrace())

See also [`FaultStore`](@ref) and [`drain_faults!`](@ref).
"""
function record_fault!(store::FaultStore, site::Symbol; origin, reference = nothing,
                       exception, traceback = nothing)
    key = compute_fault_key(site, get_fault_origin_name(origin),
                            get_fault_exception_name(exception))
    known = get(store.records, key, nothing)
    if known !== nothing
        grown = FaultRecord(known.key, known.site, known.origin, known.exception_type,
                            known.message, known.traceback, known.first_reference,
                            known.first_time, known.count + 1)
        store.records[key] = grown
        # Compare against the count that was last queued, not the one that was
        # last drained. Comparing against the drained count re-queues the key on
        # every occurrence above the first bucket, which is the busy loop this
        # rule exists to stop.
        queued = get(store.queued_counts, key, 0)
        if _get_fault_count_bucket(grown.count) != _get_fault_count_bucket(queued)
            store.queued_counts[key] = grown.count
            push!(store.undrained, key)
            _notify_fault_wake!(store)
        end
        return grown
    end
    if length(store.order) >= store.capacity
        store.dropped += 1
        return nothing
    end
    record = make_fault_record(site; origin, reference, exception, traceback)
    store.records[record.key] = record
    store.queued_counts[record.key] = record.count
    push!(store.order, record.key)
    push!(store.undrained, record.key)
    _notify_fault_wake!(store)
    record
end

record_fault!(::Nothing, site::Symbol; origin, reference = nothing, exception,
              traceback = nothing) = nothing

"""
    drain_faults!(store) -> Vector{FaultRecord}

Hand every record that is new, or that grew by an order of magnitude, to each
attached target, and answer the records that were handed over.

The answer is what lets the caller report the same records on the console: the
drain is the one place that knows which records are new, and the console tier
needs exactly that.

Call it once per frame from the editor's own task, before anything reads the
projection. A record is handed over at most once per count bucket, so a store
with nothing new writes no cell, invalidates nothing, and causes no repaint.

It never throws. A target whose `append_fault!` fails is skipped and reported on
the console, because a log that can not take a fault must not take the editor
with it.
"""
function drain_faults!(store::FaultStore)
    isempty(store.undrained) && return FaultRecord[]
    keys_to_emit = copy(store.undrained)
    empty!(store.undrained)
    emitted = FaultRecord[]
    for key in keys_to_emit
        record = get(store.records, key, nothing)
        record === nothing && continue
        for target in store.targets
            try
                append_fault!(target, record)
            catch exception
                _log_fault_report_failure(target, exception)
            end
        end
        push!(emitted, record)
    end
    emitted
end

drain_faults!(::Nothing) = FaultRecord[]

"""
    get_consecutive_fault_count(store, counter) -> Int

How many times in a row the barriers that count on `counter` caught, with no
success between. A barrier counts on its site, or on the counter it was given.

A circuit breaker reads it: a backend seam that fails every frame is worse to
call than to leave alone, and a printer that fails every frame is what the safe
mode answers.
"""
get_consecutive_fault_count(store::FaultStore, counter::Symbol) =
    get(store.consecutive, counter, 0)

get_consecutive_fault_count(::Nothing, counter::Symbol) = 0

"""
    reset_consecutive_fault_count!(store, counter) -> store

Say that a barrier that counts on `counter` ran without a fault.
"""
function reset_consecutive_fault_count!(store::FaultStore, counter::Symbol)
    get(store.consecutive, counter, 0) == 0 || (store.consecutive[counter] = 0)
    store
end

reset_consecutive_fault_count!(::Nothing, counter::Symbol) = nothing

"""
    clear_fault_store!(store) -> store

Forget every record. The `dropped` count is forgotten with them.
"""
function clear_fault_store!(store::FaultStore)
    empty!(store.records)
    empty!(store.order)
    empty!(store.undrained)
    empty!(store.queued_counts)
    empty!(store.consecutive)
    store.dropped = 0
    store
end
