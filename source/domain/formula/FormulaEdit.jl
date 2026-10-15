# Fragment of `FormulaModule` — the edit mode of a formula, as a cell of a
# spreadsheet takes an edit: the keys edit a draft of the code, a commit writes the
# draft into the code as one operation and computes the formula, and a cancel
# drops the draft. A key starts no computation.

"""
    BeginFormulaEditOperation(formula; draft = nothing)

Put `formula` into edit mode, with `draft` as its draft, or a copy of its code. A
view shows the draft in place of the code and no value, because the stored value
belongs to the code. A key that edits the code of a formula in value mode starts
with it. Its inverse is [`CancelFormulaEditOperation`](@ref).
"""
struct BeginFormulaEditOperation <: Operation
    formula::FormulaFormula
    draft::Any
end

BeginFormulaEditOperation(formula::FormulaFormula; draft = nothing) = BeginFormulaEditOperation(formula, draft)

function evaluate_operation(editor, operation::BeginFormulaEditOperation)
    formula = operation.formula
    # The draft is a working copy of the code, a plain deep copy of its tree, which
    # every kind of code takes.
    formula.draft = something(operation.draft, copy_document(formula.code))
    nothing
end

make_inverse_operation(document, operation::BeginFormulaEditOperation) =
    CancelFormulaEditOperation(operation.formula)

describe_operation(operation::BeginFormulaEditOperation) = "edit the formula $(operation.formula.name)"

"""
    CancelFormulaEditOperation(formula)

Drop the draft of `formula`: the formula shows its code and its stored value
again. Escape gives it. Its inverse puts the same draft back.
"""
struct CancelFormulaEditOperation <: Operation
    formula::FormulaFormula
end

function evaluate_operation(editor, operation::CancelFormulaEditOperation)
    operation.formula.draft === nothing || (operation.formula.draft = nothing)
    nothing
end

make_inverse_operation(document, operation::CancelFormulaEditOperation) =
    BeginFormulaEditOperation(operation.formula; draft = operation.formula.draft)

describe_operation(operation::CancelFormulaEditOperation) = "drop the edit of the formula $(operation.formula.name)"

"""
    CommitFormulaOperation(formula, environment = nothing)

Write the draft of `formula` into its code, as one operation, leave the edit mode,
and compute the formula again in `environment` ([`ComputeFormulasOperation`](@ref)).
Enter gives it. With no environment, nothing computes. Its inverse restores the
old code, the draft and the old stored value together.
"""
struct CommitFormulaOperation <: Operation
    formula::FormulaFormula
    environment::Union{FormulaEnvironment, Nothing}
end

CommitFormulaOperation(formula::FormulaFormula) = CommitFormulaOperation(formula, nothing)

function evaluate_operation(editor, operation::CommitFormulaOperation)
    formula = operation.formula
    draft = formula.draft
    draft === nothing && return nothing
    formula.code = draft
    formula.draft = nothing
    environment = operation.environment
    environment === nothing ||
        evaluate_operation(editor, ComputeFormulasOperation(environment, FormulaFormula[formula]))
    nothing
end

make_inverse_operation(document, operation::CommitFormulaOperation) =
    (formula = operation.formula;
     _RestoreFormulaOperation(formula, operation.environment, formula.code, formula.draft,
                              formula.result, formula.result_key))

describe_operation(operation::CommitFormulaOperation) = "commit the formula $(operation.formula.name)"

# The state of a formula before a commit, which an undo of the commit puts back:
# its code, its draft, and its stored value with its key. Its inverse commits
# again.
struct _RestoreFormulaOperation <: Operation
    formula::FormulaFormula
    environment::Union{FormulaEnvironment, Nothing}
    code::Any
    draft::Any
    result::Any
    result_key::Any
end

function evaluate_operation(editor, operation::_RestoreFormulaOperation)
    formula = operation.formula
    formula.code = operation.code
    formula.draft = operation.draft
    isequal(formula.result, operation.result) || (formula.result = operation.result)
    formula.result_key = operation.result_key
    formula.is_computing && (formula.is_computing = false)
    nothing
end

make_inverse_operation(document, operation::_RestoreFormulaOperation) =
    CommitFormulaOperation(operation.formula, operation.environment)

describe_operation(operation::_RestoreFormulaOperation) = "restore the formula $(operation.formula.name)"

# Each names its formula, and no place in a document, so every reader passes it up
# as it is.
is_self_contained_operation(::Union{BeginFormulaEditOperation, CancelFormulaEditOperation,
                                    CommitFormulaOperation, _RestoreFormulaOperation}) = true

# ── An edit of the code becomes an edit of the draft ────────────────────────
#
# A key is read at the stage nearest the output, and its operation comes up to the
# sheet as a path from the sheet, such as `formulas[2].code.left`. So the reader
# of the sheet turns a write of the code of a formula in value mode into the start
# of the edit mode and the same write of the draft, which holds a copy of the code.

