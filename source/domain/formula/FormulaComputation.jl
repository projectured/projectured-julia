# Fragment of `FormulaModule` — the computation of the stored value of a formula
# off the loop: the key of the code that a value comes from, the formula task of
# an editor, and the operations that start a computation and bring its value
# back. The code of a formula is the code of a person, so it can take any time;
# the loop only prepares its inputs as values and writes what comes back.

"""
    compute_formula_key(formula, env) -> UInt64

The key of the code and the inputs that the value of `formula` comes from now:
the hash of the text of its code, of its parameter, and of the key of the stored value of each
formula of `env` that the code names. A stored value whose `result_key` is this
key belongs to the code and the inputs now; a new value of an input makes it
stale.
"""
function compute_formula_key(formula::FormulaFormula, env::FormulaEnvironment)
    inputs = Pair{String,Any}[]
    for name in _find_readable_names(formula)
        dependency = resolve(env, name)
        push!(inputs, name => (dependency === nothing ? nothing : dependency.result_key))
    end
    hash((_formula_code_text(formula.code), _find_formula_parameter(formula), inputs))
end

# What the formula task needs to compute a formula, read on the loop: the key, and
# the code as an `Expr` with the stored values of its inputs; or the value itself
# when no code runs, as for a cycle, an input that failed, or code with no reading.
struct _FormulaJob
    key::UInt64
    expression::Any
    bindings::Vector{Pair{Symbol,Any}}
    value::Any
    is_ready::Bool
end

# The job of `formula` on the loop, or `nothing` when its stored value belongs to
# its code now.
function _make_formula_job(formula::FormulaFormula, env::FormulaEnvironment)
    key = compute_formula_key(formula, env)
    formula.result_key == key && return nothing
    _depends_on_itself(formula, env) && return _FormulaJob(key, nothing, Pair{Symbol,Any}[],
                                                           FormulaError("#CYCLE!"), true)
    try
        bindings = Pair{Symbol,Any}[]
        for name in get_formula_names(formula)
            dependency = resolve(env, name)
            dependency === nothing && continue
            value = dependency.result
            value isa FormulaError && return _FormulaJob(key, nothing, Pair{Symbol,Any}[], value, true)
            push!(bindings, Symbol(name) => value)
        end
        _FormulaJob(key, convert_formula_to_expr(formula, env), bindings, nothing, false)
    catch e
        _FormulaJob(key, nothing, Pair{Symbol,Any}[], FormulaError("#ERROR! " * sprint(showerror, e)), true)
    end
end

# The value of a job: its code run in `scratch`, on the task that calls it.
_run_formula_job(scratch::Module, job::_FormulaJob) =
    job.is_ready ? job.value : _run_formula_code(scratch, job.expression, job.bindings)

# The formulas of `env` that `formulas` holds, each after the formulas of the list
# that it names. A cycle does not stop the order: its formulas come in the order
# that the walk meets them.
function _order_formulas(env::FormulaEnvironment, formulas)
    wanted = Base.IdSet{FormulaFormula}(formulas)
    order = FormulaFormula[]
    seen = Base.IdSet{FormulaFormula}()
    function visit(formula)
        formula in seen && return
        push!(seen, formula)
        for dependency in get_formula_dependencies(formula, env)
            dependency in wanted && visit(dependency)
        end
        push!(order, formula)
    end
    foreach(visit, formulas)
    order
end

# The formulas of `env` that name `formula`.
_find_formula_dependents(env::FormulaEnvironment, formula::FormulaFormula) =
    FormulaFormula[other for other in env.formulas
                   if any(dependency -> dependency === formula, get_formula_dependencies(other, env))]

# ── The formula task of an editor ────────────────────────────────────────────

# The formulas that wait for the formula task of an editor, the task, and the
# scratch module in which it runs their code.
mutable struct _FormulaComputer
    lock::ReentrantLock
    queue::Vector{Tuple{FormulaEnvironment,FormulaFormula}}
    task::Union{BackgroundWork,Nothing}
    scratch::Module
end

_FormulaComputer() = _FormulaComputer(ReentrantLock(), Tuple{FormulaEnvironment,FormulaFormula}[], nothing,
                                      _make_formula_scratch_module())

# Queue `formulas` for the formula task of `editor`, and start the task when none
# runs. A formula that waits already keeps its place. The task is background work
# of the editor that no code unit waits for, so it can wait for the editor while
# the unit that queued the formulas still runs.
function _queue_formulas!(editor, env::FormulaEnvironment, formulas)
    computer = get_session_document!(_FormulaComputer, editor, _FormulaComputer)
    lock(computer.lock) do
        for formula in formulas
            any(((_, queued),) -> queued === formula, computer.queue) || push!(computer.queue, (env, formula))
        end
        computer.task === nothing &&
            (computer.task = start_background_work(() -> _run_formula_task!(editor, computer);
                                                   description = "the formula task", editor,
                                                   parent = nothing))
    end
    nothing
