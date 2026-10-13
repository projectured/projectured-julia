# Fragment of `CellModule` — the pull-based reactive kind and its engine: the read
# that records its reader, the write that invalidates the readers, and the
# computation that runs on the next read. The engine counts its reads, computes,
# invalidations and writes with `@count_performance`.

# The state of a reactive cell. A cell that is not valid computes at its next
# read. A failed cell is one whose last computation threw: it computes at its next read,
# and the walk of a write goes on through it, because a reader that caught its exception
# can be valid. A computing cell is on the stack of a computation, and the walk of
# a write stops at it: one task writes and reads a set of cells, so a write that
# reaches a computing cell comes from inside its computation, which writes only a cell
# that it made in the same run. A read of a computing cell on the task that computes
# it is a cycle.
@enum _CellState::UInt8 begin
    _VALID
    _INVALID
    _FAILED
    _COMPUTING
end

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

    c[]                             # read, and compute first if not valid
    c[] = value                     # hold `value`, and invalidate the readers
    c[] = @computation expr         # compute `expr`, and invalidate the readers
    set_cell_value!(c, value)       # the same as `c[] = value`
    set_cell_computation!(c, f)     # the same as `c[] = Computation(f)`
"""
mutable struct ReactiveCell{T} <: AbstractCell{T}
    value::T
    computation::Union{Nothing, Function}
    state::_CellState
    # The cells that the last computation read. The edges are strong, so a cell
    # keeps alive the cells that it computes from.
    dependencies::Union{Nothing, Set{ReactiveCell}}
    # The cells that read this one. The edges are weak, so a cell does not keep
    # its readers alive.
    dependents::Union{Nothing, Vector{WeakRef}}

    ReactiveCell{T}(value) where {T} =
        new{T}(value, nothing, _VALID, nothing, nothing)
    # With a `Computation`, `value` holds `nothing` when `T` admits it, as after
    # `set_cell_computation!`. For another `T`, `value` stays undefined, because the
    # field can not hold a placeholder. An invalid cell makes `_recompute!` assign
    # it before any read returns.
    function ReactiveCell{T}(marker::Computation) where {T}
        c = new{T}()
        nothing isa T && (c.value = nothing)
        c.computation = marker.computation
        c.state = _INVALID
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
    run_without_cell_tracking(f)

Run `f` so that no read inside it records a reader. A cell that computes inside
`f` puts itself on the stack, so it still records its own dependencies.

Use it to read cells from inside a computation that must not depend on them, when
`f` reads more than one cell, or reads them in code that it calls. For one cell,
`peek` does the same. `UntrackedCell` runs its computation with it.

The function puts an empty stack in place of the stack of the task while `f`
runs, and puts the stack back after `f` returns or throws.

# Example

    suffix() = " (" * string(count[]) * ")"
    label = Cell(@computation title[] * run_without_cell_tracking(suffix))

See also `peek`, the untracked read of one cell, and `UntrackedCell`.
"""
function run_without_cell_tracking(f)
    stack = _get_computing_stack()
    isempty(stack) && return f()                 # no reader: nothing to stop
    storage = task_local_storage()
    set_aside = _get_set_aside_stacks()
    push!(set_aside, stack)
    storage[:projectured_reactive_computing] = ReactiveCell[]
    try
        return f()
    finally
        storage[:projectured_reactive_computing] = stack
        pop!(set_aside)
    end
end

# The stacks that `run_without_cell_tracking` set aside on this task, the innermost
# last. A cycle can pass through them, so the check of a cycle searches them too.
_get_set_aside_stacks() =
    get!(() -> Vector{ReactiveCell}[], task_local_storage(),
         :projectured_reactive_set_aside)::Vector{Vector{ReactiveCell}}

# ── a cycle ──────────────────────────────────────────────────────────────────

"""
    CellCycleException(cell)

The exception of a reactive cell whose computation read the cell itself, directly or
through other cells.

It is an ordinary exception, so a barrier records it as a fault and the editor goes
on. Each cell of the cycle is failed, and computes again at its next read; a write
that breaks the cycle reaches the readers of the cycle. The check finds a cycle also
through `run_without_cell_tracking` and an `UntrackedCell`.

Use it to tell a cycle from another fault in a catch, or in a test of a computation
that could read itself.

# Example

    a = Cell(0); b = Cell(@computation a[] + 1)
    a[] = @computation b[] + 1
    a[]                             # throws a CellCycleException

See also `ReactiveCell`.
"""
struct CellCycleException <: Exception
    cell::ReactiveCell
end

