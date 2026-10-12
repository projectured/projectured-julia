# Fragment of `CellModule` — the fault scope of a computation: the owner that a
# computation belongs to, and where its fault goes when it throws.
#
# A computation runs when a reader reads its cell, often after the code that made the
# cell returned, so that code is not on the stack of the read that fails. The scope
# keeps the relation from the moment the computation is made: code makes its cells
# inside `run_in_cell_fault_scope`, each computation made there keeps the scope, and the
# computation that throws hands its fault to that scope.

# The scope that `run_in_cell_fault_scope` set, the computing stack of that moment and its
# depth. A computation made deeper in that stack was made by a computation that runs
# inside the scope, so it takes the scope of that computation instead. A stack that
# is not the same vector is the stack of `run_without_cell_tracking`.
const _FAULT_SCOPE =
    ScopedValue{Union{Nothing, Tuple{Any, Vector{ReactiveCell}, Int}}}(nothing)

"""
    run_in_cell_fault_scope(body, scope)

Run `body` so that every computation made inside it belongs to `scope`.

Use it around code that makes cells, when the faults of their computations belong
to one owner, the scope. A computation made in the scope keeps it. When it throws,
it calls [`record_cell_fault!`](@ref) with the scope, so the fault goes to
the owner that made the cell, whatever read reaches the cell. A computation made
later, inside the run of a computation that has a scope, takes that scope. A scope
inside a scope takes the place of the outer one until its `body` returns.

# Example

    total = run_in_cell_fault_scope(part) do
        Cell(@computation parse(Int, text[]))
    end

See also [`RecordedCellFaultException`](@ref).
"""
function run_in_cell_fault_scope(body, scope)
    stack = _get_computing_stack()
    with(body, _FAULT_SCOPE => (scope, stack, length(stack)))
end

"""
    RecordedCellFaultException(exception, scope)

A fault that a scope took, on its way up the stack of the reads.

The scope already recorded `exception` and will show it, so a scope above lets it
pass and records nothing, and a catch that would record a fault records no second
one. `scope` is the scope of the computation
that handed the fault on; a scope can pass a fault to the scope that encloses it,
which then shows it. `showerror` shows `exception`.

Use it to tell, in a catch above, a fault that a scope took from one that no scope
took: let it pass, and record nothing.

# Example

    catch exception
        exception isa RecordedCellFaultException && rethrow()
        record_fault!(store, :read; origin = :Parser, exception)
    end

See also [`run_in_cell_fault_scope`](@ref) and [`record_cell_fault!`](@ref).
"""
struct RecordedCellFaultException <: Exception
    exception::Any
    scope::Any
end

function Base.showerror(io::IO, recorded::RecordedCellFaultException)
    print(io, "a fault that a scope recorded: ")
    showerror(io, recorded.exception)
end

# A computation and the scope that it belongs to. The cell keeps this in place of
# the function, so a run of it hands a fault to the scope.
struct _FaultScopedComputation <: Function
    computation::Function
    scope::Any
end

# A `MethodError` in a task whose world is older than the newest method is no
# fault: a reactive cell runs the computation again in the newest world
# (`_run_computation`), and only a `MethodError` there is one.
function (scoped::_FaultScopedComputation)()
    try
        return scoped.computation()
    catch exception
        (exception isa RecordedCellFaultException || !is_fault_exception(exception)) &&
            rethrow()
        exception isa MethodError && Base.tls_world_age() < Base.get_world_counter() &&
            rethrow()
        record_cell_fault!(scoped.scope, scoped.computation, exception;
                                  traceback = catch_backtrace()) || rethrow()
        throw(RecordedCellFaultException(exception, scoped.scope))
    end
end

"""
    get_cell_fault_scope(cell) -> scope or nothing

The scope that the computation of `cell` belongs to, or `nothing` when the cell holds
a value, or when its computation was made outside every scope.

Use it to find the owner of the computation that a cell holds.

# Example

    owner = get_cell_fault_scope(cell)

See also [`find_cell_fault_scope`](@ref), the scope that a computation made now keeps.
"""
get_cell_fault_scope(cell::AbstractCell) =
    _get_computation_fault_scope(get_cell_computation(cell))

_get_computation_fault_scope(computation::_FaultScopedComputation) = computation.scope
_get_computation_fault_scope(::Union{Function, Nothing}) = nothing

"""
    find_cell_fault_scope() -> scope or nothing

The scope that a computation made now keeps: the scope of the computation that
runs, when it runs deeper than where `run_in_cell_fault_scope` set the last scope, else
that scope, or `nothing` outside every scope.

Use it before code sets a scope of its own, to know the scope that encloses it: a
fault that the inner scope can not show goes there.

# Example

    enclosing = find_cell_fault_scope()

See also [`run_in_cell_fault_scope`](@ref).
"""
function find_cell_fault_scope()
    current = _FAULT_SCOPE[]
    stack = get(task_local_storage(), :projectured_reactive_computing, nothing)
    if stack !== nothing && !isempty(stack)
        is_deeper = current === nothing || stack !== current[2] ||
                    length(stack) > current[3]
        is_deeper && return _get_computation_fault_scope(stack[end].computation)
    end
    current === nothing ? nothing : current[1]
end

function _capture_fault_scope(computation::Function)
    computation isa _FaultScopedComputation && return computation
    scope = find_cell_fault_scope()
    scope === nothing ? computation : _FaultScopedComputation(computation, scope)
end
