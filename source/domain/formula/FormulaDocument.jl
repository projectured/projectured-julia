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
`code` (a `JuliaDocument`, a `MathDocument`, or a bare number), and
`display_mode` (`:code`/`:result`/`:both`). The code refers to another formula by
its name. `draft` is `nothing` in value mode, and in edit mode a copy of the code
that the keys edit, which a commit writes into the code
([`CommitFormulaOperation`](@ref)); a view then shows the draft and no value.

`result` is the last value that was computed, any value or a `FormulaError`, or
`nothing` before the first computation; `result_key` is the key of the code that
it came from ([`compute_formula_key`](@ref)), and `is_computing` says that a
computation of it runs. Only [`ReplaceFormulaResultOperation`](@ref) writes them,
and a print reads only them. `current_value` is the value of the code and the
inputs now, which a read computes on the task that reads it; it is wired once the
formula is placed in an environment ([`wire_result!`](@ref)), code reads it with
[`get_formula_value`](@ref), and no print reads it.
"""
@document struct FormulaFormula <: FormulaDocument
    name::String
    code::Union{JuliaDocument, MathDocument, PrimitiveNumber}
    draft::Any
    result::Any
    result_key::Any
    is_computing::Bool
    current_value::Any
    display_mode::Symbol = :both
end

# Mixed positional+keyword form (name/code positional, result/display_mode
# keywords) the @document macro can't generate. `name` may be a String or a Cell
# (a derived thunk); the inner ctor passes a Cell through unchanged.
function FormulaFormula(name, code::Document; result = nothing, display_mode::Symbol = :both)
    name_cell = name isa Cell ? name : Cell(name isa AbstractString ? String(name) : name)
    FormulaFormula(name_cell, Cell(code), Cell(nothing), Cell(result), Cell(nothing), Cell(false),
                   Cell(nothing), Cell(display_mode), Cell(nothing))
end

"""
Named-formula scope: an ordered set of `FormulaFormula`s (a spreadsheet
*sheet*). The `current_value` of each formula is wired to this environment.
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
`rho` are one name, `p_{block}` is `p_block` and `U_{slotted,5}` is
`U_slotted_5`. A name that reads as neither is itself. A name with one name in parentheses, `S_{pure}(G)`, is the name of a
function of one variable, and its key is the name before the parentheses,
`S_pure`; the name in the parentheses is its parameter
([`_find_formula_parameter`](@ref)).
"""
function get_formula_key(name::AbstractString)
    text = String(name)
    try
        # A name that reads as a number, such as `1`, is no math tree.
        tree = parse_math(text)
        _is_function_name(tree) && return _get_function_key(tree)
        tree isa MathDocument && (read = convert_math_to_julia(tree)) isa JuliaIdentifier &&
            return read.name
    catch e
        e isa MathReadingException || e isa ErrorException || rethrow()
    end
    text
end

# Whether a tree is a name with one name in parentheses.
_is_function_name(tree) = tree isa MathFunction &&
    (tree.argument isa MathVariable || tree.argument isa MathSymbol || tree.argument isa MathText)

# The name that a formula takes as its parameter, `rho` for `S_{pure}(ρ)`, or
# `nothing` when its name names none.
function _find_formula_parameter(name::AbstractString)
    try
        tree = parse_math(String(name))
        _is_function_name(tree) && return _name_of_node(tree.argument)
    catch e
        e isa MathReadingException || e isa ErrorException || rethrow()
    end
    nothing
end
_find_formula_parameter(formula::FormulaFormula) = _find_formula_parameter(formula.name)

# The keys of the formulas of `env` whose name names a parameter.
_find_function_keys(env::FormulaEnvironment) =
    String[get_formula_key(f.name) for f in env.formulas if _find_formula_parameter(f) !== nothing]

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
    get_cell_name(col::Int, row::Int) -> String

The A1-style name for a cell at 1-based `(col, row)`: `get_cell_name(1, 1) == "A1"`,
`get_cell_name(2, 1) == "B1"`, `get_cell_name(27, 3) == "AA3"`.
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
    for name in get_formula_names(formula)
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
get_formula_names(code) =
    unique!(String[identifier.name for identifier in _find_free_identifiers(code)])

"""
    get_formula_names(formula::FormulaFormula) -> Vector{String}

