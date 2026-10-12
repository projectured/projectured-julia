# Fragment of `FormulaModule` — the formula document types: the abstract
# `FormulaDocument` and the type-in entry point that parses typed text into
# one.

abstract type FormulaDocument <: Document end

"""
A static "insert formula" placeholder label. It renders as a plain
`SyntaxLeaf` (`FormulaInsertionToSyntaxLeaf`) with no editable input; no
reader parses `value` into a `FormulaFormula` yet
(`plan/pending/excel-julia-formulas.md`, phase 5).
"""
@document struct FormulaInsertion <: FormulaDocument
    value::String = ""
end

"""
A named formula: `name` (display name — a `String` or a derived thunk `Cell`),
`code` (a `JuliaDocument`, a `MathDocument`, or a bare number), `result` (the
computed value, any value or a `FormulaError`), `display_mode`
(`:code`/`:result`/`:both`). The code refers to another formula by its name.
`result` is wired to `Cell(@computation evaluate_formula(self, env))` once placed
in an environment; see [`wire_result!`](@ref).
"""
@document struct FormulaFormula <: FormulaDocument
    name::String
    code::Union{JuliaDocument, MathDocument, PrimitiveNumber}
    result::Any
    display_mode::Symbol = :both
end

# Mixed positional+keyword form (name/code positional, result/display_mode
# keywords) the @document macro can't generate. `name` may be a String or a Cell
# (a derived thunk); the inner ctor passes a Cell through unchanged.
function FormulaFormula(name, code::Document; result = nothing, display_mode::Symbol = :both)
    name_cell = name isa Cell ? name : Cell(name isa AbstractString ? String(name) : name)
    FormulaFormula(name_cell, Cell(code), Cell(result), Cell(display_mode), Cell(nothing))
end

"""
Named-formula scope: an ordered set of `FormulaFormula`s (a spreadsheet
*sheet*). Each contained formula's `result` is wired to a reactive thunk
against this environment.
"""
@document struct FormulaEnvironment <: FormulaDocument
    formulas::CellVector{FormulaFormula} = CellVector{FormulaFormula}()
end
function FormulaEnvironment(formulas::Vector)
    env = FormulaEnvironment(CellVector{FormulaFormula}(formulas), Cell(nothing))
    for f in formulas
        wire_result!(f, env)
    end
    env
end

# ═══════════════════════════════════════════════════════════════════════
# Phase 2 — environment, naming, dependency graph, cycle detection
# ═══════════════════════════════════════════════════════════════════════

"""
    resolve(env, name) -> FormulaFormula | nothing

Look up the formula named `name` in `env` (the first match by current name).
Reads `env.formulas` and each `f.name` reactively.
"""
function resolve(env::FormulaEnvironment, name::AbstractString)
    key = get_formula_key(name)
    for f in env.formulas
        get_formula_key(f.name) == key && return f
    end
    return nothing
end

"""
    get_formula_key(name) -> String

The name a formula binds under: its own name when that is an identifier, and
otherwise the identifier its name reads as in the math notation, so `ρ` and
`rho` are one name and `p_{block}` is `p_block`. A name that reads as neither
is itself.
"""
function get_formula_key(name::AbstractString)
    text = String(name)
    try
        read = convert_math_to_julia(parse_math(text))
        read isa JuliaIdentifier && return read.name
    catch e
        e isa MathReadingException || e isa ErrorException || rethrow()
    end
    text
end

"""
    get_column_letter(col::Int) -> String

The spreadsheet column label for 1-based `col`: `1 → "A"`, `26 → "Z"`,
`27 → "AA"`, `28 → "AB"`, `52 → "AZ"`, `53 → "BA"`.
"""
function get_column_letter(col::Integer)
    col >= 1 || error("get_column_letter: col must be >= 1, got $col")
    s = Char[]
    n = col
    while n > 0
        n -= 1
        pushfirst!(s, Char('A' + (n % 26)))
        n ÷= 26
    end
    String(s)
end