function Base.showerror(io::IO, exception::CellCycleException)
    T = get_cell_value_type(exception.cell)
    kind = T === Any ? "Cell" : "ReactiveCell{$(T)}"
    print(io, "a ", kind, " read itself while it computed")
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
    c.state === _VALID || _recompute!(c)
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
        c.state = _VALID
        return
    end
    stack = _get_computing_stack()
    c.state === _COMPUTING && _is_computing_on_this_task(c, stack) &&
        throw(CellCycleException(c))
    _detach_upstream!(c)
    @count_performance :computes
    push!(stack, c)
    c.state = _COMPUTING
    value = try
        _run_computation(c.computation)
    catch
        c.state = _FAILED
        rethrow()
    finally
        pop!(stack)
    end
    # Only a run that still finds the cell computing stores its value. A write or a
    # new computation inside the run changed the state, and its answer stands.
    if c.state === _COMPUTING
        c.value = value
        c.state = _VALID
    elseif !isdefined(c, :value)
        c.value = value
    end
end

# Whether `c` computes on this task: on its stack, or on a stack that
# `run_without_cell_tracking` set aside.
function _is_computing_on_this_task(@nospecialize(c::ReactiveCell), stack)
    _is_on_stack(c, stack) && return true
    any(aside -> _is_on_stack(c, aside), _get_set_aside_stacks())
end

function _is_on_stack(@nospecialize(c::ReactiveCell), stack::Vector{ReactiveCell})
    for i in lastindex(stack):-1:firstindex(stack)
        stack[i] === c && return true
    end
    false
end

# ── invalidation ─────────────────────────────────────────────────────────────

# Mark every reader of `c` invalid, then the readers of each, and so on, by the
# rules of `_CellState`: an invalid or computing reader stops the walk, and a failed
# reader does not. A reader comes out of `dependents` as a `ReactiveCell` with a free
# `T`, so `@nospecialize` gives the walk one compiled body, which calls itself with no
# dispatch at run time.
function _invalidate_dependents!(@nospecialize(c::ReactiveCell))
    ds = c.dependents
    ds === nothing && return
    for i in eachindex(ds)
        d = ds[i].value
        d === nothing && continue      # the reader was collected
        dd = d::ReactiveCell
        state = dd.state
        state === _VALID || state === _FAILED || continue
        dd.state = _INVALID
        @count_performance :invalidations
        _invalidate_dependents!(dd)
    end
end

# ── write ────────────────────────────────────────────────────────────────────

"""
    c[] = value

Make `c` hold `value`, and invalidate every cell that reads `c`, and the cells
that read those. If `c` held a computation, it holds `value` in its place. A value
that does not convert to the value type of `c` throws, and `c` stays as it was.

A write of plain data that is `===` to the value that `c` holds, when `c` holds no
computation, invalidates nothing. Plain data is a value that is `isbits`, a
`String` or a `Symbol`: it can not change inside, so no reader can tell the write
from no write. A write of the same mutable value still invalidates the readers,
and `invalidate_cell!` makes them compute again with no write.
"""
function Base.setindex!(c::ReactiveCell{T}, value) where {T}
    converted = convert(T, value)
    @count_performance :writes
    _is_same_plain_value(c, converted) && return value
    _detach_upstream!(c)
    c.computation = nothing
    c.value = converted
    c.state = _VALID
    _invalidate_dependents!(c)
    return value
end

# Whether `c` holds no computation and holds `value` already as plain data, which
# can not change inside, so that a write of it changes nothing that a reader sees.
_is_same_plain_value(c::ReactiveCell, value) =
    c.computation === nothing && isdefined(c, :value) && _is_plain_value(value) &&
    c.value === value

_is_plain_value(value) = isbits(value) || value isa Union{String,Symbol}

function invalidate_cell!(c::ReactiveCell)
    if c.computation !== nothing && (c.state === _VALID || c.state === _FAILED)
        c.state = _INVALID
        @count_performance :invalidations
    end
    _invalidate_dependents!(c)
    nothing
end

"""
    set_cell_value!(c, value)

Put a value into a cell, and invalidate every cell that read it.

Use it to write a cell that held a computation and must now hold a value, or to
write one from code that reads better with a verb than with `c[] = value`,
which does the same. Everything that read the cell computes again on its next
read, unless the write is of the same plain data that the cell holds.

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
    c.state = _INVALID
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

is_cell_valid(c::ReactiveCell) = c.state === _VALID

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
    c.state === _VALID || _recompute!(c)
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
    c.state === _VALID ? show(io, c.value) : print(io, "<invalid>")
    print(io, ")")
end
