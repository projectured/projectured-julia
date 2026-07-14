# Fragment of `CellModule` — the pull-based reactive kind and its engine.
# `AbstractCell` is already in scope. This is the only cell kind that touches the
# performance counters, so it pulls in the bump macro.
using ..PerformanceCounterModule

"""
    ReactiveCell{T}   (alias: `Cell`; `Cell(v)` ≡ `ReactiveCell{Any}(v)`)

A reactive cell that holds either a primitive value or a lazy computation.
Dependency tracking is automatic: when a computed cell evaluates its thunk,
every `ReactiveCell` read via `c[]` is recorded as a dependency. When any
upstream cell changes, all downstream dependents are invalidated and will
recompute on next read.

# Construction

    Cell(value)                       # untyped primitive cell (T = Any)
    Cell(f::Function)                 # untyped computed cell – f is the thunk (zero args)
    Cell(f::Function; as_value=true)  # primitive holding f AS a value, not a thunk
    ReactiveCell{T}(value)            # typed primitive cell (type-stable reads)
    ReactiveCell{T}(f::Function)      # typed computed cell (f is the thunk)
    ReactiveCell{T}(f::Function; as_value=true) # typed primitive holding f as a value

# Reading and writing

    c[]           # read (triggers computation if invalid)
    c[] = v       # set a primitive value, invalidating dependents
    set_function!(c, f)  # switch to a computed cell with thunk `f`
    set_value!(c, v) # switch to a primitive cell with value `v`
"""
mutable struct ReactiveCell{T} <: AbstractCell{T}
    value::T
    thunk::Union{Nothing, Function}
    valid::Bool
    deps::Set{ReactiveCell}           # cells I read from  (upstream, STRONG)
    dependents::Vector{WeakRef}       # cells that read me  (downstream, WEAK)

    ReactiveCell{T}(value) where {T} =
        new{T}(value, nothing, true, Set{ReactiveCell}(), WeakRef[])
    # A `Function` argument is the cell's *thunk* (a computed cell): `value` starts
    # *undefined* (a typed field cannot hold a placeholder) and `valid = false`
    # guarantees `recompute!` assigns it before any read returns. Pass
    # `as_value = true` to instead store the function itself AS the value — a valid
    # primitive holding `f` — the clean way to hold a callable as a value, since a
    # bare `Cell(f)` reads `f` as a thunk.
    function ReactiveCell{T}(f::Function; as_value::Bool = false) where {T}
        if as_value
            return new{T}(f, nothing, true, Set{ReactiveCell}(), WeakRef[])
        end
        c = new{T}()
        c.thunk = f
        c.valid = false
        c.deps = Set{ReactiveCell}()
        c.dependents = WeakRef[]
        return c
    end
end

"""
`Cell` is a `const` alias for the **concrete** `ReactiveCell{Any}` — the untyped
reactive cell. It is deliberately concrete (not an abstract alias) so
`Vector{Cell}`, `Set{Cell}` and `::Cell` struct fields stay concretely typed,
which dispatch across the machinery depends on. Code that means "a cell of any
kind" tests `isa AbstractCell`; code that means "a reactive cell of any value
type" tests `isa ReactiveCell`.
"""
const Cell = ReactiveCell{Any}

"""Primitive untyped cell holding `value`."""
ReactiveCell(value) = ReactiveCell{Any}(value)

"""
Untyped cell from a `Function`: by default `f` is the cell's thunk (a computed
cell); with `as_value = true`, `f` is stored AS the cell's value (a primitive).
"""
ReactiveCell(f::Function; as_value::Bool = false) = ReactiveCell{Any}(f; as_value)

# ── per-task tracking stack ────────────────────────────────────────────────
# While a ReactiveCell's thunk is running, that cell sits on the current task's
# stack so any ReactiveCell read during evaluation can register itself as a
# dependency. The stack is task-local, not a module global: concurrent
# evaluations (e.g. separate editors on separate tasks) each get their own, so
# their dependency tracking never crosses.
_computing_stack() =
    get!(() -> ReactiveCell[], task_local_storage(), :projectured_reactive_computing)::Vector{ReactiveCell}

# The reactive hot path bumps the performance counters via `@count_performance`
# (imported at the top of this file). The macro lives in `PerformanceCounterModule`
# (cell/PerformanceCounter.jl); it expands to a bump into the task-local counter
# store when counting is compiled in, and to `nothing` when it is not — so these
# call sites cost nothing in a normal build.

# ── reading ──────────────────────────────────────────────────────────────

function Base.getindex(c::ReactiveCell)
    @count_performance :reads
    # register dependency if inside a computation
    stack = _computing_stack()
    if !isempty(stack)
        observer = stack[end]
        if observer !== c
            _register_dependent!(c, observer)
            push!(observer.deps, c)
        end
    end
    if !c.valid
        recompute!(c)
    end
    return c.value
end

# Force a computed cell's thunk. The fast path is a direct call; if that raises a
# `MethodError` (typically a world-age miss — a thunk constructed in a newer world
# than the caller's, then forced from an older-world call site), retry once through
# `Base.invokelatest`, which resolves against the latest method table. A genuine
# `MethodError` simply rethrows from the retry. Thunks are contractually pure, so a
# second evaluation is safe.
function _force_thunk(@nospecialize(f))
    try
        return f()
    catch e
        e isa MethodError || rethrow()
        return Base.invokelatest(f)
    end
end