"""
    cell_name(col::Int, row::Int) -> String

The A1-style name for a cell at 1-based `(col, row)`: `cell_name(1, 1) == "A1"`,
`cell_name(2, 1) == "B1"`, `cell_name(27, 3) == "AA3"`.
"""
get_cell_name(col::Integer, row::Integer) = get_column_letter(col) * string(row)

"""
    get_formula_dependencies(formula, env) -> Vector{FormulaFormula}

The formulas `formula` depends on in `env`: each formula of the sheet that a
free name of its code resolves to. A formula refers to another by name, so a
sheet read from a `.pred` file, `code = "(1 - rho) * rho^n"`, refers to the
formula `rho` of the same sheet.
"""
function get_formula_dependencies(formula::FormulaFormula, env::FormulaEnvironment)
    deps = FormulaFormula[]
    for name in get_formula_names(formula.code)
        target = resolve(env, name)
        target === nothing && continue
        target === formula && continue
        target in deps || push!(deps, target)
    end
    deps
end

"""
    get_formula_names(code) -> Vector{String}

Every free name of the Julia body `code`, in the order the walk meets them: each
`JuliaIdentifier` that the code reads and does not bind itself. A callee is a
name too, because a formula can hold a function: `G = F(3)` reads `F`. The
field of a field access names a slot, and is not a name.

A name that the code binds is local in the part that the binding covers, and is
not free there: a parameter of a lambda, a function or a `do` block, a variable
of a `let`, a `for` loop or a comprehension, a parameter of a `where`, the
variable of a `catch`, and the target of an `=` in the statements after it.
"""
function get_formula_names(code)
    names = String[]
    code isa PrimitiveNumber && return names
    _collect_names!(names, code isa MathDocument ? convert_math_to_julia(code) : code,
                    Set{String}())
    names
end

# `bound` holds the names that a binding above the node covers.
_collect_names!(names::Vector{String}, node, bound::Set{String}) = nothing

function _collect_names!(names::Vector{String}, node::Document, bound::Set{String})
    for fname in fieldnames(typeof(node))
        is_view_state_field(fname) && continue
        child = getfield(node, fname)[]
        if child isa CellVector
            for c in child
                _collect_names!(names, c, bound)
            end
        else
            _collect_names!(names, child, bound)
        end
    end
end

function _collect_names!(names::Vector{String}, node::JuliaIdentifier, bound::Set{String})
    node.name in bound || node.name in names || push!(names, node.name)
    return
end

_collect_names!(names::Vector{String}, node::JuliaFieldAccess, bound::Set{String}) =
    _collect_names!(names, node.object, bound)

# An `=` reads its value and binds its target, and a target that is a call
# defines a function. An update such as `+=` reads both sides. A keyword
# argument `k = v` of a call is an `=` too, so its `k` is no name.
function _collect_names!(names::Vector{String}, node::JuliaAssignment, bound::Set{String})
    if node.operator !== :(=)
        _collect_names!(names, node.target, bound)
        _collect_names!(names, node.value, bound)
    elseif _is_function_signature(node.target)
        _collect_names!(names, node.value, _bind_signature!(names, node.target, bound))
    else
        _collect_target_names!(names, node.target, bound)
        _collect_names!(names, node.value, bound)
    end
end

# The statements of a block run in order: what a statement binds covers the
# statements after it.
function _collect_names!(names::Vector{String}, node::Union{JuliaBlock,JuliaToplevel},
                         bound::Set{String})
    inner = copy(bound)
    for statement in node.statements
        _collect_names!(names, statement, inner)
        _add_statement_names!(inner, statement)
    end
end

_collect_names!(names::Vector{String}, node::JuliaLambda, bound::Set{String}) =
    _collect_names!(names, node.body, _bind_parameters!(names, node.parameters, bound))

_collect_names!(names::Vector{String}, node::JuliaLet, bound::Set{String}) =
    _collect_names!(names, node.body, _bind_parameters!(names, node.bindings, bound))

_collect_names!(names::Vector{String}, node::JuliaWhere, bound::Set{String}) =
    _collect_names!(names, node.body, _bind_parameters!(names, node.parameters, bound))

function _collect_names!(names::Vector{String}, node::JuliaDo, bound::Set{String})
    _collect_names!(names, node.call, bound)
    _collect_names!(names, node.body, _bind_parameters!(names, node.parameters, bound))
