# Fragment of `CellModule` — the pull-based reactive kind and its engine: the read
# that records its reader, the write that invalidates the readers, and the
# computation that runs on the next read. The engine counts its reads, computes,
# invalidations and writes with `@count_performance`.

"""
    ReactiveCell{T}

A box that holds a value, or a computation of one that runs when the value is
read.

Use it to keep a value that others depend on: a cell records the cells that read
it, and a write invalidates them, so each of them computes again the next time
it is read.
Nothing recomputes until it is read, and nothing recomputes that did not depend
on what changed. A struct of cells keeps its fields in these unless its
declaration names another kind, so a write to one field invalidates only the
computations that read that field.

# Example

    width = Cell(80)
    label = Cell(@computation "the width is " * string(width[]))
    label[]            # "the width is 80"
    width[] = 120
    label[]            # "the width is 120", computed again on this read

See also `set_cell_computation!` and `set_cell_value!`, which change what a cell
holds; `ImmutableCell` and `MutableCell`, which hold a value and record no
reader; and the guide `kernel/cell`.

# Construction

    Cell(value)                          # an untyped cell that holds `value`
    Cell(@computation expr)              # an untyped cell that computes `expr`
    ReactiveCell{T}(value)               # a typed cell that holds `value`
    ReactiveCell{T}(@computation expr)   # a typed cell that computes `expr`

`Cell` is `ReactiveCell{Any}`. A typed cell reads its value with no conversion.

# Read and write

    c[]                             # read, and compute first if the cell is invalid
    c[] = value                     # hold `value`, and invalidate the readers
    c[] = @computation expr         # compute `expr`, and invalidate the readers
    set_cell_value!(c, value)       # the same as `c[] = value`
    set_cell_computation!(c, f)     # the same as `c[] = Computation(f)`
"""
mutable struct ReactiveCell{T} <: AbstractCell{T}
    value::T
    computation::Union{Nothing, Function}
    valid::Bool
    # The cells that the last computation read. The edges are strong, so a cell
    # keeps alive the cells that it computes from.
    dependencies::Union{Nothing, Set{ReactiveCell}}
    # The cells that read this one. The edges are weak, so a cell does not keep
    # its readers alive.
    dependents::Union{Nothing, Vector{WeakRef}}

    ReactiveCell{T}(value) where {T} =
        new{T}(value, nothing, true, nothing, nothing)
    # With a `Computation`, `value` holds `nothing` when `T` admits it, as after
    # `set_cell_computation!`. For another `T`, `value` stays undefined, because the
    # field can not hold a placeholder. `valid = false` makes `_recompute!` assign
    # it before any read returns.
    function ReactiveCell{T}(marker::Computation) where {T}
        c = new{T}()
        nothing isa T && (c.value = nothing)
        c.computation = marker.computation
        c.valid = false
        c.dependencies = nothing
        c.dependents = nothing
        return c
    end
    # A `Function` needs no method of its own: it is a value like any other, and the
    # constructor above stores it. Only a `Computation` makes a cell compute.
end

# Both edge sets are `nothing` until the first edge forms, and these two make them
# on first use. Most cells are values that read nothing, and a cell has no reader
# until a computation reads it. An empty `Set` and an empty `Vector` in every
# cell would be about 90% of the cost to make one: about 168 bytes, against 24
# bytes for a `MutableCell`.
#
# `@nospecialize` is on the cell, because the cell that arrives here is often a
# `ReactiveCell{T} where T`: it comes out of `dependencies`, a
# `Set{ReactiveCell}`, or out of the computing stack, a `Vector{ReactiveCell}`.
# Neither body reads `T`, so one compiled body serves every cell. An ahead-of-time
# build can not enumerate a free parameter, so a body specialized on `T` would
# leave these calls unresolved.
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
`Cell(@computation expr)` a computation. A cell of a stated type, which reads without
a conversion, is `ReactiveCell{T}`.

# Example

    jobs = Cell(4)
    jobs[] = 8         # everything that read `jobs` computes again when read

See also `ReactiveCell`, which this names, and `@computation`.

`Cell` is a `const` alias for the **concrete** type `ReactiveCell{Any}`. It is
concrete and not abstract, so `Vector{Cell}`, `Set{Cell}` and a field of type
`Cell` stay concrete, and dispatch depends on that. To test for a cell of any
kind, test `isa AbstractCell`. To test for a reactive cell of any value type,
test `isa ReactiveCell`.
"""
const Cell = ReactiveCell{Any}

# ── the computing stack ──────────────────────────────────────────────────────

# The cells whose computations run now on this task, the innermost last. A read records
# the innermost cell as its reader. The stack is task-local, so two evaluations on
# two tasks never record a reader for each other.
_get_computing_stack() =
    get!(() -> ReactiveCell[], task_local_storage(),
         :projectured_reactive_computing)::Vector{ReactiveCell}

"""
    run_untracked(f)

