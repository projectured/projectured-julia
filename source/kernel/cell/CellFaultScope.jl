# Fragment of `CellModule` — the fault scope of a computation: the part of a print
# that a computation belongs to, and where its fault goes when it throws.
#
# A printer builds cells and returns. Its fault comes later, inside one of those
# cells, while a consumer reads it, and by then the printer and its barrier have
# returned. So the barrier is not on the stack of the read that fails. The scope
# keeps the relation from the moment the cell is built: a barrier prints its part
# inside `run_in_fault_scope`, each computation made there keeps the barrier, and
# the computation that throws hands its fault to that barrier.

# The scope that a barrier set, the computing stack of that moment and its depth.
# A computation made deeper in that stack was made by a computation that runs
# inside the print, so it takes the scope of that computation instead. A stack
# that is not the same vector is the stack of `run_untracked`.
const _FAULT_SCOPE = ScopedValue{Union{Nothing, Tuple{Any, Vector{ReactiveCell}, Int}}}(nothing)

"""
    run_in_fault_scope(body, scope)

Run `body` so that every computation made inside it belongs to `scope`.

Use it in a barrier, around the print of the part that the barrier holds. A
computation made in the scope keeps it. When it throws, it calls
[`record_computation_fault!`](@ref) with the scope, so the fault goes to the
barrier of the part that built the cell, whatever read reaches the cell. A
computation made later, inside the run of a computation that has a scope, takes
that scope. A scope inside a scope takes the place of the outer one until its
`body` returns.

# Example

    inner = run_in_fault_scope(barrier) do
        print_document(projection, recursion, input, context)
    end

See also [`RecordedFaultException`](@ref).
"""
function run_in_fault_scope(body, scope)
    stack = _get_computing_stack()
    with(body, _FAULT_SCOPE => (scope, stack, length(stack)))
end

"""
    record_computation_fault!(scope, computation, exception, traceback) -> Bool

Hand the fault of a computation to the scope that the computation belongs to, and
answer whether the scope took it.

The computation calls it once, inside its catch, with its own function, which
takes no argument and computes the value again, the exception and its traceback.
It runs inside a computation, so it must not write a cell. A scope that takes the
fault answers `true`, and the computation then throws a
[`RecordedFaultException`](@ref), so no scope above records the fault again. A
scope that can not show the fault answers `false`, and the exception goes on as
it is, to the next scope up.

A barrier adds a method for its own scope. The fallback takes nothing.
"""
function record_computation_fault! end

record_computation_fault!(scope, computation, exception, traceback) = false

"""
    RecordedFaultException(exception, scope)

A fault that a scope took, on its way up the stack of the reads.

The scope already recorded `exception` and will show it, so a scope or a barrier
above lets it pass and records nothing. A barrier that catches it while it prints
shows a mark and records no second fault. `scope` is the scope of the computation
that handed the fault on; a scope can pass a fault to the scope that encloses it,
which then shows it. `showerror` shows `exception`.

See also [`run_in_fault_scope`](@ref) and [`record_computation_fault!`](@ref).
"""
struct RecordedFaultException <: Exception
    exception::Any
    scope::Any
end

function Base.showerror(io::IO, recorded::RecordedFaultException)
    print(io, "a fault that a barrier recorded: ")
    showerror(io, recorded.exception)
end

# A computation and the scope that it belongs to. The cell keeps this in place of
# the function, so a run of it hands a fault to the scope.
struct _FaultScopedComputation <: Function
    computation::Function
    scope::Any
end

# A `MethodError` in a task whose world is older than the newest method is no
# fault: the cell runs the computation again in the newest world
# (`_run_computation`), and only a `MethodError` there is one.
function (scoped::_FaultScopedComputation)()
    try
        return scoped.computation()
    catch exception
        (exception isa RecordedFaultException || is_passthrough_exception(exception)) &&
            rethrow()
        exception isa MethodError && Base.tls_world_age() < Base.get_world_counter() &&
            rethrow()
        record_computation_fault!(scoped.scope, scoped.computation, exception,
                                  catch_backtrace()) || rethrow()
        throw(RecordedFaultException(exception, scoped.scope))
    end
end

"""
    get_fault_scope(computation::Function) -> scope or nothing

The scope that a computation belongs to, or `nothing` when it was made outside
every scope.
"""
get_fault_scope(computation::_FaultScopedComputation) = computation.scope
get_fault_scope(::Union{Function, Nothing}) = nothing

"""
    find_fault_scope() -> scope or nothing

The scope that a computation made now keeps: the scope of the computation that
runs, when it runs deeper than where the last barrier set its scope, else the
scope of that barrier, or `nothing` outside every scope.

Use it in a barrier, before it sets its own scope, to know the scope that encloses
it: a fault that the barrier can not show goes there.
"""
find_fault_scope() = _find_fault_scope()

# The scope of a computation made now: the scope of the computation that runs
# when it is deeper in the stack than the scope that a barrier set, and else the
# scope of the barrier.
function _find_fault_scope()
    current = _FAULT_SCOPE[]
    stack = get(task_local_storage(), :projectured_reactive_computing, nothing)
    if stack !== nothing && !isempty(stack)
        is_deeper = current === nothing || stack !== current[2] || length(stack) > current[3]
        is_deeper && return get_fault_scope(stack[end].computation)
    end
    current === nothing ? nothing : current[1]
end

function _capture_fault_scope(computation::Function)
    computation isa _FaultScopedComputation && return computation
    scope = _find_fault_scope()
    scope === nothing ? computation : _FaultScopedComputation(computation, scope)
end
