# Fragment of `CellModule` — the pull-based reactive kind and its engine: the read
# that records its reader, the write that invalidates the readers, and the
# computation that runs on the next read. The engine counts its reads, computes,
# invalidations, writes, checks and stops with `@count_performance`.

# The state of a reactive cell. A cell that is not valid computes at its next
# read. A failed cell is one whose last computation threw: it computes at its next read,
# and the walk of a write goes on through it, because a reader that caught its exception
# can be valid. A computing cell is on the stack of a computation, and the walk of
# a write stops at it: one task writes and reads a set of cells, so a write that
# reaches a computing cell comes from inside its computation, which writes only a cell
# that it made in the same run. A read of a computing cell is a cycle, for the same
# reason: it comes from inside the computation, or from a task that it waits for.
#
# A cell below the direct readers of a write is maybe invalid: a read first brings
# its dependencies up to date, and it computes only when one of them computed a new
# value. A cell is checking while its dependencies are brought up to date, and a
# read of a checking cell is a cycle, as a read of a computing cell is.
#
# Beside its state, a cell is provisional or final. A provisional value is valid,
# but a newer value comes later, such as the default of a value that a task still
# reads. A computation that reads a provisional cell is provisional itself, and a
# write of a value is final. The flag is no state of invalidation: a provisional
# cell is valid, and the walk of a write treats it as any valid cell.
@enum _CellState::UInt8 begin
    _VALID
    _INVALID
    _FAILED
    _COMPUTING
    _MAYBE_INVALID
    _CHECKING
end

"""
    ReactiveCell{T}

A box that holds a value, or a computation of one that runs when the value is
read.

Use it to keep a value that others depend on: a cell records the cells that read
it, and a write invalidates them, so each of them computes again the next time
it is read. Nothing recomputes until it is read, nothing recomputes that did not
depend on what changed, and a computation that gives the plain data that it gave
before, as provisional as before, leaves the cells that read it as they were.

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
    # Whether the value is provisional: the last computation read a provisional
    # cell, or marked itself provisional. The field fits beside `state`, so it does
    # not make a cell larger.
    is_provisional::Bool
    # The length of `dependents` after its last sweep of collected readers.
    swept_length::UInt32
    # The cells that the last computation read, in the order of the first read of
    # each. The edges are strong, so a cell keeps alive the cells that it computes
    # from. A check of a "maybe invalid" cell follows the order.
    dependencies::Union{Nothing, Vector{ReactiveCell}}
    # The cells that read this one. The edges are weak, so a cell does not keep
    # its readers alive.
    dependents::Union{Nothing, Vector{WeakRef}}

    ReactiveCell{T}(value) where {T} =
        new{T}(value, nothing, _VALID, false, UInt32(0), nothing, nothing)
    # With a `Computation`, `value` holds `nothing` when `T` admits it, as after
    # `set_cell_computation!`. For another `T`, `value` stays undefined, because the
    # field can not hold a placeholder. An invalid cell makes `_recompute!` assign
    # it before any read returns.
    function ReactiveCell{T}(marker::Computation) where {T}
        c = new{T}()
        nothing isa T && (c.value = nothing)
        c.computation = marker.computation
        c.state = _INVALID
        c.is_provisional = false
        c.swept_length = UInt32(0)
        c.dependencies = nothing
        c.dependents = nothing
        return c
    end
    # A `Function` needs no method of its own: it is a value like any other, and the
    # constructor above stores it. Only a `Computation` makes a cell compute.
end

# Both edge lists are `nothing` until the first edge forms, and these two make
# them on first use. Most cells are values that read nothing, and a cell has no
# reader until a computation reads it, so an empty list in every cell would be
# memory that most cells never use.
#
# `@nospecialize` is on the cell, because the cell that arrives here is often a
# `ReactiveCell{T} where T`: it comes out of `dependencies`, a
# `Vector{ReactiveCell}`, or out of the computing stack, another one.
# Neither body reads `T`, so one compiled body serves every cell. An ahead-of-time
# build can not enumerate a free parameter, so a body specialized on `T` would
# leave these calls unresolved.
@inline _get_dependencies!(@nospecialize(c::ReactiveCell)) =
    (d = c.dependencies; d === nothing ? (c.dependencies = ReactiveCell[]) : d)

# Put `c` after the dependencies that the run of `observer` read, unless it is the
# last of them. Answers whether it put it. A run that reads a cell again after
# another one leaves a repeat, which `_remove_repeated_dependencies!` takes out
# when the run ends.
@inline function _record_dependency!(@nospecialize(observer::ReactiveCell), @nospecialize(c::ReactiveCell))
    deps = _get_dependencies!(observer)
    n = length(deps)
    n > 0 && (@inbounds deps[n]) === c && return false
    push!(deps, c)
    true
end

# The count of dependencies up to which the end of a run finds a repeat by a scan,
# and past which it finds it with a set.
const _DEPENDENCY_SCAN_LIMIT = 32

# Keep the first of each cell in the dependencies of `c`, in their order.
function _remove_repeated_dependencies!(@nospecialize(c::ReactiveCell))
    deps = c.dependencies
    (deps === nothing || length(deps) < 2) && return nothing
    kept = 0
    if length(deps) <= _DEPENDENCY_SCAN_LIMIT
        @inbounds for i in eachindex(deps)
            d = deps[i]
            is_repeat = false
            for k in 1:kept
                deps[k] === d && (is_repeat = true; break)
            end
            is_repeat || (kept += 1; deps[kept] = d)
        end
    else
        seen = Base.IdSet{ReactiveCell}()
        @inbounds for i in eachindex(deps)
            d = deps[i]
            d in seen && continue
            push!(seen, d)
            kept += 1
            deps[kept] = d
        end
    end
    resize!(deps, kept)
    nothing
end
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
    storage[:projectured_reactive_computing] = ReactiveCell[]
    try
        return f()
    finally
        storage[:projectured_reactive_computing] = stack
    end
end

# ── a cycle ──────────────────────────────────────────────────────────────────

"""
    CellCycleException(cell)