The free names of the code of `formula`, with its parameter bound: the parameter
of `S_{pure}(G)` is no name of the sheet, and it shadows a formula `G`, as the
parameter of a lambda does.
"""
function get_formula_names(formula::FormulaFormula)
    parameter = _find_formula_parameter(formula)
    parameter === nothing && return get_formula_names(formula.code)
    unique!(String[identifier.name for identifier in
                   _find_free_identifiers(formula.code, Set{String}([parameter]))])
end

# Each free identifier of `code`, every place it stands. A math tree gives those of
# its Julia reading.
_find_free_identifiers(code::PrimitiveNumber, bound::Set{String} = Set{String}()) = JuliaIdentifier[]
function _find_free_identifiers(code, bound::Set{String} = Set{String}())
    found = JuliaIdentifier[]
    _collect_free_identifiers!(found, code isa MathDocument ? convert_math_to_julia(code) : code, bound)
    found
end

# `bound` holds the names that a binding above the node covers.
_collect_free_identifiers!(found, node, bound::Set{String}) = nothing

function _collect_free_identifiers!(found, node::Document, bound::Set{String})
    for fname in fieldnames(typeof(node))
        is_view_state_field(fname) && continue
        child = getfield(node, fname)[]
        if child isa CellVector
            for c in child
                _collect_free_identifiers!(found, c, bound)
            end
        else
            _collect_free_identifiers!(found, child, bound)
        end
    end
end

function _collect_free_identifiers!(found, node::JuliaIdentifier,
                                    bound::Set{String})
    _record_identifier!(found, node, bound)
    return
end

# A list keeps each free identifier; a dictionary keeps every identifier with the
# names that bind where it stands, to find a local name that would capture it.
_record_identifier!(found::Vector, node::JuliaIdentifier, bound::Set{String}) =
    node.name in bound || push!(found, node)
_record_identifier!(found::IdDict, node::JuliaIdentifier, bound::Set{String}) =
    found[node] = copy(bound)

_collect_free_identifiers!(found, node::JuliaFieldAccess, bound::Set{String}) =
    _collect_free_identifiers!(found, node.object, bound)

# An `=` reads its value and binds its target, and a target that is a call
# defines a function. An update such as `+=` reads both sides. A keyword
# argument `k = v` of a call is an `=` too, so its `k` is no name.
function _collect_free_identifiers!(found, node::JuliaAssignment, bound::Set{String})
    if node.operator !== :(=)
        _collect_free_identifiers!(found, node.target, bound)
        _collect_free_identifiers!(found, node.value, bound)
    elseif _is_function_signature(node.target)
        _collect_free_identifiers!(found, node.value, _bind_signature!(found, node.target, bound))
    else
        _collect_target_identifiers!(found, node.target, bound)
        _collect_free_identifiers!(found, node.value, bound)
    end
end

# The statements of a block run in order: what a statement binds covers the
# statements after it.
function _collect_free_identifiers!(found, node::Union{JuliaBlock,JuliaToplevel},
                         bound::Set{String})
    inner = copy(bound)
    for statement in node.statements
        _collect_free_identifiers!(found, statement, inner)
        _add_statement_names!(inner, statement)
    end
end

_collect_free_identifiers!(found, node::JuliaLambda, bound::Set{String}) =
    _collect_free_identifiers!(found, node.body, _bind_parameters!(found, node.parameters, bound))

_collect_free_identifiers!(found, node::JuliaLet, bound::Set{String}) =
    _collect_free_identifiers!(found, node.body, _bind_parameters!(found, node.bindings, bound))

_collect_free_identifiers!(found, node::JuliaWhere, bound::Set{String}) =
    _collect_free_identifiers!(found, node.body, _bind_parameters!(found, node.parameters, bound))

function _collect_free_identifiers!(found, node::JuliaDo, bound::Set{String})
    _collect_free_identifiers!(found, node.call, bound)
    _collect_free_identifiers!(found, node.body, _bind_parameters!(found, node.parameters, bound))
end

_collect_free_identifiers!(found, node::JuliaFor, bound::Set{String}) =
    _collect_free_identifiers!(found, node.body, _bind_iterators!(found, node.iterators, bound))

function _collect_free_identifiers!(found, node::JuliaComprehension, bound::Set{String})
    _collect_free_identifiers!(found, node.element_type, bound)
    inner = _bind_iterators!(found, node.iterators, bound)
    _collect_free_identifiers!(found, node.expression, inner)
    _collect_free_identifiers!(found, node.condition, inner)
end

function _collect_free_identifiers!(found, node::JuliaFunction, bound::Set{String})
    inner = _add_bound_names!(copy(bound), node.name)
    clause = node.where_clause
    clause isa JuliaWhereParameters && (inner = _bind_parameters!(found, clause.parameters, inner))
    _collect_free_identifiers!(found, node.result_type, inner)
    _collect_free_identifiers!(found, node.body, _bind_parameters!(found, node.params, inner))
end

function _collect_free_identifiers!(found, node::JuliaTry, bound::Set{String})
    _collect_free_identifiers!(found, node.body, bound)
    variable = node.catch_var
    _collect_free_identifiers!(found, node.catch_branch,
                    variable === nothing ? bound : _add_bound_names!(copy(bound), variable))
    _collect_free_identifiers!(found, node.finally_branch, bound)
end

# Parameters bind from left to right, so a default can read a parameter before
# it. The bindings of a `let` and the parameters of a `where` bind the same way.
function _bind_parameters!(found, parameters, bound::Set{String})
    inner = copy(bound)
    for parameter in parameters
        _collect_target_identifiers!(found, parameter, inner)
        _add_bound_names!(inner, parameter)
    end
    inner
end

# The variables of a loop or a comprehension cover its body, and each iterable
# is read before its own variable binds.
function _bind_iterators!(found, iterators, bound::Set{String})
    inner = copy(bound)
    for iterator in iterators
        _collect_free_identifiers!(found, iterator.iterable, inner)
        _collect_target_identifiers!(found, iterator.variable, inner)
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
function _bind_signature!(found, signature, bound::Set{String})
    if signature isa JuliaWhere
        return _bind_signature!(found, signature.body,
                                _bind_parameters!(found, signature.parameters, bound))
    elseif signature isa JuliaTypeAnnotation
        inner = _bind_signature!(found, signature.value, bound)
        _collect_free_identifiers!(found, signature.type, inner)
        return inner
    end
    inner = _add_bound_names!(copy(bound), signature.callee)
    inner = _bind_parameters!(found, signature.arguments, inner)
    _bind_parameters!(found, signature.keyword_arguments, inner)
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
_add_bound_names!(bound::Set{String}, node::JuliaTypeAnnotation) =
    _add_bound_names!(bound, node.value)
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
_collect_target_identifiers!(found, node, bound::Set{String}) =
    _collect_free_identifiers!(found, node, bound)
_collect_target_identifiers!(found, node::JuliaIdentifier, bound::Set{String}) = nothing
_collect_target_identifiers!(found, node::JuliaSplat, bound::Set{String}) =
    _collect_target_identifiers!(found, node.value, bound)
_collect_target_identifiers!(found, node::JuliaSubtype, bound::Set{String}) =
    _collect_free_identifiers!(found, node.rhs, bound)
function _collect_target_identifiers!(found, node::JuliaTypeAnnotation,
                                bound::Set{String})
    _collect_target_identifiers!(found, node.value, bound)
    _collect_free_identifiers!(found, node.type, bound)
end
function _collect_target_identifiers!(found, node::JuliaAssignment, bound::Set{String})
    _collect_target_identifiers!(found, node.target, bound)
    _collect_free_identifiers!(found, node.value, bound)
end
function _collect_target_identifiers!(found, node::Union{JuliaTuple,JuliaNamedTuple},
                                bound::Set{String})
    for element in (node isa JuliaTuple ? node.elements : node.entries)
        _collect_target_identifiers!(found, element, bound)
    end
end

# Each identifier of the Julia code of `formula`, with the names that a binding of
# the code, or the parameter of the formula, covers where it stands.
function _find_identifier_scopes(formula::FormulaFormula)
    scopes = IdDict{Any,Set{String}}()
    parameter = _find_formula_parameter(formula)
    _collect_free_identifiers!(scopes, formula.code,
                               parameter === nothing ? Set{String}() : Set{String}([parameter]))
    scopes
end

# The identifiers of the code of `formula` that refer to a formula of `env`: each
# free identifier whose name resolves there, held by identity. Math code gives
# none, because its view draws the math tree and not its Julia reading.
function _find_reference_identifiers(formula::FormulaFormula, env::FormulaEnvironment)
    references = Base.IdSet{Any}()
    code = formula.code
    code isa JuliaDocument || return references
    parameter = _find_formula_parameter(formula)
    for identifier in _find_free_identifiers(code, parameter === nothing ? Set{String}() : Set{String}([parameter]))
        resolve(env, identifier.name) === nothing || push!(references, identifier)
    end
    references
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

# The code of a formula runs in a scratch module: one for each editor, which its
# formula task keeps, and one for each formula that code reads the value of. The
# values of the dependencies are bound as locals in a generated `let`, so they
# never leak into globals.
# `e` is Euler's number in each scratch module; the `let` of the sheet binds last,
# so a formula named `e` means that formula.
function _make_formula_scratch_module()
    scratch = Module(:FormulaScratch)
    Core.eval(scratch, :(const e = Base.MathConstants.e))
    scratch
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
    convert_formula_to_expr(formula, env) -> Expr | literal

The Julia `Expr` of the code of a formula, which `evaluate_formula` runs inside
a `let` that binds the names of its dependencies to their values. Julia code
gives the `Expr` that `make_julia_expression` builds, math code the `Expr` of
its Julia reading with the functions of `env` ([`convert_math_to_julia`](@ref)),
and a bare number its value. The `Expr` of a formula with a parameter is a
lambda of the parameter whose body is the `Expr` of the code. A formula whose
name ends in `(X)`, where `X` is a name of its code, and does not read in the
math notation gives an error that says why the name does not read.
"""
convert_formula_to_expr(code::JuliaDocument, env::FormulaEnvironment) =
    Expr(:block, make_julia_expression(code).args...)