end

_collect_names!(names::Vector{String}, node::JuliaFor, bound::Set{String}) =
    _collect_names!(names, node.body, _bind_iterators!(names, node.iterators, bound))

function _collect_names!(names::Vector{String}, node::JuliaComprehension, bound::Set{String})
    _collect_names!(names, node.element_type, bound)
    inner = _bind_iterators!(names, node.iterators, bound)
    _collect_names!(names, node.expression, inner)
    _collect_names!(names, node.condition, inner)
end

function _collect_names!(names::Vector{String}, node::JuliaFunction, bound::Set{String})
    inner = _add_bound_names!(copy(bound), node.name)
    clause = node.where_clause
    clause isa JuliaWhereParameters && (inner = _bind_parameters!(names, clause.parameters, inner))
    _collect_names!(names, node.result_type, inner)
    _collect_names!(names, node.body, _bind_parameters!(names, node.params, inner))
end

function _collect_names!(names::Vector{String}, node::JuliaTry, bound::Set{String})
    _collect_names!(names, node.body, bound)
    variable = node.catch_var
    _collect_names!(names, node.catch_branch,
                    variable === nothing ? bound : _add_bound_names!(copy(bound), variable))
    _collect_names!(names, node.finally_branch, bound)
end

# Parameters bind from left to right, so a default can read a parameter before
# it. The bindings of a `let` and the parameters of a `where` bind the same way.
function _bind_parameters!(names::Vector{String}, parameters, bound::Set{String})
    inner = copy(bound)
    for parameter in parameters
        _collect_target_names!(names, parameter, inner)
        _add_bound_names!(inner, parameter)
    end
    inner
end

# The variables of a loop or a comprehension cover its body, and each iterable
# is read before its own variable binds.
function _bind_iterators!(names::Vector{String}, iterators, bound::Set{String})
    inner = copy(bound)
    for iterator in iterators
        _collect_names!(names, iterator.iterable, inner)
        _collect_target_names!(names, iterator.variable, inner)
        _add_bound_names!(inner, iterator.variable)
    end
    inner
end

# `f(x) = body`, `f(x)::T = body` and `f(x) where {T} = body` define `f`.
_is_function_signature(node) = node isa JuliaCall
_is_function_signature(node::JuliaWhere) = _is_function_signature(node.body)
_is_function_signature(node::JuliaTypeAnnotation) = _is_function_signature(node.value)

_get_function_name(node::JuliaCall) = node.callee
_get_function_name(node::JuliaWhere) = _get_function_name(node.body)
_get_function_name(node::JuliaTypeAnnotation) = _get_function_name(node.value)

# The names that the body of a function definition sees bound: the function
# itself, its parameters, and the parameters of its `where`.
function _bind_signature!(names::Vector{String}, signature, bound::Set{String})
    if signature isa JuliaWhere
        return _bind_signature!(names, signature.body,
                                _bind_parameters!(names, signature.parameters, bound))
    elseif signature isa JuliaTypeAnnotation
        inner = _bind_signature!(names, signature.value, bound)
        _collect_names!(names, signature.type, inner)
        return inner
    end
    inner = _add_bound_names!(copy(bound), signature.callee)
    inner = _bind_parameters!(names, signature.arguments, inner)
    _bind_parameters!(names, signature.keyword_arguments, inner)
end

_add_statement_names!(bound::Set{String}, statement) = bound
_add_statement_names!(bound::Set{String}, statement::JuliaFunction) =
    _add_bound_names!(bound, statement.name)
_add_statement_names!(bound::Set{String}, statement::JuliaConst) =
    _add_statement_names!(bound, statement.assignment)
function _add_statement_names!(bound::Set{String}, statement::JuliaAssignment)
    statement.operator === :(=) || return bound
    target = statement.target
    _add_bound_names!(bound, _is_function_signature(target) ? _get_function_name(target) : target)
end