The exception of a reactive cell whose computation read the cell itself, directly or
through other cells.

It is an ordinary exception, so a barrier records it as a fault and the editor goes
on. Each cell of the cycle is failed, and computes again at its next read; a write
that breaks the cycle reaches the readers of the cycle. The check finds a cycle also
through `run_without_cell_tracking`, an `UntrackedCell` and a task that the
computation waits for, because a read of a computing cell is always a cycle.

Use it to tell a cycle from another fault in a catch, or in a test of a computation
that could read itself. A cycle through a task that the computation waits for
reaches the catch inside the `TaskFailedException` of `fetch`, whose task holds the
`CellCycleException` as its result.

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
    observer = _record_read!(c)
    c.state === _VALID || _bring_up_to_date_for!(c, observer)
    # A reader of a provisional value is provisional too.
    c.is_provisional && observer !== nothing && (observer.is_provisional = true)
    return c.value
end

# Bring `c` up to date for a read by `observer`. A failure of `c` that a provisional
# value caused is provisional too, so a reader that catches it is provisional.
@noinline function _bring_up_to_date_for!(c::ReactiveCell, observer)
    try
        _bring_up_to_date!(c)
    catch
        c.is_provisional && observer !== nothing && (observer.is_provisional = true)
        rethrow()
    end
    nothing
end

# Record the innermost computation of this task as a reader of `c`, and answer it,
# or `nothing` when no computation runs or the computation reads its own cell.
@inline function _record_read!(c::ReactiveCell)
    stack = _get_computing_stack()
    isempty(stack) && return nothing
    observer = stack[end]
    observer === c && return nothing
    _record_dependency!(observer, c) && _register_dependent!(c, observer)
    observer
end

# Make a cell that is not valid valid: a maybe invalid cell checks its
# dependencies first, and every other cell computes. `in_check` says that the
# check of a reader asked for it, and not a read.
function _bring_up_to_date!(c::ReactiveCell, in_check::Bool = false)
    c.state === _MAYBE_INVALID && _check_dependencies!(c, in_check) && return nothing
    c.state === _CHECKING && throw(CellCycleException(c))
    _recompute!(c)
    nothing
