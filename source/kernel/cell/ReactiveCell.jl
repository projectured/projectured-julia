# Fragment of `CellModule` — the pull-based reactive kind and its engine.
# `AbstractCell` is already in scope. This is the only cell kind that touches the
# performance counters, so it pulls in the bump macro.
using ..PerformanceModule

"""
    ReactiveCell{T}   (alias: `Cell`; `Cell(v)` ≡ `ReactiveCell{Any}(v)`)

A box that holds a value, or a computation of one that runs when the value is
read.

Use it to keep a value that others depend on: a cell remembers who read it, so
a write tells them, and each of them computes again the next time it is read.
Nothing recomputes until it is read, and nothing recomputes that did not depend
on what changed. Every field of a document is one of these, which is how an
edit redraws the part of the screen it touched and no more.

# Example

    width = Cell(80)
    label = ComputedCell(() -> "the width is " * string(width[]))
    label[]            # "the width is 80"
    width[] = 120
    label[]            # "the width is 120", computed again on this read

See also `set_cell_function!` and `set_cell_value!`, which change what a cell
holds; `ImmutableCell` and `MutableCell`, which hold a value and tell nobody;
and the guide `kernel/cell`.

# Construction

    Cell(value)                       # untyped primitive cell (T = Any)
    ComputedCell(f)                   # untyped computed cell – f is the thunk (zero args)
    ReactiveCell{T}(value)            # typed primitive cell (type-stable reads)
    ReactiveCell{T}(Computed(f))      # typed computed cell (f is the thunk)

# Reading and writing

    c[]           # read (triggers computation if invalid)
    c[] = v       # set a primitive value, invalidating dependents
    c[] = Computed(f)         # switch to a computed cell with thunk `f`
    set_cell_function!(c, f)  # switch to a computed cell with thunk `f`
    set_cell_value!(c, v) # switch to a primitive cell with value `v`
"""
mutable struct ReactiveCell{T} <: AbstractCell{T}
    value::T
    thunk::Union{Nothing, Function}
    valid::Bool
    # Upstream (cells I read, STRONG) and downstream (cells that read me, WEAK)
    # edges, allocated LAZILY — `nothing` until the first edge forms. The
    # overwhelming majority of cells are primitive leaves that read nothing and,
    # until a projection observes them, are read by nothing; the eager empty `Set` +
    # `Vector` was ~90% of a ReactiveCell's construction cost (measured ~168 B vs a
    # MutableCell's 24 B). Every access below treats `nothing` as empty, and
    # `_get_dependencies!` / `_get_dependents!` allocate on demand.
    dependencies::Union{Nothing, Set{ReactiveCell}}       # cells I read from  (upstream, STRONG)
    dependents::Union{Nothing, Vector{WeakRef}}   # cells that read me  (downstream, WEAK)

    ReactiveCell{T}(value) where {T} =
        new{T}(value, nothing, true, nothing, nothing)
    # A `Computed` argument carries the cell's *thunk*: `value` starts *undefined* (a
    # typed field cannot hold a placeholder) and `valid = false` guarantees
    # `_recompute!` assigns it before any read returns.
    function ReactiveCell{T}(computed::Computed) where {T}
        c = new{T}()
        c.thunk = computed.thunk
        c.valid = false
        c.dependencies = nothing
        c.dependents = nothing
        return c
    end
    # A `Function` needs no method of its own: it is a value like any other, and the
    # constructor above stores it. Only a `Computed` argument makes a cell compute.
end

# Lazily allocate the edge containers on first use. A cell that never reads another
# keeps `deps === nothing`; one never read inside a computation keeps
# `dependents === nothing` — and pays for neither.
#
# `@nospecialize` ON THE CELL, because the cell that arrives here is often a
# `ReactiveCell{T} where T` and not one concrete cell: `deps` is a
# `Set{ReactiveCell}` and the computing stack a `Vector{ReactiveCell}`, so
# whatever comes out of either carries a free parameter. Neither body reads `T`,
# so one compiled body serves every cell — and a free parameter is the one shape
# an ahead-of-time build cannot enumerate, which is what made these calls
# unresolvable and put them in a seal file.
@inline _get_dependencies!(@nospecialize(c::ReactiveCell)) =
    (d = c.dependencies; d === nothing ? (c.dependencies = Set{ReactiveCell}()) : d)