# The names that a target or a parameter binds: `x`, `(a, b)`, `x::T`, `xs...`,
# `x = default`, `(; a, b)`, and the `T` of `T <: Real`.
_add_bound_names!(bound::Set{String}, node) = bound
_add_bound_names!(bound::Set{String}, node::JuliaIdentifier) = push!(bound, node.name)
_add_bound_names!(bound::Set{String}, node::JuliaTypeAnnotation) = _add_bound_names!(bound, node.value)
_add_bound_names!(bound::Set{String}, node::JuliaSplat) = _add_bound_names!(bound, node.value)
_add_bound_names!(bound::Set{String}, node::JuliaAssignment) = _add_bound_names!(bound, node.target)
_add_bound_names!(bound::Set{String}, node::JuliaSubtype) = _add_bound_names!(bound, node.lhs)
function _add_bound_names!(bound::Set{String}, node::Union{JuliaTuple,JuliaNamedTuple})
    for element in (node isa JuliaTuple ? node.elements : node.entries)
        _add_bound_names!(bound, element)
    end
    bound
end

# The names that a target or a parameter reads: a type, a default, the bound of
# `T <: Real`, and the collection and the indices of `a[i] = v`.
_collect_target_names!(names::Vector{String}, node, bound::Set{String}) =
    _collect_names!(names, node, bound)
_collect_target_names!(names::Vector{String}, node::JuliaIdentifier, bound::Set{String}) = nothing
_collect_target_names!(names::Vector{String}, node::JuliaSplat, bound::Set{String}) =
    _collect_target_names!(names, node.value, bound)
_collect_target_names!(names::Vector{String}, node::JuliaSubtype, bound::Set{String}) =
    _collect_names!(names, node.rhs, bound)
function _collect_target_names!(names::Vector{String}, node::JuliaTypeAnnotation,
                                bound::Set{String})
    _collect_target_names!(names, node.value, bound)
    _collect_names!(names, node.type, bound)
end
function _collect_target_names!(names::Vector{String}, node::JuliaAssignment, bound::Set{String})
    _collect_target_names!(names, node.target, bound)
    _collect_names!(names, node.value, bound)
end
function _collect_target_names!(names::Vector{String}, node::Union{JuliaTuple,JuliaNamedTuple},
                                bound::Set{String})
    for element in (node isa JuliaTuple ? node.elements : node.entries)
        _collect_target_names!(names, element, bound)
    end
end

"""
    would_create_cycle(env, from, to) -> Bool

True if adding a reference `from → to` would close a cycle, i.e. if `to` can
already reach `from` through the existing dependency graph (or `to === from`).
DFS over `get_formula_dependencies`.
"""
function would_create_cycle(env::FormulaEnvironment, from::FormulaFormula, to::FormulaFormula)
    from === to && return true
    visited = Set{FormulaFormula}()
    stack = FormulaFormula[to]
    while !isempty(stack)
        n = pop!(stack)
        n === from && return true
        n in visited && continue
        push!(visited, n)
        for d in get_formula_dependencies(n, env)
            push!(stack, d)
        end
    end
    return false
end

"""
    compute_topological_order(env) -> Vector{FormulaFormula}

A dependency-first ordering of `env`'s formulas (dependencies before dependents).
Errors if the graph contains a cycle. Useful for batch evaluation and tests.
"""
function compute_topological_order(env::FormulaEnvironment)
    order = FormulaFormula[]
    state = Dict{FormulaFormula,Int}()  # absent/0 = unvisited, 1 = in-progress, 2 = done
    function visit(n)
        s = get(state, n, 0)
        s == 2 && return
        s == 1 && error("compute_topological_order: cycle detected at $(n.name)")
        state[n] = 1
        for d in get_formula_dependencies(n, env)
            visit(d)
        end
        state[n] = 2
        push!(order, n)
    end
    for f in env.formulas
        visit(f)
    end
    order
end

# ═══════════════════════════════════════════════════════════════════════
# Phase 3 — evaluation
# ═══════════════════════════════════════════════════════════════════════

# A persistent scratch module used to evaluate formula bodies, mirroring the
# `execute_julia_code!` sandbox-eval pattern in editor/Mcp.jl. Dependency values
# are bound as locals in a generated `let` so they never leak into globals.
const _FORMULA_SCRATCH = Ref{Module}()

