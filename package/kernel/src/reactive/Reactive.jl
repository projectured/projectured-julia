"""
    ReactiveModule

Pull-based reactive cell engine (Layer 0). A Cell wraps either a plain value
or a zero-argument thunk. Reading a cell while another cell's thunk is evaluating
registers a dependency edge. Writing a primitive cell eagerly marks all transitive
dependents as stale; recomputation is lazy — it happens on the next read.

The module includes:
- **Cell**: Reactive cell that holds either a primitive value or a lazy computation
- **Functions**: `set_value!`, `set_function!`, `is_up_to_date`, `peek`

The instrumentation counters (`PerformanceCounterModule`,
`reactive/PerformanceCounter.jl`, whose `_perf` dict this module still bumps
inline on the hot path) were split out of this file but stay in the reactive
layer. Anything *built on* `Cell` rather than part of the engine — an animation
clock that samples time, say — belongs in a higher layer, not here.

Dependency tracking is automatic: when a computed cell evaluates its thunk,
every `Cell` read via `c[]` is recorded as a dependency. When any upstream
cell changes, all downstream dependents are invalidated and will recompute
on next read.

# Invariants (unchecked — see documentation/reactive-cells.md)
- **Acyclic graph.** A thunk must never transitively read its own cell;
  `recompute!` would recurse forever. Only *direct* self-edges are skipped.
- **Monotone invalidation.** `_invalidate_walk!` stops at already-invalid
  dependents, trusting they propagated when first invalidated. Always walk the
  full closure on write; never hand-set `valid` or partially invalidate.
- **Write-driven propagation.** Writes invalidate dependents unconditionally —
  there is no value-equality short-circuit, so writing a cell its current value
  still recomputes downstream.
- **Pure thunks.** A thunk may run 0/1/many times and is cached until
  invalidation, so it must be side-effect-free and depend only on cells it reads.
"""
module ReactiveModule

import ..PerformanceCounterModule: _perf

export Cell, set_value!, set_function!, is_up_to_date

"""
    Cell

A reactive cell that holds either a primitive value or a lazy computation.
Dependency tracking is automatic: when a computed cell evaluates its thunk,
every `Cell` read via `c[]` is recorded as a dependency. When any upstream
cell changes, all downstream dependents are invalidated and will recompute
on next read.

# Construction

    Cell(value)          # primitive cell
    Cell(thunk::Function) # computed cell – thunk is called with zero args

# Reading and writing

    c[]         # read (triggers computation if invalid)
    c[] = v     # set a primitive value, invalidating dependents
    set_function!(c, f) # switch to a computed cell with thunk `f`
    set_value!(c, v) # switch to a primitive cell with value `v`
"""
mutable struct Cell
    value::Any
    thunk::Union{Nothing, Function}
    valid::Bool
    deps::Set{Cell}           # cells I read from  (upstream)
    dependents::Set{Cell}     # cells that read me  (downstream)
end

# ── global tracking stack ────────────────────────────────────────────────
# While a Cell's thunk is running, that Cell sits on this stack so that
# any Cell read during evaluation can register itself as a dependency.
const _computing = Cell[]

# Performance counters (`_perf`, `get_performance_counters`, `perf_reset!`, `perf_record!`,
# `@perf_time`) live in `PerformanceCounterModule` (reactive/PerformanceCounter.jl).
# `_perf` is imported above so the Cell hot path below stays a bare `Dict` write.

# ── constructors ─────────────────────────────────────────────────────────

"""Primitive cell holding `value`."""
Cell(value) = Cell(value, nothing, true, Set{Cell}(), Set{Cell}())

"""Computed cell whose value is produced by calling `thunk()`."""
Cell(thunk::Function) = Cell(nothing, thunk, false, Set{Cell}(), Set{Cell}())

# ── reading ──────────────────────────────────────────────────────────────

function Base.getindex(c::Cell)
    _perf[:reads] += 1
    # register dependency if inside a computation
    if !isempty(_computing)
        observer = _computing[end]
        if observer !== c
            push!(c.dependents, observer)
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

function recompute!(c::Cell)
    if c.thunk === nothing
        c.valid = true
        return
    end
    # detach old upstream links
    for dep in c.deps
        delete!(dep.dependents, c)
    end
    empty!(c.deps)
    # evaluate thunk while tracking dependencies
    push!(_computing, c)
    try
        c.value = _force_thunk(c.thunk)
    finally
        pop!(_computing)
    end
    c.valid = true
    _perf[:computes] += 1
end

# ── invalidation ─────────────────────────────────────────────────────────

function invalidate!(c::Cell)
    c.valid && _invalidate_walk!(c)
end

function _invalidate_walk!(c::Cell)
    c.valid = false
    _perf[:invalidations] += 1
    for d in c.dependents
        d.valid && _invalidate_walk!(d)
    end
end

# ── writing ──────────────────────────────────────────────────────────────

"""
    c[] = value

Set `c` to a primitive value, invalidating all downstream dependents.
"""
function Base.setindex!(c::Cell, value)
    _perf[:writes] += 1
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
set_value!(c::Cell, value) = (c[] = value)

"""
    set_function!(c, thunk::Function)

Turn `c` into a computed cell. `thunk` is a zero-argument function that
will be called lazily. Previous value is discarded and dependents are
invalidated immediately.
"""
function set_function!(c::Cell, thunk::Function)
    _detach_upstream!(c)
    c.thunk = thunk
    c.value = nothing
    c.valid = false
    _invalidate_dependents!(c)
    return c
end

"""Return `true` if the cached value is up to date."""
is_up_to_date(c::Cell) = c.valid
is_up_to_date(cs::Vector{Cell}) = all(is_up_to_date, cs)

# ── untracked read ─────────────────────────────────────────────────────────

"""
    peek(c::Cell)

Read a cell's value **without** registering a dependency (an untracked read).
Unlike `c[]`, calling this inside a computed thunk does not make the thunk a
dependent of `c`. A generic reactive primitive (cf. Solid's `untrack`, MobX's
`untracked`) — for callers that want to *sample* a cell's current value rather
than subscribe to it.
"""
function Base.peek(c::Cell)
    c.valid || recompute!(c)
    return c.value
end

# ── helpers ──────────────────────────────────────────────────────────────

function _detach_upstream!(c::Cell)
    for dep in c.deps
        delete!(dep.dependents, c)
    end
    empty!(c.deps)
end

function _invalidate_dependents!(c::Cell)
    for d in c.dependents
        d.valid && _invalidate_walk!(d)
    end
end

# ── display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, c::Cell)
    kind = c.thunk === nothing ? "primitive" : "computed"
    print(io, "Cell(", kind, ", ")
    # Forward `io` (rather than `repr`, which would build a fresh buffer) so the
    # value is shown in the same IOContext — any depth/limit keys a caller set on
    # `io` stay in effect across Cell-wrapped subtrees.
    c.valid ? show(io, c.value) : print(io, "<invalid>")
    print(io, ")")
end

end # module