@inline _get_dependents!(@nospecialize(c::ReactiveCell)) =
    (d = c.dependents; d === nothing ? (c.dependents = WeakRef[]) : d)

"""
    Cell(value)

A reactive cell that holds a value of any type: the name almost every caller
writes.

Use it to make one field, one parameter or one result reactive without saying
what type it holds. `Cell(3)` holds a number, `Cell("a")` a string, and
`ComputedCell(f)` a computation. A cell of a stated type, which reads without a
conversion, is `ReactiveCell{T}`.

# Example

    jobs = Cell(4)
    jobs[] = 8         # everything that read `jobs` computes again when read

See also `ReactiveCell`, which this names, and `set_cell_function!`.

`Cell` is a `const` alias for the **concrete** `ReactiveCell{Any}` — the untyped
reactive cell. It is deliberately concrete (not an abstract alias) so
`Vector{Cell}`, `Set{Cell}` and `::Cell` struct fields stay concretely typed,
which dispatch across the machinery depends on. Code that means "a cell of any
kind" tests `isa AbstractCell`; code that means "a reactive cell of any value
type" tests `isa ReactiveCell`.
"""
const Cell = ReactiveCell{Any}

"""
    ComputedCell(f) -> Cell

A cell whose value is computed by `f`, the first time it is read and after
anything it read has changed.

Use it to state a derived value where it belongs, beside the thing that has it,
instead of computing it again at every place that needs it. `f` takes no
argument. A cell of a stated type is `ReactiveCell{T}(Computed(f))`.

# Example

    rows = Cell(["a", "b"])
    count = ComputedCell(() -> length(rows[]))
    count[]            # 2

See also `Cell`, which holds a value, and `set_cell_function!`, which turns one
into the other.
"""
ComputedCell(f::Function) = ReactiveCell{Any}(Computed(f))

# ── per-task tracking stack ────────────────────────────────────────────────
# While a ReactiveCell's thunk is running, that cell sits on the current task's
# stack so any ReactiveCell read during evaluation can register itself as a
# dependency. The stack is task-local, not a module global: concurrent
# evaluations (e.g. separate editors on separate tasks) each get their own, so
# their dependency tracking never crosses.
_get_computing_stack() =
    get!(() -> ReactiveCell[], task_local_storage(),
         :projectured_reactive_computing)::Vector{ReactiveCell}

# The reactive hot path bumps the performance counters via `@count_performance`
# (imported at the top of this file). The macro lives in `PerformanceModule`
# (cell/PerformanceCounter.jl); it expands to a bump into the task-local counter
# store when counting is compiled in, and to `nothing` when it is not — so these
# call sites cost nothing in a normal build.

# ── reading ──────────────────────────────────────────────────────────────

function Base.getindex(c::ReactiveCell)
    @count_performance :reads
    # register dependency if inside a computation
    stack = _get_computing_stack()
    if !isempty(stack)
        observer = stack[end]
        if observer !== c
            _register_dependent!(c, observer)
            push!(_get_dependencies!(observer), c)
        end
    end
    if !c.valid
        _recompute!(c)
    end
    return c.value
end

# Run the thunk of a computed cell. A thunk that calls a method newer than the
# world of the task that reads it throws a `MethodError`, so the thunk then runs
# once more through `Base.invokelatest`. The retry happens only in an older world.
# Code inside `invokelatest` runs in the latest world, so a nested cell does not
# retry, and a real `MethodError` runs each thunk of a chain once. A thunk is pure,
# so a second run is safe.
function _force_thunk(@nospecialize(f))
    try
        return f()
    catch exception
        is_older_world = Base.tls_world_age() < Base.get_world_counter()
        exception isa MethodError && is_older_world || rethrow()
        return Base.invokelatest(f)
    end
end

function _recompute!(c::ReactiveCell)
    if c.thunk === nothing
        c.valid = true
        return
    end
    _detach_upstream!(c)
    stack = _get_computing_stack()
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