Run `f` so that no read inside it records a reader. A cell that computes inside
`f` puts itself on the stack, so it still records its own dependencies.

Use it to read cells from inside a computation that must not depend on them, when
`f` reads more than one cell, or reads them in code that it calls. For one cell,
`peek` does the same. `UntrackedCell` runs its computation with it.

The function puts an empty stack in place of the stack of the task while `f`
runs, and puts the stack back after `f` returns or throws.
"""
function run_untracked(f)
    stack = _get_computing_stack()
    isempty(stack) && return f()                 # no reader: nothing to stop
    storage = task_local_storage()
    storage[:projectured_reactive_computing] = ReactiveCell[]
    try
        return f()
    finally
        storage[:projectured_reactive_computing] = stack
    end
end

# ── read ─────────────────────────────────────────────────────────────────────

function Base.getindex(c::ReactiveCell)
    @count_performance :reads
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

# Run the computation of a cell. A computation that calls a method newer than the
# world of the task that reads it throws a `MethodError`, so the computation then
# runs once more through `Base.invokelatest`. The retry happens only in an older
# world. Code inside `invokelatest` runs in the latest world, so a nested cell does
# not retry, and a real `MethodError` runs each computation of a chain once. A
# computation is pure, so a second run is safe.
function _run_computation(@nospecialize(f))
    try
        return f()
    catch exception
        is_older_world = Base.tls_world_age() < Base.get_world_counter()
        exception isa MethodError && is_older_world || rethrow()
        return Base.invokelatest(f)
    end
end

function _recompute!(c::ReactiveCell)
    if c.computation === nothing
        c.valid = true
        return
    end
    _detach_upstream!(c)
    stack = _get_computing_stack()
    @count_performance :computes
    push!(stack, c)
    try
        c.value = _run_computation(c.computation)
    finally
        pop!(stack)
    end
    c.valid = true
end

# ── invalidation ─────────────────────────────────────────────────────────────

# Mark every valid reader of `c` invalid, then the readers of each, and so on. A
# reader that is invalid already stops the walk: its own readers became invalid
# with it.
function _invalidate_dependents!(c::ReactiveCell)
    ds = c.dependents
    ds === nothing && return
    for i in eachindex(ds)
        d = ds[i].value
        d === nothing && continue      # the reader was collected
        dd = d::ReactiveCell
        if dd.valid
            dd.valid = false
            @count_performance :invalidations
            _invalidate_dependents!(dd)
        end
    end
end

# ── write ────────────────────────────────────────────────────────────────────

"""
    c[] = value

Make `c` hold `value`, and invalidate every cell that reads `c`, and the cells
that read those. If `c` held a computation, it holds `value` in its place. A value
that does not convert to the value type of `c` throws, and `c` stays as it was.
"""
function Base.setindex!(c::ReactiveCell{T}, value) where {T}
    converted = convert(T, value)
    @count_performance :writes
    _detach_upstream!(c)
    c.computation = nothing
    c.value = converted
    c.valid = true
    _invalidate_dependents!(c)
    return value
end

"""
    set_cell_value!(c, value)

Put a value into a cell, and invalidate every cell that read it.

Use it to write a cell that held a computation and must now hold a value, or to
write one from code that reads better with a verb than with `c[] = value`,
which does the same. Everything that read the cell computes again on its next
read.

# Example

    width = Cell(@computation 2 * margin[])
    set_cell_value!(width, 80)      # a number now, and no computation

See also `set_cell_computation!`, for the other direction, and `unwrap_cell`.
"""
set_cell_value!(c::ReactiveCell, value) = (c[] = value)

"""
    set_cell_computation!(c, computation::Function)

Make a cell compute its value, instead of holding one.

Use it to derive one value from others after the thing that holds it was built:
a title that follows a name, a width that follows a margin, a list that follows
a filter. `computation` takes no argument, and it runs on the first read after
the write, not before. Every cell that it reads becomes a cell that `c`
depends on. For an expression, `c[] = @computation expr` does the same.

# Example

    total = Cell(0)
    set_cell_computation!(total, () -> length(rows[]))
    total[]            # counted now, and again after `rows` changes

The call invalidates the dependents at once. The cell keeps its old value until
the first read replaces it, because a typed cell can not hold `nothing` as a
placeholder. When `T` admits `nothing`, the call clears the value at once, so
the old object can be collected.

