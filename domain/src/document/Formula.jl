"""
    FormulaModule

A domain for **named, cross-referencing, evaluated formulas** whose code is a
Julia expression — the spreadsheet idea generalised. A formula is an ordinary
`Document`: its body reuses the `Julia` domain, it carries a name (the
spreadsheet's `A1`), and other formulas refer to it by identity and display its
current name. Each formula's `result` is a reactive `Cell` evaluating the Julia
body with referenced formulas bound to their values.

Types:

- `FormulaFormula`     — a named formula: `name` + `code` (a `JuliaDocument`) +
                         a reactive `result` document + a `display_mode`.
- `FormulaReference`   — a citation of another formula, held by identity; the
                         projection renders `target.name`, so renames track.
- `FormulaEnvironment` — the resolution / evaluation scope: the set of named
                         formulas (the analogue of a spreadsheet *sheet*).
- `FormulaInsertion`   — the per-domain type-in entry point.

Cycle-freeness is enforced two ways: a static DFS (`would_create_cycle`) lets the
reader veto a cycle-introducing edit, and the evaluator keeps a currently-
evaluating set as a safety net that returns an error result rather than looping.
"""
module FormulaModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
import ..TextModule: TextText, TextString
import ..JuliaModule: JuliaDocument,
                      JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
                      JuliaNothing, JuliaSymbol, JuliaChar,
                      JuliaBinaryOp, JuliaUnaryOp, JuliaCall, JuliaTernary,
                      JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
                      JuliaTypeAnnotation, JuliaAssignment, JuliaForIterator, JuliaFor,
                      JuliaWhile, JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry,
                      JuliaBegin, JuliaIf, JuliaFunction, JuliaBlock, _julia_operator_string

export FormulaDocument, FormulaInsertion, FormulaReference, FormulaFormula,
       FormulaEnvironment, formula_result_text, wire_result!,
       resolve, column_letter, cell_name,
       formula_references, formula_dependencies,
       would_create_cycle, topological_order,
       formula_to_expr, evaluate_formula,
       IFormulaInsertion, IFormulaReference, IFormulaFormula, IFormulaEnvironment

# ── Abstract base ────────────────────────────────────────────────────────────

abstract type FormulaDocument <: Document end

# ── FormulaInsertion ─────────────────────────────────────────────────────────

"""
    FormulaInsertion(value="")

The Formula domain's type-in entry point. Holds a buffer of typed text committed
(e.g. on Enter) by parsing an Excel-style `=expr` or a bare `name = expr` into a
`FormulaFormula`.
"""
@document struct FormulaInsertion <: FormulaDocument
    value::String
    selection::Reference
end

FormulaInsertion(value::AbstractString="") =
    FormulaInsertion(Cell(String(value)), Cell(nothing))

# ── FormulaReference ─────────────────────────────────────────────────────────

"""
    FormulaReference(target)

A citation of another formula, held *by identity* (`target` is the referenced
`FormulaFormula`, not a copy of its name). The projection renders `target.name`
reactively, so renaming a formula updates every reference with no rewrite pass.
"""
@document struct FormulaReference <: FormulaDocument
    target::Document
    selection::Reference
end

FormulaReference(target) = FormulaReference(Cell(target), Cell(nothing))

# ── FormulaFormula ───────────────────────────────────────────────────────────

"""
    FormulaFormula(name, code; result, display_mode)

A named formula. `name` is the display name (a literal string, or a `Cell`
holding a derived thunk such as `cell_name(col, row)`); `code` is the body (a
`JuliaDocument` that may contain `FormulaReference`s); `result` is the *computed*
result document; `display_mode` is `:code`, `:result`, or `:both`.

`result` is wired as `Cell(() -> evaluate_formula(self, environment))` once the
formula is placed in an environment (see [`wire_result!`](@ref)); reading a
dependency's value inside that thunk registers the reactive dependency.
"""
@document struct FormulaFormula <: FormulaDocument
    name::String
    code::Document
    result::Document
    display_mode::Symbol
    selection::Reference
end

function FormulaFormula(name, code::Document;
                        result::Document = formula_result_text(""),
                        display_mode::Symbol = :both)
    # `name` may be a literal string OR a Cell (e.g. a derived thunk); the
    # @document inner constructor passes a Cell through unchanged.
    name_cell = name isa Cell ? name : Cell(name isa AbstractString ? String(name) : name)
    FormulaFormula(name_cell, Cell(code), Cell(result), Cell(display_mode), Cell(nothing))
end

# Convenience: build a result document from a value.
formula_result_text(s) = TextText(TextString(_value_string(s)))

_value_string(s::AbstractString) = String(s)
_value_string(x) = string(x)

# ── FormulaEnvironment ───────────────────────────────────────────────────────

"""
    FormulaEnvironment(formulas = [])

The resolution / evaluation scope: an ordered set of `FormulaFormula`s, the
analogue of a spreadsheet *sheet*. Provides name → formula lookup, dependency
extraction, and cycle detection. Each contained formula's `result` is wired to a
reactive thunk against this environment.
"""
@document struct FormulaEnvironment <: FormulaDocument
    formulas::CellVector
    selection::Reference
end

FormulaEnvironment() = FormulaEnvironment(CellVector(), Cell(nothing))
function FormulaEnvironment(formulas::Vector)
    env = FormulaEnvironment(CellVector(Cell[Cell(f) for f in formulas]), Cell(nothing))
    for f in formulas
        f isa FormulaFormula && wire_result!(f, env)
    end
    env
end