function _invalidate_dependents!(c::ReactiveCell)
    ds = c.dependents
    ds === nothing && return
    for i in eachindex(ds)
        d = ds[i].value
        d === nothing && continue      # reader already collected — nothing to invalidate
        dd = d::ReactiveCell
        if dd.valid
            dd.valid = false
            @count_performance :invalidations
            _invalidate_dependents!(dd)
        end
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
    set_cell_value!(c, value)

Put a value into a cell, and let everything that read it know.

Use it to write a cell that held a computation and must now hold a value, or to
write one from code that reads better with a verb than with `c[] = value`,
which does the same. Everything that read the cell computes again on its next
read.

# Example

    width = ComputedCell(() -> 2 * margin[])
    set_cell_value!(width, 80)      # a number now, and no computation

See also `set_cell_function!`, for the other direction, and `unwrap_cell`.
"""
set_cell_value!(c::ReactiveCell, value) = (c[] = value)

"""
    set_cell_function!(c, thunk::Function)

Make a cell compute its value, instead of holding one.

Use it to derive one value from others after the thing that holds it was built:
a title that follows a name, a width that follows a margin, a list that follows
a filter. `thunk` takes no argument and is called on the first read after a
write, not before; every cell it reads becomes one the cell depends on.

# Example

    total = Cell(0)
    set_cell_function!(total, () -> length(rows[]))
    total[]            # counted now, and again after `rows` changes

Dependents are invalidated immediately. The previous value stays cached in the
(now invalid) cell until the first read replaces it — a typed cell cannot hold a
`nothing` placeholder; when `T` admits `nothing` the value is cleared eagerly so
the old object is released.

See also `set_cell_value!`, for the other direction, `ComputedCell`, which
builds such a cell, and the guide `kernel/cell`.
"""
function set_cell_function!(c::ReactiveCell{T}, thunk::Function) where {T}
    _detach_upstream!(c)
    c.thunk = thunk
    nothing isa T && (c.value = nothing)
    c.valid = false
    _invalidate_dependents!(c)
    return c
end

"""
    c[] = Computed(f)

Write syntax for [`set_cell_function!`](@ref) — the counterpart of `c[] = value`,
so a single write path reaches both a value and a computation.
"""
function Base.setindex!(c::ReactiveCell, computed::Computed)
    set_cell_function!(c, computed.thunk)
    return computed
end

is_cell_up_to_date(c::ReactiveCell) = c.valid

# ── untracked read ─────────────────────────────────────────────────────────

"""
    peek(c::ReactiveCell)

Read a cell without becoming one of the things it tells.

Use it to look at a value from inside a computation that must not depend on it:
a counter, a clock, a cache of the last answer. An ordinary read, `c[]`, makes
the computation depend on the cell; this one does not.

# Example

    drawn = ComputedCell(() -> begin
        count = peek(frames)        # looked at, not depended on
        "frame " * string(count) * " of " * title[]
    end)

See also `Cell` and the guide `kernel/cell`.

Read a cell's value **without** registering a dependency (an untracked read).
Unlike `c[]`, calling this inside a computed thunk does not make the thunk a
dependent of `c`. A generic reactive primitive (cf. Solid's `untrack`, MobX's
`untracked`) — for callers that want to *sample* a cell's current value rather
than subscribe to it.
"""
function Base.peek(c::ReactiveCell)
    c.valid || _recompute!(c)
    return c.value
end

# ── helpers ──────────────────────────────────────────────────────────────

function _detach_upstream!(c::ReactiveCell)
    c.dependencies === nothing && return
    for dependency in c.dependencies
        _unregister_dependent!(dependency, c)
    end
    empty!(c.dependencies)
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

# `@nospecialize` on both: `observer` reaches here from the computing stack and
# `c` from another cell's `deps`, and both of those hold `ReactiveCell` with a
# free parameter. The body walks a `Vector{WeakRef}` and compares with `===`; it
# never reads `T`.
function _register_dependent!(@nospecialize(c::ReactiveCell),
                              @nospecialize(observer::ReactiveCell))
    ds = _get_dependents!(c)
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

# The mirror of `_register_dependent!`, and `c` is the one that arrives with a
# free parameter here: `recompute!` iterates `c.deps`, a `Set{ReactiveCell}`.
function _unregister_dependent!(@nospecialize(c::ReactiveCell),
                                @nospecialize(observer::ReactiveCell))
    ds = c.dependents
    ds === nothing && return nothing
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