end

# Bring each dependency of `c` up to date, in the order of the last run, and stop
# at the first one that computed a new value: that one made `c` invalid. Answers
# whether `c` is valid with no computation.
#
# A dependency that throws makes each checking cell on the path invalid, and the
# exception goes up to the check that a read started. That check answers `false`,
# so its cell computes: each cell below it computes once, the cell that threw
# computes once more, and each computation meets the exception and can catch it.
# An exception that is no fault, such as an interrupt, goes up through every check.
function _check_dependencies!(@nospecialize(c::ReactiveCell), in_check::Bool)
    @count_performance :checks
    c.state = _CHECKING
    deps = c.dependencies
    if deps !== nothing
        for i in eachindex(deps)
            d = @inbounds deps[i]
            d.state === _VALID && continue
            try
                _bring_up_to_date!(d, true)
            catch exception
                c.state === _CHECKING && (c.state = _INVALID)
                (in_check || !is_fault_exception(exception)) && rethrow()
                return false
            end
            c.state === _CHECKING || return false
        end
    end
    c.state === _CHECKING || return false
    c.state = _VALID
    true
end

# Run the computation of a cell. A computation that calls a method newer than the
# world of the task that reads it throws a `MethodError`, so the computation then
# runs once more through `Base.invokelatest`. The retry happens only in an older
# world. Code inside `invokelatest` runs in the latest world, so a cell that the
# retry computes does not retry again. A real `MethodError` read from an older world
# makes each cell of a chain retry the rest of the chain, so a chain of n cells runs
# about n²/2 computations before the error reaches the reader. A computation is
# pure, so the extra runs are safe.
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
    # One task writes and reads the cells, so a read of a computing cell comes from
    # inside its own computation: a cycle.
    c.state === _COMPUTING && throw(CellCycleException(c))
    _check_cell_writer(c)
    # The value that the readers of `c` read last, which the new value is compared
    # with. A failed cell has none: its next value is new to a reader that caught
    # its exception.
    had_value = c.state !== _FAILED && isdefined(c, :value)
    old = had_value ? c.value : nothing
    was_provisional = c.is_provisional
    stack = _get_computing_stack()
    _detach_upstream!(c)
    @count_performance :computes
    push!(stack, c)
    c.state = _COMPUTING
    # The run starts final; a read of a provisional cell makes it provisional.
    c.is_provisional = false
    value = try
        _run_computation(c.computation)
    catch
        # A failed run keeps the flag that its reads gave it: a failure that a
        # provisional value caused is provisional.
        c.state = _FAILED
        _invalidate_maybe_invalid_readers!(c)
        rethrow()
    finally
        pop!(stack)
        _remove_repeated_dependencies!(c)
    end
    # Only a run that still finds the cell computing stores its value. A write or a
    # new computation inside the run changed the state, and its answer stands. A
    # value of plain data that is `===` to the old one, and as provisional as the
    # old one, is no change for a reader, by the rule of a write, so the readers that
    # wait for a check stay as they are.
    if c.state === _COMPUTING
        c.value = value
        c.state = _VALID
        if had_value && _is_plain_value(value) && old === value && was_provisional == c.is_provisional
            @count_performance :stops
        else
            _invalidate_maybe_invalid_readers!(c)
        end
    else
        c.is_provisional = false
        isdefined(c, :value) || (c.value = value)
    end
end

# ── invalidation ─────────────────────────────────────────────────────────────

