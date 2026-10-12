# Fragment of `FaultModule` — the per-editor collection of faults, and the drain
# that hands new ones to whatever shows them.

"""
    FaultStore(; capacity = 64)

Where a fault goes the moment it is caught. One per editor.

**A store is deliberately not made of cells, and that is what makes the whole
design work.** A printer does not throw when `print_document` runs; it throws
later, inside the computation that derives its output, while the renderer reads
it. So the barrier must catch inside the computation — and a computation may not
write a cell (`PAR-NO-WRITE-IN-THUNK`), because a write in the middle of a
computation invalidates consumers half way through and leaves the graph
inconsistent.

A store has no dependents, so a write to it invalidates nothing and the rule it
protects is not in play. The write is keyed, so a computation that runs ten
times for one logical fault leaves one record. And the answer of the computation
does not depend on the store, so its cached value stays correct.
`PAR-PURE-THUNK` and `PAR-NO-WRITE-IN-THUNK` each carry the paragraph that says
so.

Call [`drain_faults!`](@ref) once per frame, on the task of the editor, outside
every computation. The drain may write cells, and it is what puts a fault into a
log document.

A store has no lock, so all code that writes it must run on the thread of the
editor task. A task that the editor task starts with `@async` runs on that
thread.

`capacity` bounds the number of distinct keys, and it must be at least 1. A new
key that does not fit takes the place of the oldest key that the drain already
handed over, so each fault reaches the targets at least once. A key that comes
back after the store forgot it starts a new count. When every key still waits for
the drain, the new fault counts into the overflow record: one record beside the
capacity, whose count says how many faults did not fit.

# Example

    store = FaultStore()
    attach_fault_target!(store, log)
    record_fault!(store, :print; origin = p.inner, reference, exception,
                  traceback = catch_backtrace())
    drain_faults!(store)

See also [`record_fault!`](@ref), [`drain_faults!`](@ref) and
[`run_fault_barrier!`](@ref).
"""
mutable struct FaultStore
    records::Dict{UInt64, FaultRecord}
    order::Vector{UInt64}
    undrained::Vector{UInt64}
    queued_counts::Dict{UInt64, Int}
    targets::Vector{Any}
    consecutive::Dict{Symbol, Int}
    capacity::Int
    depth::Int
    # The wake of the editor this store belongs to, or `nothing`. Called the
    # moment a record is queued for the drain, so a sleeping editor runs the
    # frame whose report shows the fault. A function and not an editor,
    # because this layer sits below everything and names nothing above Base.
    wake::Any
end

function FaultStore(; capacity::Integer = 64)
    capacity >= 1 || throw(ArgumentError("a fault store holds at least one fault"))
    FaultStore(Dict{UInt64, FaultRecord}(), UInt64[], UInt64[],
               Dict{UInt64, Int}(), Any[], Dict{Symbol, Int}(),
               Int(capacity), 0, nothing)
end

# The overflow record counts each new fault that found every key of the store
# waiting for the drain. Its exception type is `Nothing`, because it stands for
# many exceptions and holds none.
const _OVERFLOW_SITE = :store
const _OVERFLOW_ORIGIN = :FaultStore
const _OVERFLOW_KEY = _compute_fault_key(_OVERFLOW_SITE, _OVERFLOW_ORIGIN, :Nothing)
const _OVERFLOW_MESSAGE =
    "a new fault did not fit: the store was full, and every record waited for the drain"

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
# computations and inside barriers, so an ordinary exception of the wake must not
# throw through them (PAR-REPORT-NEVER-THROWS). An exception that means stop goes on.
function _notify_fault_wake!(store::FaultStore)
    wake = store.wake
    wake === nothing && return nothing
    try
        wake()
    catch exception
        is_passthrough_exception(exception) && rethrow()
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

It is safe to call from inside a reactive computation, which is the whole reason
the store exists. It is also safe to call with `nothing` as the store, so a
projection that was given none still runs.

Answers `nothing` when there is no store. A new fault that finds the store full
belongs to the overflow record when no key can make room (see [`FaultStore`](@ref)),
and the answer is that record.

# Example

    record_fault!(store, :print; origin = p.inner, reference = ctx.reference, exception,
                  traceback = catch_backtrace())

