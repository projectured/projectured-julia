"""
    ReactiveModule

Pull-based reactive cell engine (Layer 0). A Cell wraps either a plain value
or a zero-argument thunk. Reading a cell while another cell's thunk is evaluating
registers a dependency edge. Writing a primitive cell eagerly marks all transitive
dependents as stale; recomputation is lazy — it happens on the next read.

The module includes:
- **Cell**: Reactive cell that holds either a primitive value or a lazy computation
- **Functions**: `setval!`, `setfn!`, `isuptodate`, `perf_counters`, `perf_reset!`, `perf_record!`, `@perf_time`

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

export Cell, setval!, setfn!, isuptodate, perf_counters, perf_reset!, perf_record!, @perf_time

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
    setfn!(c, f) # switch to a computed cell with thunk `f`
    setval!(c, v) # switch to a primitive cell with value `v`
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

# ── performance counters ─────────────────────────────────────────────────
const _perf = Dict{Symbol,Int}(
    :reads => 0, :computes => 0, :invalidations => 0, :writes => 0,
    :read_time => 0, :evaluate_time => 0, :print_time => 0)

"""
    perf_counters() -> Dict{Symbol,Int}

Return a copy of the performance counters dictionary. The counters track:
- `:reads` — number of cell reads
- `:computes` — number of cell re-computations
- `:invalidations` — number of cell invalidations
- `:writes` — number of cell writes
- `:read_time` — nanoseconds spent in the editor's read stage
- `:evaluate_time` — nanoseconds spent in the editor's evaluate stage
- `:print_time` — nanoseconds spent in the editor's print stage
"""
perf_counters() = copy(_perf)

"""
    perf_reset!()

Reset all performance counters to zero.
"""
function perf_reset!()
    for k in keys(_perf); _perf[k] = 0; end
end

"""
    perf_record!(key::Symbol, value::Integer)

Add `value` to the counter at `key`, creating it if absent. Used to fold in
externally measured quantities (e.g. per-stage timings) alongside the
reactive engine's own counters.
"""
function perf_record!(key::Symbol, value::Integer)
    _perf[key] = get(_perf, key, 0) + Int(value)
end

"""
    @perf_time key expr

Evaluate `expr`, record the elapsed nanoseconds under `key` via
`perf_record!`, and return the value of `expr`.
"""
macro perf_time(key, expr)
    quote
        local t = time_ns()
        local result = $(esc(expr))
        perf_record!($(esc(key)), time_ns() - t)
        result
    end
end

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
        c.value = c.thunk()
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
    setval!(c, value)

Equivalent to `c[] = value`. Turns `c` into a primitive cell.
"""
setval!(c::Cell, value) = (c[] = value)

"""
    setfn!(c, thunk::Function)

Turn `c` into a computed cell. `thunk` is a zero-argument function that
will be called lazily. Previous value is discarded and dependents are
invalidated immediately.
"""
function setfn!(c::Cell, thunk::Function)
    _detach_upstream!(c)
    c.thunk = thunk
    c.value = nothing
    c.valid = false
    _invalidate_dependents!(c)
    return c
end

"""Return `true` if the cached value is up to date."""
isuptodate(c::Cell) = c.valid
isuptodate(cs::Vector{Cell}) = all(c -> c.valid, cs)

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
    # value is shown in the same IOContext — this keeps the document `show`
    # depth limit (`:document_depth`) effective across Cell-wrapped subtrees.
    c.valid ? show(io, c.value) : print(io, "<invalid>")
    print(io, ")")
end

end # module