Base.length(e::FormulaEnvironment) = length(e.formulas)
Base.isempty(e::FormulaEnvironment) = isempty(e.formulas)
Base.getindex(e::FormulaEnvironment, i::Integer) = e.formulas[i]
Base.firstindex(::FormulaEnvironment) = 1
Base.lastindex(e::FormulaEnvironment) = length(e)
Base.iterate(e::FormulaEnvironment, s...) = iterate(e.formulas, s...)

# ═══════════════════════════════════════════════════════════════════════
# Phase 2 — environment, naming, dependency graph, cycle detection
# ═══════════════════════════════════════════════════════════════════════

"""
    resolve(env, name) -> FormulaFormula | nothing

Look up the formula named `name` in `env` (the first match by current name).
Reads `env.formulas` and each `f.name` reactively.
"""
function resolve(env::FormulaEnvironment, name::AbstractString)
    for f in env.formulas
        f isa FormulaFormula || continue
        f.name == name && return f
    end
    return nothing
end

"""
    column_letter(col::Int) -> String

The spreadsheet column label for 1-based `col`: `1 → "A"`, `26 → "Z"`,
`27 → "AA"`, `28 → "AB"`, `52 → "AZ"`, `53 → "BA"`.
"""
function column_letter(col::Integer)
    col >= 1 || error("column_letter: col must be >= 1, got $col")
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
cell_name(col::Integer, row::Integer) = column_letter(col) * string(row)

"""
    formula_references(code) -> Vector{FormulaReference}

Walk the Julia body `code`, collecting every `FormulaReference` leaf.
"""
function formula_references(code)
    refs = FormulaReference[]
    _collect_references!(refs, code)
    refs
end

function _collect_references!(refs::Vector{FormulaReference}, node)
    node isa FormulaReference && (push!(refs, node); return)
    node isa Document || return
    for fname in fieldnames(typeof(node))
        fname === :selection && continue
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
    formula_dependencies(formula) -> Vector{FormulaFormula}

The distinct target formulas referenced (directly) by `formula.code`.
"""
function formula_dependencies(formula::FormulaFormula)
    deps = FormulaFormula[]
    for r in formula_references(formula.code)
        t = r.target
        if t isa FormulaFormula && !(t in deps)
            push!(deps, t)
        end
    end
    deps
end

"""
    would_create_cycle(env, from, to) -> Bool

True if adding a reference `from → to` would close a cycle, i.e. if `to` can
already reach `from` through the existing dependency graph (or `to === from`).
DFS over `formula_dependencies`.
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
        for d in formula_dependencies(n)
            push!(stack, d)
        end
    end
    return false
end

"""
    topological_order(env) -> Vector{FormulaFormula}

A dependency-first ordering of `env`'s formulas (dependencies before dependents).
Errors if the graph contains a cycle. Useful for batch evaluation and tests.
"""
function topological_order(env::FormulaEnvironment)
    order = FormulaFormula[]
    state = Dict{FormulaFormula,Int}()  # absent/0 = unvisited, 1 = in-progress, 2 = done
    function visit(n)
        s = get(state, n, 0)
        s == 2 && return
        s == 1 && error("topological_order: cycle detected at $(n.name)")
        state[n] = 1
        for d in formula_dependencies(n)
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
# `execute_julia_code` sandbox-eval pattern in editor/Mcp.jl. Dependency values
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
    formula_to_expr(code, env) -> Expr | literal

Walk the Julia body `code` to a native Julia `Expr` (the inverse of
`juliaparse`), mapping each `FormulaReference` to a `Symbol` bound to its
target's name. The result is evaluated inside a `let` that binds those names to
the targets' values.
"""
formula_to_expr(code, env::FormulaEnvironment) = _to_expr(code)

function _to_expr(node)
    if node isa FormulaReference
        t = node.target
        t isa FormulaFormula || error("FormulaReference target is not a formula")
        return Symbol(t.name)
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
    elseif node isa JuliaBinaryOp
        return Expr(:call, node.operator, _to_expr(node.left), _to_expr(node.right))
    elseif node isa JuliaUnaryOp
        return Expr(:call, node.operator, _to_expr(node.operand))
    elseif node isa JuliaCall
        return Expr(:call, _to_expr(node.callee),
                    Any[_to_expr(a) for a in node.arguments]...)
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
        error("formula_to_expr: unsupported node $(typeof(node))")
    end
end

"""
    evaluate_formula(formula, env) -> result document

Evaluate `formula.code` in a sandbox module with every referenced formula's name
bound to its (recursively evaluated) value, returning a result document
(`TextText`). Reading a dependency's `result` inside this thunk registers the
reactive dependency. A re-entry guard returns an error result on a cycle.
"""
function evaluate_formula(formula::FormulaFormula, env::FormulaEnvironment)
    if formula in _EVALUATING
        return formula_result_text("#CYCLE!")
    end
    push!(_EVALUATING, formula)
    try
        deps = formula_dependencies(formula)
        # Bind each dependency name to its evaluated value. Reading dep.result
        # here is the reactive subscription that triggers recompute on change.
        bindings = Expr[]
        for d in deps
            val = _result_value(d.result)
            push!(bindings, Expr(:(=), Symbol(d.name), QuoteNode(val)))
        end
        body = formula_to_expr(formula.code, env)
        letex = Expr(:let, Expr(:block, bindings...), body)
        value = Core.eval(_formula_scratch_module(), letex)
        return formula_result_text(value)
    catch e
        return formula_result_text("#ERROR! " * sprint(showerror, e))
    finally
        delete!(_EVALUATING, formula)
    end
end

# Read the scalar value out of a result document (a TextText of one TextString).
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
    result isa TextText || return string(result)
    buf = IOBuffer()
    for span in result
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
    setfn!(getfield(formula, :result), () -> evaluate_formula(formula, env))
    formula
end

end # module
