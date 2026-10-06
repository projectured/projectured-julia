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
A citation of another formula, held *by identity*. The projection renders
`target.name` reactively, so renames track without a rewrite pass.
"""
@document struct FormulaReference <: FormulaDocument
    target::Document
end

"""
A named formula: `name` (display name — a `String` or a derived thunk `Cell`),
`code` (a `JuliaDocument` that may contain `FormulaReference`s), `result` (the
computed result document), `display_mode` (`:code`/`:result`/`:both`).
`result` is wired to `Cell(@computation evaluate_formula(self, env))` once placed
in an environment; see [`wire_result!`](@ref).
"""
@document struct FormulaFormula <: FormulaDocument
    name::String
    code::Document
    result::Document
    display_mode::Symbol = :both
end

# Convenience: build a result document from a value.
make_formula_result_text(s) = TextBlock(TextString(_value_string(s)))

_value_string(s::AbstractString) = String(s)
_value_string(x) = string(x)

# Mixed positional+keyword form (name/code positional, result/display_mode
# keywords) the @document macro can't generate. `name` may be a String or a Cell
# (a derived thunk); the inner ctor passes a Cell through unchanged.
function FormulaFormula(name, code::Document;
                        result::Document = make_formula_result_text(""),
                        display_mode::Symbol = :both)
    name_cell = name isa Cell ? name : Cell(name isa AbstractString ? String(name) : name)
    FormulaFormula(name_cell, Cell(code), Cell(result), Cell(display_mode), Cell(nothing))
end

"""
Named-formula scope: an ordered set of `FormulaFormula`s (a spreadsheet
*sheet*). Each contained formula's `result` is wired to a reactive thunk
against this environment.
"""
@document struct FormulaEnvironment <: FormulaDocument
    formulas::CellVector = CellVector()
end
function FormulaEnvironment(formulas::Vector)
    env = FormulaEnvironment(CellVector(Cell[Cell(f) for f in formulas]), Cell(nothing))
    for f in formulas
        f isa FormulaFormula && wire_result!(f, env)
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
        f isa FormulaFormula || continue
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
    get_formula_references(code) -> Vector{FormulaReference}

Walk the Julia body `code`, collecting every `FormulaReference` leaf.
"""
function get_formula_references(code)
    refs = FormulaReference[]
    _collect_references!(refs, code)
    refs
end

function _collect_references!(refs::Vector{FormulaReference}, node)
    node isa FormulaReference && (push!(refs, node); return)
    node isa Document || return
    for fname in fieldnames(typeof(node))
        is_view_state_field(fname) && continue
        child = getfield(node, fname)[]   # read the Cell value
        _collect_child!(refs, child)
    end
    return
end

function _collect_child!(refs, child)
    if child isa CellVector
        for c in child
            _collect_child!(refs, c)
        end
    elseif child isa Document
        _collect_references!(refs, child)
    end
    return
end

"""
    get_formula_dependencies(formula) -> Vector{FormulaFormula}

The distinct target formulas referenced (directly) by `formula.code`.
"""
function get_formula_dependencies(formula::FormulaFormula)
    deps = FormulaFormula[]
    for r in get_formula_references(formula.code)
        t = r.target
        if t isa FormulaFormula && !(t in deps)
            push!(deps, t)
        end
    end
    deps
end

"""
    get_formula_dependencies(formula, env) -> Vector{FormulaFormula}

The formulas `formula` depends on in `env`: the targets of its references, and
every formula of the sheet that a plain name in its code resolves to.

A name binds because a file holds names and not identities. A sheet read from a
`.pred` file says `code = "(1 - rho) * rho^n"`, and `rho` is the formula of
that name in the same sheet. A reference by identity keeps what it has: a
rename tracks it, and a name written in the code does not.
"""
function get_formula_dependencies(formula::FormulaFormula, env::FormulaEnvironment)
    deps = get_formula_dependencies(formula)
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

Every plain name the Julia body `code` reads: each `JuliaIdentifier` that is
not the callee of a call and not the field of a field access. A callee names a
function and a field names a slot; neither is a value a sheet holds.
"""
function get_formula_names(code)
    names = String[]
    code isa PrimitiveNumber && return names
    _collect_names!(names, code isa MathDocument ? convert_math_to_julia(code) : code)
    names
end

function _collect_names!(names::Vector{String}, node)
    if node isa JuliaIdentifier
        node.name in names || push!(names, node.name)
        return
    end
    node isa Document || return
    for fname in fieldnames(typeof(node))
        is_view_state_field(fname) && continue
        node isa JuliaCall && fname === :callee &&
            getfield(node, :callee)[] isa JuliaIdentifier && continue
        node isa JuliaFieldAccess && fname === :field && continue
        child = getfield(node, fname)[]
        if child isa CellVector
            for c in child
                _collect_names!(names, c)
            end
        elseif child isa Document
            _collect_names!(names, child)
        end
    end
    return
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
        f isa FormulaFormula && visit(f)
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

# Cycle safety net: the set of formulas currently being evaluated. Re-entering a
# formula mid-evaluation yields an explicit error rather than looping. (Static
# rejection in the reader means this should never trigger in normal use.)
const _EVALUATING = Set{FormulaFormula}()

"""
    convert_formula_to_expr(code, env) -> Expr | literal