function _formula_scratch_module()
    if !isassigned(_FORMULA_SCRATCH)
        _FORMULA_SCRATCH[] = Module(:FormulaScratch)
    end
    _FORMULA_SCRATCH[]
end

"""
    FormulaError(text)

The value of a formula that computes none: `#ERROR!` and the message of an
error that its code raised, or `#CYCLE!` when the formula depends on itself. A
formula that reads it gives it on as its own value, so the error shows in every
formula that depends on the formula that failed.
"""
struct FormulaError
    text::String
end

Base.show(io::IO, error::FormulaError) = print(io, error.text)

"""
    convert_formula_to_expr(code, env) -> Expr | literal

The Julia `Expr` of the code of a formula, which `evaluate_formula` runs inside
a `let` that binds the names of its dependencies to their values. Julia code
gives the `Expr` that `make_julia_expression` builds, math code the `Expr` of
its Julia reading, and a bare number its value.
"""
convert_formula_to_expr(code::JuliaDocument, env::FormulaEnvironment) =
    Expr(:block, make_julia_expression(code).args...)
convert_formula_to_expr(code::MathDocument, env::FormulaEnvironment) =
    convert_formula_to_expr(convert_math_to_julia(code), env)
convert_formula_to_expr(code::PrimitiveNumber, env::FormulaEnvironment) = code.value

"""
    evaluate_formula(formula, env) -> value

The value of `formula`: its code evaluated in a scratch module, inside a `let`
that binds each free name that resolves in `env` to the value of that formula.
The scope binds last, so a formula named `pi` means that formula and not
`Base.pi`. The read of the `result` of each dependency records the dependency,
so a change of it computes this formula again.

An error that the code raises, a dependency whose value is a `FormulaError`,
and a formula that depends on itself give a `FormulaError`.
"""
function evaluate_formula(formula::FormulaFormula, env::FormulaEnvironment)
    _depends_on_itself(formula, env) && return FormulaError("#CYCLE!")
    try
        bindings = Expr[]
        for name in get_formula_names(formula.code)
            dependency = resolve(env, name)
            dependency === nothing && continue
            value = dependency.result
            value isa FormulaError && return value
            push!(bindings, Expr(:(=), Symbol(name), QuoteNode(value)))
        end
        body = convert_formula_to_expr(formula.code, env)
        Core.eval(_formula_scratch_module(), Expr(:let, Expr(:block, bindings...), body))
    catch e
        FormulaError("#ERROR! " * sprint(showerror, e))
    end
end

# Whether `formula` reaches itself through the names of the formulas of `env`.
# The walk reads the code and the name of each formula it meets, and no result:
# so a formula of a cycle computes again when a formula of the cycle changes, and
# the cycle is found before a result reads another in its own computation.
function _depends_on_itself(formula::FormulaFormula, env::FormulaEnvironment)
    visited = Set{FormulaFormula}()
    pending = FormulaFormula[formula]
    while !isempty(pending)
        node = pop!(pending)
        node in visited && continue
        push!(visited, node)
        for name in _find_readable_names(node.code)
            target = resolve(env, name)
            target === formula && return true
            target === nothing || push!(pending, target)
        end
    end
    false
end

# The free names of a code that the evaluation can read. A math tree with no
# reading has none, and its own evaluation says why.
function _find_readable_names(code)
    try
        return get_formula_names(code)
    catch e
        e isa MathReadingException || e isa ErrorException || rethrow()
    end
    String[]
end

"""
    get_formula_value(formula) -> Any

The value of a formula: any value its code computes, or a `FormulaError`.
Reading it inside a reactive cell subscribes to the result.

Use it to read the number a formula of a study's sheet computed — a blocking
probability, a mean queue length — to compare it with a result, to print it, or
to state an expectation from it.

# Example

    p_block = add_study_formula!(get_study(), "p_{block}", "((1 - ρ) ρ^n)/(1 - ρ^(n + 1))")
    println(get_formula_value(p_block))

See also `add_study_formula!`, `add_expectation!`.
"""
get_formula_value(formula::FormulaFormula) = formula.result