# The index of the formula of a sheet whose code `reference`, rooted at the sheet,
# reaches, or `nothing`.
function _find_written_formula(reference)
    reference isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    (length(steps) >= 3 && steps[1] == FieldReferenceStep("formulas") && steps[2] isa RangeReferenceStep &&
     steps[3] == FieldReferenceStep("code")) || return nothing
    steps[2].stop
end

_get_operation_path(operation) =
    operation isa ReplacePathOperation ? get_operation_path(operation) : operation_reference(operation)

# The index of the formula whose code `operation`, rooted at a sheet, writes: a
# step of it that is not a move of the selection has a path below the code.
function _find_formula_code_write(operation)
    if operation isa CompoundOperation
        for inner in operation.operations
            index = _find_formula_code_write(inner)
            index === nothing || return index
        end
        return nothing
    end
    operation isa WrappingOperation && return _find_formula_code_write(get_wrapped_operation(operation))
    operation isa ReplaceSelectionOperation && return nothing
    _find_written_formula(_get_operation_path(operation))
end

# `reference` below the draft of formula `index` in place of its code, or `nothing`
# when it is not below that code.
function _move_to_draft(reference, index::Int)
    _find_written_formula(reference) == index || return nothing
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    steps[3] = FieldReferenceStep("draft")
    reroot_reference(EmptyReference(), Tuple(steps))
end

# `operation` with each path below the code of formula `index` moved below its
# draft: an edit of the code becomes the same edit of the draft, and a move of the
# selection follows it.
function _move_to_formula_draft(operation, index::Int)
    operation isa CompoundOperation &&
        return CompoundOperation(Any[_move_to_formula_draft(inner, index) for inner in operation.operations])
    operation isa WrappingOperation &&
        return rewrap_operation(operation, _move_to_formula_draft(get_wrapped_operation(operation), index))
    moved = _move_to_draft(_get_operation_path(operation), index)
    moved === nothing && return operation
    operation isa ReplacePathOperation ? make_path_operation(operation, moved) : retarget_operation(operation, moved)
end

# What the reader of a sheet makes of an answer: a commit computes in this sheet,
# and a write of the code of a formula in value mode starts its edit mode.
function _read_formula_edit(env::FormulaEnvironment, answer::Intent)
    operation = _give_formula_environment(answer.operation, env)
    index = _find_formula_code_write(operation)
    if index !== nothing && env.formulas[index].draft === nothing
        operation = CompoundOperation(Any[BeginFormulaEditOperation(env.formulas[index]),
                                          _move_to_formula_draft(operation, index)])
    end
    operation === answer.operation ? answer : Intent(answer.gesture, operation, answer.description, answer.domain)
end

# ── The keys of the edit mode ───────────────────────────────────────────────

# The selection of the whole code of a formula, rooted at the formula.
_select_formula_code() = ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("code"), EmptyReference()))

# In edit mode, Enter commits the draft and Escape drops it, as in a cell of a
# spreadsheet, even inside the code, where a stage nearer the output reads the key
# too. Each leaves the selection on the whole code.
@gestures FormulaFormula begin
    when(doc.draft !== nothing)
    override(KeyPress('\n';)) => "Commit the formula" =>
        CompoundOperation(Any[CommitFormulaOperation(doc), _select_formula_code()])
    override(KeyDown(:escape;)) => "Drop the edit of the formula" =>
        CompoundOperation(Any[CancelFormulaEditOperation(doc), _select_formula_code()])
end

# A key for the formula of the sheet that holds the selection, when that formula
# is in edit mode: its bindings read the key first, even when a stage nearer the
# output read it, as a template reads the bindings of its focused child. The
# answer is rooted at the sheet; `nothing` when no binding answers.
function _read_formula_edit_key(env::FormulaEnvironment, change::Intent)
    gesture = change.gesture
    gesture isa Union{KeyPress, KeyDown} || return nothing
    selection = getfield(env, :selection)[]
    selection isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(selection))
    (length(steps) >= 2 && steps[1] == FieldReferenceStep("formulas") && steps[2] isa RangeReferenceStep) ||
        return nothing
    index = steps[2].stop
    1 <= index <= length(env.formulas) || return nothing
    formula = env.formulas[index]
    formula.draft === nothing && return nothing
    operation = read_gesture(formula, gesture; claimed = change.operation)
    operation === nothing ? nothing : reroot_operation(operation, (steps[1], steps[2]))
end

# `operation` with each commit that names no environment given `environment`. The
# reader of a sheet calls it, because only the sheet knows the formulas that a
# commit computes again.
function _give_formula_environment(operation, environment::FormulaEnvironment)
    operation isa CompoundOperation &&
        return CompoundOperation(Any[_give_formula_environment(inner, environment) for inner in operation.operations])
    operation isa CommitFormulaOperation && operation.environment === nothing &&
        return CommitFormulaOperation(operation.formula, environment)
    operation
end