end

# The formula task: one formula after the other, until none waits. The loop
# prepares each job and writes each value, through the door; the code runs here.
function _run_formula_task!(editor, computer::_FormulaComputer)
    while true
        item = lock(computer.lock) do
            isempty(computer.queue) && (computer.task = nothing; return nothing)
            popfirst!(computer.queue)
        end
        item === nothing && return nothing
        (env, formula) = item
        try
            job = run_on_editor_task!(editor; description = "prepare a formula") do
                job = _make_formula_job(formula, env)
                job === nothing && (formula.is_computing = false)
                job
            end
            job === nothing && continue
            value = _run_formula_job(computer.scratch, job)
            run_on_editor_task!(editor; description = "store the value of a formula") do
                evaluate_operation(editor, ReplaceFormulaResultOperation(formula, env, value, job.key))
            end
        catch exception
            # The editor ended, or did not take the call: no formula of this queue
            # can come back.
            @warn "the formula task of the editor stops" exception
            lock(() -> (empty!(computer.queue); computer.task = nothing), computer.lock)
            return nothing
        end
    end
end

# ── The operations ───────────────────────────────────────────────────────────

"""
    ComputeFormulasOperation(environment, formulas = all of them)

Compute the stored value of `formulas` of `environment` again, each after the
formulas of the list that it names. While the loop of the editor runs, the
formula task of the editor computes them, one at a time and off the loop, and
each formula shows a mark until its value comes back. With no loop, as in a
test that drives the frames, or a script with no editor, they compute at once on
the task that applies the operation. A formula whose stored value belongs to its
code now is left as it is.

It starts a computation and edits no document of a person, so its inverse is
`DoNothingOperation()`.
"""
struct ComputeFormulasOperation <: Operation
    environment::FormulaEnvironment
    formulas::Vector{FormulaFormula}
end

ComputeFormulasOperation(environment::FormulaEnvironment) =
    ComputeFormulasOperation(environment, FormulaFormula[formula for formula in environment.formulas])

function evaluate_operation(editor, operation::ComputeFormulasOperation)
    env = operation.environment
    order = _order_formulas(env, operation.formulas)
    if editor isa Editor && is_editor_loop_running(editor)
        for formula in order
            formula.is_computing || (formula.is_computing = true)
        end
        _queue_formulas!(editor, env, order)
    else
        scratch = _make_formula_scratch_module()
        for formula in order
            job = _make_formula_job(formula, env)
            job === nothing && continue
            evaluate_operation(editor, ReplaceFormulaResultOperation(formula, env, _run_formula_job(scratch, job),
                                                                     job.key))
        end
    end
    nothing
end

make_inverse_operation(document, operation::ComputeFormulasOperation) = DoNothingOperation()

describe_operation(operation::ComputeFormulasOperation) =
    "compute $(length(operation.formulas)) formula(s) of the sheet"

"""
    ReplaceFormulaResultOperation(formula, environment, value, key)

Store `value`, which a computation of `formula` gave for the code with the key
`key`, as the value that a view of the formula shows. A value whose key is no
longer the key of the code now is dropped, and the formula computes again. A new
value computes again each formula of `environment` that names `formula`.

The stored value derives from the code, so it is no step of the undo; its inverse
is `DoNothingOperation()`.
"""
struct ReplaceFormulaResultOperation <: Operation
    formula::FormulaFormula
    environment::FormulaEnvironment
    value::Any
    key::UInt64
end

function evaluate_operation(editor, operation::ReplaceFormulaResultOperation)
    (formula, env) = (operation.formula, operation.environment)
    if compute_formula_key(formula, env) != operation.key
        evaluate_operation(editor, ComputeFormulasOperation(env, FormulaFormula[formula]))
        return nothing
    end
    old = formula.result
    isequal(old, operation.value) || (formula.result = operation.value)
    formula.result_key == operation.key || (formula.result_key = operation.key)
    formula.is_computing && (formula.is_computing = false)
    isequal(old, operation.value) && return nothing
    dependents = _find_formula_dependents(env, formula)
    isempty(dependents) || evaluate_operation(editor, ComputeFormulasOperation(env, dependents))
    nothing
end

make_inverse_operation(document, operation::ReplaceFormulaResultOperation) = DoNothingOperation()

describe_operation(operation::ReplaceFormulaResultOperation) =
    "store the value of the formula $(operation.formula.name)"

# A sheet that enters the window computes each value that it does not hold for
# its code now, as at the load of a file, whose sheet holds no value.
acquire_document!(editor, env::FormulaEnvironment) =
    evaluate_operation(editor, ComputeFormulasOperation(env))