See also `set_cell_value!`, for the other direction, `@computation`, which makes
the computation of an expression, and the guide `kernel/cell`.
"""
function set_cell_computation!(c::ReactiveCell{T}, computation::Function) where {T}
    _detach_upstream!(c)
    c.computation = _capture_fault_scope(computation)
    nothing isa T && (c.value = nothing)
    c.valid = false
    _invalidate_dependents!(c)
    return c
end

"""
    c[] = Computation(f)
    c[] = @computation expr

The write syntax for [`set_cell_computation!`](@ref). With `c[] = value` beside
it, one write syntax gives a cell either a value or a computation.
"""
function Base.setindex!(c::ReactiveCell, marker::Computation)
    set_cell_computation!(c, marker.computation)
    return marker
end

is_cell_up_to_date(c::ReactiveCell) = c.valid

# ── untracked read ───────────────────────────────────────────────────────────

"""
    peek(c::ReactiveCell)

Read a cell, and record no dependency on it.

Use it to look at a value from inside a computation that must not depend on it:
a counter, a clock, a cache of the last answer. An ordinary read, `c[]`, makes
the computation depend on the cell; this one does not.

# Example

    drawn = Cell(@computation begin
        count = peek(frames)        # looked at, not depended on
        "frame " * string(count) * " of " * title[]
    end)

See also `Cell` and the guide `kernel/cell`.
"""
function Base.peek(c::ReactiveCell)
    c.valid || _recompute!(c)
    return c.value
end

# ── the upstream edge ────────────────────────────────────────────────────────

function _detach_upstream!(c::ReactiveCell)
    c.dependencies === nothing && return
    for dependency in c.dependencies
        _unregister_dependent!(dependency, c)
    end
    empty!(c.dependencies)
end

# ── the downstream edge ──────────────────────────────────────────────────────
#
# `dependents` carries invalidation down to the readers, and it must not keep a
# reader alive, so it holds `WeakRef`s. With strong edges, a cell would keep alive
# every cell that ever read it, also a computed cell that no other object holds
# any more. A reader removes its edges only when it computes again or is written,
# and a cell that nothing holds never does either.
#
# The edges are in a `Vector`, which a linear scan by identity searches, and not
# in a hash set, because the set is small. Across a live pipeline the mean size is
# 0.85, the median 1, the 99th percentile 3 and the largest 40, and one cell in
# 4173 has more than 16. Against a `Set`, the vector is about 3 times faster to
# register a reader, 1.4 times faster to detach one and 4 to 10 times faster to
# invalidate. A `WeakKeyDict` is 7 times slower than the `Set`, because its lock
# costs the most. The measurements are in plan/done/reactive-dependents-leak.md.
#
# Both helpers remove the entries of collected readers in the scan that they do
# anyway, so dead `WeakRef`s do not collect in the vector.

# `@nospecialize` on both: `observer` comes from the computing stack and `c` from
# the `dependencies` of another cell, and both of those hold `ReactiveCell` with a
# free parameter. The body walks a `Vector{WeakRef}` and compares with `===`; it
# never reads `T`.
function _register_dependent!(@nospecialize(c::ReactiveCell),
                              @nospecialize(observer::ReactiveCell))
    ds = _get_dependents!(c)
    i, n = 1, length(ds)
    @inbounds while i <= n
        v = ds[i].value
        if v === nothing
            # The reader was collected: move the last entry here, and look at
            # slot `i` again.
            ds[i] = ds[n]; pop!(ds); n -= 1
        elseif v === observer
            return nothing                      # already registered
        else
            i += 1
        end
    end
    push!(ds, WeakRef(observer))
    return nothing
end

# The mirror of `_register_dependent!`. Here `c` is the one with a free
# parameter: `_detach_upstream!` takes it out of `dependencies`, a
# `Set{ReactiveCell}`.
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

# ── display ──────────────────────────────────────────────────────────────────

function Base.show(io::IO, c::ReactiveCell{T}) where {T}
    kind = c.computation === nothing ? "value" : "computation"
    # `Cell` is the name of `ReactiveCell{Any}`, so only a typed cell shows its type.
    T === Any ? print(io, "Cell(") : print(io, "ReactiveCell{", T, "}(")
    print(io, kind, ", ")
    # The value is shown into the same `io`, not through `repr`, which makes a new
    # buffer. So the depth and limit keys that a caller set on `io` still hold
    # inside a value in a cell.
    c.valid ? show(io, c.value) : print(io, "<invalid>")
    print(io, ")")
end