function recompute!(c::ReactiveCell)
    if c.thunk === nothing
        c.valid = true
        return
    end
    # detach old upstream links
    for dep in c.deps
        _unregister_dependent!(dep, c)
    end
    empty!(c.deps)
    # evaluate thunk while tracking dependencies
    stack = _computing_stack()
    push!(stack, c)
    try
        c.value = _force_thunk(c.thunk)
    finally
        pop!(stack)
    end
    c.valid = true
    @count_performance :computes
end

# ── invalidation ─────────────────────────────────────────────────────────

function invalidate!(c::ReactiveCell)
    c.valid && _invalidate_walk!(c)
end

function _invalidate_walk!(c::ReactiveCell)
    c.valid = false
    @count_performance :invalidations
    ds = c.dependents
    for i in eachindex(ds)
        d = ds[i].value
        d === nothing && continue      # reader already collected — nothing to invalidate
        dd = d::ReactiveCell
        dd.valid && _invalidate_walk!(dd)
    end
end

# ── writing ──────────────────────────────────────────────────────────────

"""
    c[] = value

Set `c` to a primitive value, invalidating all downstream dependents
(reactive kind), or store the value with no propagation (mutable kind).
"""
function Base.setindex!(c::ReactiveCell, value)
    @count_performance :writes
    _detach_upstream!(c)
    c.thunk = nothing
    c.value = value
    c.valid = true
    _invalidate_dependents!(c)
    return value
end

"""
    set_value!(c, value)

Equivalent to `c[] = value`. Turns `c` into a primitive cell.
"""
set_value!(c::ReactiveCell, value) = (c[] = value)

"""
    set_function!(c, thunk::Function)

Turn `c` into a computed cell. `thunk` is a zero-argument function that
will be called lazily. Dependents are invalidated immediately. The previous
value stays cached in the (now invalid) cell until the first read replaces it
— a typed cell cannot hold a `nothing` placeholder; when `T` admits `nothing`
the value is cleared eagerly so the old object is released.
"""
function set_function!(c::ReactiveCell{T}, thunk::Function) where {T}
    _detach_upstream!(c)
    c.thunk = thunk
    nothing isa T && (c.value = nothing)
    c.valid = false
    _invalidate_dependents!(c)
    return c
end

"""Return `true` if the cached value is up to date."""
is_up_to_date(c::ReactiveCell) = c.valid
is_up_to_date(cs::Vector{Cell}) = all(is_up_to_date, cs)

# ── untracked read ─────────────────────────────────────────────────────────

"""
    peek(c::ReactiveCell)

Read a cell's value **without** registering a dependency (an untracked read).
Unlike `c[]`, calling this inside a computed thunk does not make the thunk a
dependent of `c`. A generic reactive primitive (cf. Solid's `untrack`, MobX's
`untracked`) — for callers that want to *sample* a cell's current value rather
than subscribe to it.
"""
function Base.peek(c::ReactiveCell)
    c.valid || recompute!(c)
    return c.value
end

# ── helpers ──────────────────────────────────────────────────────────────

function _detach_upstream!(c::ReactiveCell)
    for dep in c.deps
        _unregister_dependent!(dep, c)
    end
    empty!(c.deps)
end

function _invalidate_dependents!(c::ReactiveCell)
    ds = c.dependents
    for i in eachindex(ds)
        d = ds[i].value
        d === nothing && continue      # reader already collected
        dd = d::ReactiveCell
        dd.valid && _invalidate_walk!(dd)
    end
end

# ── the downstream edge ────────────────────────────────────────────────────
#
# `dependents` exists to propagate INVALIDATION downstream. It must not keep the
# reader ALIVE, so it holds `WeakRef`s. A strong set here meant that every cell a
# document was ever read by — every projection pipeline ever printed from it, and
# every span a printer shed while recomputing — was pinned for ever, because the only
# place an edge was removed was `recompute!`, and a discarded cell never recomputes.
#
# A `Vector` with a linear identity scan, not a hash set: the set is *tiny* (across a
# live pipeline, mean 0.85, median 1, p99 3, max 40 — one cell in 4173 exceeds 16), and
# at that size hashing is pure overhead. Measured, this is ~3x faster than the `Set` it
# replaces on the hot path, 1.4x faster to detach and 4-10x faster to invalidate. A
# `WeakKeyDict` — the obvious choice — is 7x SLOWER, because its lock dominates.
# See plan/pending/reactive-dependents-leak.md.
#
# Both helpers prune entries whose reader has been collected, in the scan they are
# already doing, so dead `WeakRef`s never accumulate.

function _register_dependent!(c::ReactiveCell, observer::ReactiveCell)
    ds = c.dependents
    i, n = 1, length(ds)
    @inbounds while i <= n
        v = ds[i].value
        if v === nothing
            ds[i] = ds[n]; pop!(ds); n -= 1     # collected: swap-remove, re-examine slot i
        elseif v === observer
            return nothing                      # already registered
        else
            i += 1
        end
    end
    push!(ds, WeakRef(observer))
    return nothing
end

function _unregister_dependent!(c::ReactiveCell, observer::ReactiveCell)
    ds = c.dependents
    i, n = 1, length(ds)
    @inbounds while i <= n
        v = ds[i].value
        if v === nothing || v === observer
            ds[i] = ds[n]; pop!(ds); n -= 1
        else
            i += 1
        end
    end
    return nothing
end

# ── display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, c::ReactiveCell)
    kind = c.thunk === nothing ? "primitive" : "computed"
    print(io, "Cell(", kind, ", ")
    # Forward `io` (rather than `repr`, which would build a fresh buffer) so the
    # value is shown in the same IOContext — any depth/limit keys a caller set on
    # `io` stay in effect across Cell-wrapped subtrees.
    c.valid ? show(io, c.value) : print(io, "<invalid>")
    print(io, ")")
end