# Mark every direct reader of `c` invalid, and every valid cell below them maybe
# invalid. A failed reader stays failed, because it computes at its next read
# anyway, and the walk goes on through it, because a reader that caught its
# exception can be valid. An invalid, computing or checking reader stops the walk
# below it, because the cells below it are marked already. A reader comes out of
# `dependents` as a `ReactiveCell` with a free `T`, so `@nospecialize` gives each
# walk one compiled body, which calls itself with no dispatch at run time.
function _invalidate_dependents!(@nospecialize(c::ReactiveCell))
    ds = c.dependents
    ds === nothing && return
    for i in eachindex(ds)
        d = ds[i].value
        d === nothing && continue      # the reader was collected
        dd = d::ReactiveCell
        state = dd.state
        if state === _VALID
            dd.state = _INVALID
            @count_performance :invalidations
            _mark_readers_maybe_invalid!(dd)
        elseif state === _FAILED
            _mark_readers_maybe_invalid!(dd)
        elseif state === _MAYBE_INVALID || state === _CHECKING
            dd.state = _INVALID
            @count_performance :invalidations
        end
    end
end

# Mark every valid reader below `c` maybe invalid.
function _mark_readers_maybe_invalid!(@nospecialize(c::ReactiveCell))
    ds = c.dependents
    ds === nothing && return
    for i in eachindex(ds)
        d = ds[i].value
        d === nothing && continue
        dd = d::ReactiveCell
        state = dd.state
        if state === _VALID
            dd.state = _MAYBE_INVALID
            @count_performance :invalidations
            _mark_readers_maybe_invalid!(dd)
        elseif state === _FAILED
            _mark_readers_maybe_invalid!(dd)
        end
    end
end

# A computation of `c` gave a new value, or failed: its readers that wait for a
# check compute instead. The walk of the write counted their marks already.
function _invalidate_maybe_invalid_readers!(@nospecialize(c::ReactiveCell))
    ds = c.dependents
    ds === nothing && return
    for i in eachindex(ds)
        d = ds[i].value
        d === nothing && continue
        dd = d::ReactiveCell
        state = dd.state
        (state === _MAYBE_INVALID || state === _CHECKING) && (dd.state = _INVALID)
    end
end

# ── write ────────────────────────────────────────────────────────────────────

"""
    c[] = value

Make `c` hold `value`, and invalidate every cell that reads `c`. The cells that
read those are maybe invalid: at its next read, each one computes again only when
a cell that it read gives a new value. If `c` held a computation, it holds `value`
in its place. A value that does not convert to the value type of `c` throws, and
`c` stays as it was.

A write of plain data that is `===` to the value that `c` holds, when `c` holds no
computation, invalidates nothing. Plain data is a value that is `isbits`, a
`String` or a `Symbol`: it can not change inside, so no reader can tell the write
from no write. A write of the same mutable value still invalidates the readers,
and `invalidate_cell!` makes them compute again with no write.
"""
function Base.setindex!(c::ReactiveCell{T}, value) where {T}
    converted = convert(T, value)
    _is_same_plain_value(c, converted) && return value
    _check_cell_writer(c)
    @count_performance :writes
    _detach_upstream!(c)
    c.computation = nothing
    c.value = converted
    c.state = _VALID
    c.is_provisional = false
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
    _check_cell_writer(c)
    if c.computation !== nothing && (c.state === _VALID || c.state === _FAILED || c.state === _MAYBE_INVALID)
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
which does the same. Every cell that read it computes again on its next read,
unless the write is of the same plain data that the cell holds. A cell further
down computes again only when a cell that it read gives a new value.

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
    _check_cell_writer(c)
    _detach_upstream!(c)
    c.computation = _capture_fault_scope(computation)
    nothing isa T && (c.value = nothing)
    c.state = _INVALID
    c.is_provisional = false
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

# ── provisional values ───────────────────────────────────────────────────────

# A computation that reads `c` depends on it, also when it reads only whether `c`
# is provisional, and it does not become provisional by that read: whether a value
# is provisional is a final fact.
function is_cell_provisional(c::ReactiveCell)
    _record_read!(c)
    c.state === _VALID || _bring_up_to_date!(c)
    c.is_provisional
end

# A kind that records no reader holds no provisional value: a stored kind holds
# what was written, and the untracked kind reads with no reader. The fallback
# stands here, beside the engine that spreads the flag.
is_cell_provisional(::AbstractCell) = false