Walk the Julia body `code` to a native Julia `Expr` (the inverse of
`parse_julia`), mapping each `FormulaReference` to a `Symbol` bound to its
target's name. The result is evaluated inside a `let` that binds those names to
the targets' values.
"""
convert_formula_to_expr(code, env::FormulaEnvironment) = _to_expr(code)
# A math tree evaluates through its Julia reading, and a bare number is its value.
convert_formula_to_expr(code::MathDocument, env::FormulaEnvironment) =
    _to_expr(convert_math_to_julia(code))
convert_formula_to_expr(code::PrimitiveNumber, env::FormulaEnvironment) = code.value

function _to_expr(node)
    if node isa FormulaReference
        t = node.target
        t isa FormulaFormula || error("FormulaReference target is not a formula")
        return Symbol(get_formula_key(t.name))
    elseif node isa JuliaInteger
        return node.value
    elseif node isa JuliaFloat
        return node.value
    elseif node isa JuliaString
        return node.value
    elseif node isa JuliaBool
        return node.value
    elseif node isa JuliaChar
        return node.value
    elseif node isa JuliaNothing
        return nothing
    elseif node isa JuliaSymbol
        return QuoteNode(Symbol(node.name))
    elseif node isa JuliaIdentifier
        return Symbol(node.name)
    elseif node isa JuliaBinaryOperation
        return Expr(:call, node.operator, _to_expr(node.left), _to_expr(node.right))
    elseif node isa JuliaUnaryOperation
        return Expr(:call, node.operator, _to_expr(node.operand))
    elseif node isa JuliaCall
        arguments = Any[_to_expr(a) for a in node.arguments]
        isempty(node.keyword_arguments) && return Expr(:call, _to_expr(node.callee), arguments...)
        # A keyword after `;` is `k = v`, which the call reads as `Expr(:kw, …)`.
        keywords = Any[(k = _to_expr(k); k isa Expr && k.head === :(=) ? Expr(:kw, k.args...) : k)
                       for k in node.keyword_arguments]
        return Expr(:call, _to_expr(node.callee), Expr(:parameters, keywords...), arguments...)
    elseif node isa JuliaRange
        s = node.step
        return s === nothing ?
            Expr(:call, :(:), _to_expr(node.start), _to_expr(node.stop)) :
            Expr(:call, :(:), _to_expr(node.start), _to_expr(s), _to_expr(node.stop))
    elseif node isa JuliaIndex
        return Expr(:ref, _to_expr(node.collection),
                    Any[_to_expr(i) for i in node.indices]...)
    elseif node isa JuliaFieldAccess
        f = node.field
        fname = f isa JuliaIdentifier ? Symbol(f.name) : _to_expr(f)
        return Expr(:., _to_expr(node.object), QuoteNode(fname))
    elseif node isa JuliaTuple
        return Expr(:tuple, Any[_to_expr(e) for e in node.elements]...)
    elseif node isa JuliaArray
        return Expr(:vect, Any[_to_expr(e) for e in node.elements]...)
    elseif node isa JuliaTernary
        return Expr(:if, _to_expr(node.condition),
                    _to_expr(node.then_branch), _to_expr(node.else_branch))
    elseif node isa JuliaIf
        return Expr(:if, _to_expr(node.condition),
                    _to_expr(node.then_branch), _to_expr(node.else_branch))
    elseif node isa JuliaBlock
        return Expr(:block, Any[_to_expr(s) for s in node.statements]...)
    elseif node isa JuliaAssignment
        return Expr(node.operator, _to_expr(node.target), _to_expr(node.value))
    else
        error("convert_formula_to_expr: unsupported node $(typeof(node))")
    end
end

"""
    evaluate_formula(formula, env) -> result document

Evaluate `formula.code` in a sandbox module with every referenced formula's name
bound to its (recursively evaluated) value, returning a result document
(`TextBlock`). Reading a dependency's `result` inside this thunk registers the
reactive dependency. A re-entry guard returns an error result on a cycle.
"""
function evaluate_formula(formula::FormulaFormula, env::FormulaEnvironment)
    if formula in _EVALUATING
        return make_formula_result_text("#CYCLE!")
    end
    push!(_EVALUATING, formula)
    try
        deps = get_formula_dependencies(formula, env)
        # Bind each dependency name to its evaluated value. Reading dep.result
        # here is the reactive subscription that triggers recompute on change.
        bindings = Expr[]
        for d in deps
            val = _result_value(d.result)
            push!(bindings, Expr(:(=), Symbol(get_formula_key(d.name)), QuoteNode(val)))
        end
        body = convert_formula_to_expr(formula.code, env)
        letex = Expr(:let, Expr(:block, bindings...), body)
        value = Core.eval(_formula_scratch_module(), letex)
        return make_formula_result_text(value)
    catch e
        return make_formula_result_text("#ERROR! " * sprint(showerror, e))
    finally
        delete!(_EVALUATING, formula)
    end
end

"""
    get_formula_value(formula) -> Any

The value a formula's result stands for: a number, a bool, or the text of an
error or a cycle. Reading it inside a reactive cell subscribes to the result.

Use it to read the number a formula of a study's sheet computed — a blocking
probability, a mean queue length — to compare it with a result, to print it, or
to state an expectation from it.

# Example

    p_block = add_study_formula!(get_study(), "p_{block}", "((1 - ρ) ρ^n)/(1 - ρ^(n + 1))")
    println(get_formula_value(p_block))

See also `add_study_formula!`, `add_expectation!`.
"""
get_formula_value(formula::FormulaFormula) = _result_value(formula.result)

# Read the scalar value out of a result document (a TextBlock of one TextString).
# This is what a dependent formula consumes; parse it back to a number/bool/string.
function _result_value(result)
    s = _result_string(result)
    startswith(s, "#") && return s   # propagate error/cycle markers as strings
    v = tryparse(Int, s)
    v !== nothing && return v
    f = tryparse(Float64, s)
    f !== nothing && return f
    s == "true" && return true
    s == "false" && return false
    return s
end

function _result_string(result)
    result isa TextBlock || return string(result)
    buf = IOBuffer()
    for span in result.elements
        span isa TextString && print(buf, span.content)
    end
    String(take!(buf))
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