convert_formula_to_expr(code::MathDocument, env::FormulaEnvironment) =
    convert_formula_to_expr(convert_math_to_julia(code; functions = _find_function_keys(env)), env)
convert_formula_to_expr(code::PrimitiveNumber, env::FormulaEnvironment) = code.value

function convert_formula_to_expr(formula::FormulaFormula, env::FormulaEnvironment)
    body = convert_formula_to_expr(formula.code, env)
    parameter = _find_formula_parameter(formula)
    parameter === nothing || return Expr(:->, Symbol(parameter), body)
    _check_function_name(formula)
    body
end

# A name that ends in `(X)`, where `X` is a name of the code, is the name of a
# function of `X`. When it does not read, its code would run with no `X`, so the
# error says why the name does not read, and not that `X` is not defined.
function _check_function_name(formula::FormulaFormula)
    found = match(r"\(\s*([^()]+?)\s*\)\s*$", formula.name)
    (found === nothing || !(found[1] in get_formula_names(formula.code))) && return
    try
        parse_math(formula.name)
    catch e
        e isa MathReadingException || e isa ErrorException || rethrow()
        error("the name ", repr(formula.name), " does not read as a function of ", found[1], ": ",
              sprint(showerror, e))
    end
    nothing
end

"""
    evaluate_formula(formula, env; scratch = Module(:FormulaScratch)) -> value

The value of `formula` now: its code evaluated in the module `scratch`, inside a
`let` that binds each free name that resolves in `env` to the value of that
formula now. The scope binds last, so a formula named `pi` means that formula and
not `Base.pi`. It reads the value of each dependency with
[`get_formula_value`](@ref), so in a cell it records the dependency, and a change
of it computes this formula again. It runs the code of the person on the task
that calls it, so no print calls it.

An error that the code raises, a dependency whose value is a `FormulaError`,
and a formula that depends on itself give a `FormulaError`.
"""
function evaluate_formula(formula::FormulaFormula, env::FormulaEnvironment;
                          scratch::Module = _make_formula_scratch_module())
    _depends_on_itself(formula, env) && return FormulaError("#CYCLE!")
    try
        bindings = Pair{Symbol,Any}[]
        for name in get_formula_names(formula)
            dependency = resolve(env, name)
            dependency === nothing && continue
            value = get_formula_value(dependency)
            value isa FormulaError && return value
            push!(bindings, Symbol(name) => value)
        end
        _run_formula_code(scratch, convert_formula_to_expr(formula, env), bindings)
    catch e
        FormulaError("#ERROR! " * sprint(showerror, e))
    end