# The value of a formula as one line of text, short enough to read beside its
# code: a float to six digits, nothing as no text, and any other value in its
# `text/plain` form, or in its compact form when that form takes more lines.
_formula_value_text(value::AbstractFloat) = string(round(value; sigdigits = 6))
_formula_value_text(::Nothing) = ""
function _formula_value_text(value)
    text = sprint(show, MIME("text/plain"), value)
    occursin('\n', text) && (text = sprint(show, value; context = :compact => true))
    String(first(split(text, '\n')))
end

"""
    wire_result!(formula, env) -> formula

Wire `formula.result` to a reactive thunk that re-evaluates the body whenever any
dependency's value changes. Idempotent.
"""
function wire_result!(formula::FormulaFormula, env::FormulaEnvironment)
    set_cell_computation!(getfield(formula, :result),
                          () -> evaluate_formula(formula, env))
    formula
end

# ── What a formula owes its file ─────────────────────────────────────────────
#
# A formula holds its code as a Julia tree and its result as a derived cell. A
# `.pred` file holds the code as the text a person wrote, and no result: the
# sheet evaluates it again on load. A sheet writes its formulas, one block each.

"""
    pred_arguments(formula::FormulaFormula)

The call a `.pred` file writes for a formula: its name, its code as the text
of its notation, the notation, `:julia` or `:math`, and its display mode. The
result is derived and is not written. No field holds the notation: the type of
the code says it, and the file writes what the type says.
"""
pred_arguments(formula::FormulaFormula) = (), Pair{Symbol,Any}[
    :name         => formula.name,
    :code         => _formula_code_text(formula.code),
    :notation     => is_math_code(formula.code) ? :math : :julia,
    :display_mode => formula.display_mode,
]

"""
    is_math_code(code) -> Bool

Whether a formula's code is written in the math notation: a math tree, or a
bare number, which the math reader answers for a line that is one number.
"""
is_math_code(code) = code isa MathDocument || code isa PrimitiveNumber

_formula_code_text(code::PrimitiveNumber) = string(code.value)
_formula_code_text(code) = print_natural_text(code)

"""
    make_pred_document(::Type{<:FormulaFormula}, positional, keywords)

The formula a call in a file builds: `FormulaFormula(name = "rho", code = "0.8")`
or `FormulaFormula("rho", "0.8")`. The code text is read by the notation the
call names, `parse_julia` for `:julia` and `parse_math` for `:math`; a call
that names none is Julia.
"""
function make_pred_document(::Type{<:FormulaFormula}, positional, keywords)
    fields = Dict{Symbol,Any}(keywords)
    Base.length(positional) >= 1 && (fields[:name] = positional[1])
    Base.length(positional) >= 2 && (fields[:code] = positional[2])
    haskey(fields, :name) || error("FormulaFormula: a formula needs a name")
    haskey(fields, :code) || error("FormulaFormula: a formula needs its code")
    code = fields[:code]
    code isa AbstractString ||
        error("FormulaFormula: the code of a formula is text, got ", typeof(code))
    notation = get(fields, :notation, :julia)
    notation in (:julia, :math) ||
        error("FormulaFormula: the notation is :julia or :math, got ", repr(notation))
    tree = notation === :math ? parse_math(String(code)) : parse_julia(String(code))
    FormulaFormula(String(fields[:name]), tree; display_mode = get(fields, :display_mode, :both))
end

"""
    pred_arguments(env::FormulaEnvironment)

The call a `.pred` file writes for a sheet: its formulas, in order.
"""
pred_arguments(env::FormulaEnvironment) =
    (), Pair{Symbol,Any}[:formulas => Any[f for f in env.formulas]]

"""
    make_pred_document(::Type{<:FormulaEnvironment}, positional, keywords)

The sheet a call in a file builds. Every formula in it is wired to the sheet, so
each result evaluates again against the names the file wrote.
"""
function make_pred_document(::Type{<:FormulaEnvironment}, positional, keywords)
    fields = Dict{Symbol,Any}(keywords)
    formulas = Base.length(positional) >= 1 ? positional[1] : get(fields, :formulas, Any[])
    FormulaEnvironment(Vector{Any}(formulas))
end