"""
    mark_computation_provisional!() -> nothing

Make the value of the computation that runs now provisional: a newer value comes
later. The computation answers what it has, such as its last value or a default,
and every computation that reads it is provisional too, until it computes again
from final values only.

Use it in a computation whose value comes from outside the loop and is not there
yet, such as the record of a file that a task still reads. The computation must
also read the cell that the final value arrives in, so the write of that cell
makes it compute again.

# Example

    answer = Cell(nothing)          # a task writes the final value here
    record = Cell(@computation begin
        value = answer[]
        value === nothing ? (mark_computation_provisional!(); "unknown") : value
    end)

Outside a computation it throws an `ArgumentError`, because it marks the
computation that runs, and so does code that runs with no reader, such as
`run_without_cell_tracking`, an `UntrackedCell` or a read on another task. A
computation whose first attempt fails in an older world, and that runs again in
the newest one, keeps the flag of both attempts, as it keeps the cells that both
read; the next change of a cell that it read clears it. See also
`is_cell_provisional`.
"""
function mark_computation_provisional!()
    stack = _get_computing_stack()
    isempty(stack) && throw(ArgumentError(
        "mark_computation_provisional! marks the computation that records its reads, and none " *
        "does here: no computation runs, or the code runs with no reader, as in " *
        "run_without_cell_tracking, an UntrackedCell or a read on another task"))
    stack[end].is_provisional = true
    nothing
end

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
    c.state === _VALID || _bring_up_to_date!(c)
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
# The edges are in a `Vector`, and not in a hash set, because the set is small.
# Across a live pipeline the mean size is 0.85, the median 1, the 99th percentile
# 3 and the largest 40, and one cell in 4173 has more than 16. Against a `Set`,
# the vector is about 3 times faster to register a reader, 1.4 times faster to
# detach one and 4 to 10 times faster to invalidate. A `WeakKeyDict` is 7 times
# slower than the `Set`, because its lock costs the most. The measurements are in
# plan/done/reactive-dependents-leak.md.
#
# A run detaches its cell from every cell that it read before it starts
# (`_detach_upstream!`), so the reader of a read in a run is new to the list of
# the cell that it reads, unless the run read that cell already. A record puts
# the reader at the end with no scan. A run that reads a cell again after another
# reader came puts a second entry of itself there; the next run, or a write,
# removes both, because a detach removes every entry of its reader. Collected
# readers are swept when a list grows to twice its length after the last sweep,
# and by every detach, so the list stays within about twice its live readers.

# `@nospecialize` on both: `observer` comes from the computing stack and `c` from
# the `dependencies` of another cell, and both of those hold `ReactiveCell` with a
# free parameter. The body walks a `Vector{WeakRef}` and compares with `===`; it
# never reads `T`.
function _register_dependent!(@nospecialize(c::ReactiveCell),
                              @nospecialize(observer::ReactiveCell))
    ds = _get_dependents!(c)
    n = length(ds)
    # A run that reads `c` again finds itself at the end, where its first read put
    # it, unless another reader came after it.
    n > 0 && (@inbounds ds[n]).value === observer && return nothing
    push!(ds, WeakRef(observer))
    n + 1 > 2 * Int(c.swept_length) + _SWEEP_MINIMUM && _sweep_dependents!(c, ds)
    return nothing
end

# The length under which a list of readers is not swept.
const _SWEEP_MINIMUM = 8

# Remove the entries of collected readers from `ds`, the readers of `c`.
function _sweep_dependents!(@nospecialize(c::ReactiveCell), ds::Vector{WeakRef})
    kept = 0
    @inbounds for i in eachindex(ds)
        entry = ds[i]
        entry.value === nothing && continue
        kept += 1
        ds[kept] = entry
    end
    resize!(ds, kept)
    c.swept_length = UInt32(kept)
    return nothing
end

# The mirror of `_register_dependent!`. Here `c` is the one with a free
# parameter: `_detach_upstream!` takes it out of `dependencies`, a
# `Vector{ReactiveCell}`.
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