end

# Run the `Expr` of the code of a formula in `scratch`, with each binding as a
# local of a `let`. An error that the code raises is a `FormulaError`.
function _run_formula_code(scratch::Module, expression, bindings::Vector{Pair{Symbol,Any}})
    try
        lets = Expr[Expr(:(=), name, QuoteNode(value)) for (name, value) in bindings]
        Core.eval(scratch, Expr(:let, Expr(:block, lets...), expression))
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
        for name in _find_readable_names(node)
            target = resolve(env, name)
            target === formula && return true
            target === nothing || push!(pending, target)
        end
    end
    false
end

# The free names of a formula that the evaluation can read. A math tree with no
# reading has none, and its own evaluation says why.
function _find_readable_names(formula::FormulaFormula)
    try
        return get_formula_names(formula)
    catch e
        e isa MathReadingException || e isa ErrorException || rethrow()
    end
    String[]
end

"""
    get_formula_value(formula) -> Any

The value of a formula for its code and its inputs now: any value its code
computes, or a `FormulaError`. It computes the value on the task that calls it
when the code or an input changed since the last read, so code that adds a
formula and reads its value at once gets it. Reading it inside a reactive cell
subscribes to it. A view reads the stored value with
[`get_formula_result`](@ref), never this.

Use it to read the number that a formula of a sheet computed, such as a blocking
probability or a mean queue length: to compare it with a measured value, to print
it, or to state an expectation from it.

# Example

    sheet_1 = get_edited_document(find_pane("queue.pred"))
    p_block_1 = sheet_1.formulas[2]
    println(get_formula_value(p_block_1))

See also `get_edited_document`, `print_natural_text`.
"""
function get_formula_value end