See also [`FaultStore`](@ref) and [`drain_faults!`](@ref).
"""
function record_fault!(store::FaultStore, site::Symbol; origin, reference = nothing,
                       exception, traceback = nothing)
    key = _compute_fault_key(site, _get_fault_origin_name(origin),
                             _get_fault_exception_name(exception))
    known = get(store.records, key, nothing)
    known === nothing || return _count_known_fault!(store, known)
    if _count_fault_keys(store) >= store.capacity && !_forget_drained_fault!(store)
        return _count_overflow_fault!(store)
    end
    _add_fault_record!(store, make_fault_record(site; origin, reference, exception,
                                                traceback))
end

record_fault!(::Nothing, site::Symbol; origin, reference = nothing, exception,
              traceback = nothing) = nothing

# One more occurrence of a key that the store holds.
function _count_known_fault!(store::FaultStore, known::FaultRecord)
    grown = FaultRecord(known.key, known.site, known.origin, known.exception_type,
                        known.message, known.traceback, known.first_reference,
                        known.first_time, known.count + 1)
    store.records[known.key] = grown
    # Compare against the count that was last queued, not the one that was last
    # drained. Comparing against the drained count re-queues the key on every
    # occurrence above the first bucket, which is the busy loop this rule exists
    # to stop. A key that waits for the drain already has its latest count in
    # `records`, so it waits there one time.
    queued = get(store.queued_counts, known.key, 0)
    if _get_fault_count_bucket(grown.count) != _get_fault_count_bucket(queued)
        store.queued_counts[known.key] = grown.count
        known.key in store.undrained || push!(store.undrained, known.key)
        _notify_fault_wake!(store)
    end
    grown
end

function _add_fault_record!(store::FaultStore, record::FaultRecord)
    store.records[record.key] = record
    store.queued_counts[record.key] = record.count
    push!(store.order, record.key)
    push!(store.undrained, record.key)
    _notify_fault_wake!(store)
    record
end

# The keys that count against the capacity: every key but the overflow record.
_count_fault_keys(store::FaultStore) =
    length(store.order) - haskey(store.records, _OVERFLOW_KEY)

# Forget the oldest key that the drain already handed over, and answer whether
# there was one.
function _forget_drained_fault!(store::FaultStore)
    index = findfirst(key -> key != _OVERFLOW_KEY && !(key in store.undrained),
                      store.order)
    index === nothing && return false
    key = store.order[index]
    deleteat!(store.order, index)
    delete!(store.records, key)
    delete!(store.queued_counts, key)
    true
end

function _count_overflow_fault!(store::FaultStore)
    known = get(store.records, _OVERFLOW_KEY, nothing)
    known === nothing || return _count_known_fault!(store, known)
    _add_fault_record!(store, FaultRecord(_OVERFLOW_KEY, _OVERFLOW_SITE, _OVERFLOW_ORIGIN,
                                          :Nothing, _OVERFLOW_MESSAGE, "", nothing,
                                          time(), 1))
end

"""
    drain_faults!(store; policy = FaultPolicy(), backend = nothing) -> Vector{FaultRecord}

Hand every record that is new, or that grew by an order of magnitude, to each
attached target, report it at the next tier, and answer the records that were
handed over.

A record that a target took is shown, so [`report_fault!`](@ref) keeps the
console quiet for it. A record that no target took goes to the console, and to
the sound when the console is off or fails. A target took the record when its
`append_fault!` returned.

Call it once per frame, on the task of the editor, outside every computation and
before anything reads the projection. A record is handed over at most once per
drain and at most once per count bucket, so a store with nothing new writes no
cell, invalidates nothing, and causes no repaint.

It throws nothing but an `ArgumentError` for a `policy` that is not a
`FaultPolicy`, and it checks that before it changes the store. A target whose
`append_fault!` fails is skipped, and a console line reports it when `policy`
opens the console tier. A log that can not take a fault must not stop the editor.
An exception that means stop goes on, and the records that the drain did not hand
over wait for the next drain.
"""
function drain_faults!(store::FaultStore; policy = FaultPolicy(), backend = nothing)
    # FaultPolicy.jl loads after this file, so the keyword has no type.
    policy isa FaultPolicy ||
        throw(ArgumentError("drain_faults!: the policy must be a FaultPolicy, " *
                            "not a $(typeof(policy))"))
    isempty(store.undrained) && return FaultRecord[]
    keys_to_emit = copy(store.undrained)
    empty!(store.undrained)
    emitted = FaultRecord[]
    handed = 0
    try
        for key in keys_to_emit
            record = get(store.records, key, nothing)
            if record !== nothing
                is_shown = _hand_fault_to_targets!(store, record, policy)
                report_fault!(store, record; policy, backend, is_shown)
                push!(emitted, record)
            end
            handed += 1
        end
    finally
        # Only an exception that means stop leaves the loop early.
        for key in @view keys_to_emit[handed + 1:end]
            key in store.undrained || push!(store.undrained, key)
        end
    end
    emitted
end

drain_faults!(::Nothing; policy = FaultPolicy(), backend = nothing) = FaultRecord[]

# Hand `record` to each target of `store`, and answer whether one of them took it.
function _hand_fault_to_targets!(store::FaultStore, record::FaultRecord, policy)
    is_shown = false
    for target in store.targets
        try
            append_fault!(target, record)
            is_shown = true
        catch exception
            is_passthrough_exception(exception) && rethrow()
            _log_fault_report_failure(policy, target, exception)
        end
    end
    is_shown
end

"""
    get_consecutive_fault_count(store, counter) -> Int

How many times in a row the barriers that count on `counter` caught, with no
success between. A barrier counts on its site, or on the counter it was given.

A circuit breaker reads it: a seam that fails every frame is worse to call than
to leave alone.
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