get_formula_value(formula::FormulaFormula) = formula.current_value
get_formula_value(formula::ReferencedDocument) = get_formula_value(get_document(formula))

"""
    (formula::FormulaFormula)(x) -> Any

Call the function that `formula` holds, as `S_pure(0.5)` for the formula
`S_{pure}(G)` of a sheet. The formula follows one rule: a computation never runs
the code of a formula, and reads the stored value.

- Outside a computation, as in a script, a verb or a code unit, the call takes
  [`get_formula_value`](@ref), computed on the calling task for the code and the
  inputs now.
- Inside a computation, as in the print of a chart, the call takes the stored
  value of the last computation, read as a cell, so a new value draws again. While
  a computation of the formula runs, the call takes the stored function of the
  old code and marks the computation provisional, because a newer value comes
  later. A formula with no stored value yet raises "has no value yet".

An error value raises an `ErrorException` with its text, and a value that is no
function raises an `ArgumentError`. A `ReferencedDocument` of a formula, such as
one read back from a study, calls the formula it refers to.
"""
function (formula::FormulaFormula)(x)
    value = is_computation_running() ? _read_stored_formula_value(formula) : get_formula_value(formula)
    value isa FormulaError && throw(ErrorException(value.text))
    value isa Function || throw(ArgumentError(formula.name * " is no function of one number"))
    Base.invokelatest(value, x)
end

(formula::ReferencedDocument)(x) = get_document(formula)(x)

# The stored value of `formula` as a computation reads it: a read that subscribes,
# provisional while a computation of the formula runs.
function _read_stored_formula_value(formula::FormulaFormula)
    value = formula.result
    value === nothing && throw(ErrorException(formula.name * " has no value yet"))
    formula.is_computing && mark_computation_provisional!()
    value
end

"""
    get_formula_result(formula) -> Any

The value that the last computation of `formula` stored, which a view shows, or
`nothing` before the first one. It runs no code.
"""
get_formula_result(formula::FormulaFormula) = formula.result

# Whether the stored value of a formula is a function, which a row shows as its
# equation and no value.
_has_function_value(formula::FormulaFormula) = formula.result isa Function

# The value of a formula as one line of text, short enough to read beside its
# code: a float to six digits, nothing as no text, and any other value in its
# `text/plain` form, or in its compact form when that form takes more lines.
# The stored value of a formula as a view shows it, with the mark `⋯` while a
# computation of it runs.
function _format_stored_formula_value(formula::FormulaFormula)
    text = _formula_value_text(formula.result)
    formula.is_computing ? (isempty(text) ? "⋯" : text * " ⋯") : text
end

_formula_value_text(value::AbstractFloat) = string(round(value; sigdigits = 6))
_formula_value_text(::Nothing) = ""
# A function has no one-line text: a row shows its equation and no value.
_formula_value_text(::Function) = ""
function _formula_value_text(value)
    text = sprint(show, MIME("text/plain"), value)
    occursin('\n', text) && (text = sprint(show, value; context = :compact => true))
    String(first(split(text, '\n')))
end

"""
    wire_result!(formula, env) -> formula

Wire `formula.current_value` to the code and the inputs of `formula` in `env`:
a read computes it again after a change of the code or of the value of a
dependency, in a scratch module of the formula. Idempotent.
"""
function wire_result!(formula::FormulaFormula, env::FormulaEnvironment)
    scratch = _make_formula_scratch_module()
    set_cell_computation!(getfield(formula, :current_value),
                          () -> evaluate_formula(formula, env; scratch))
    formula
end

# ── What a formula owes its file ─────────────────────────────────────────────
#
# A formula holds its code as a Julia tree and its value as a stored one. A
# `.pred` file holds the code as the text a person wrote, and no value: the sheet
# computes it again when its window acquires it. A sheet writes its formulas, one
# block each.

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
its value computes against the names the file wrote.
"""
function make_pred_document(::Type{<:FormulaEnvironment}, positional, keywords)
    fields = Dict{Symbol,Any}(keywords)
    formulas = Base.length(positional) >= 1 ? positional[1] : get(fields, :formulas, Any[])
    FormulaEnvironment(Vector{Any}(formulas))
end
