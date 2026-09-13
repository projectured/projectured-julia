"""
    FormulaModule

The Formula domain — named, cross-referencing, evaluated formulas whose code
is a Julia expression (the spreadsheet idea generalised). Each formula's
`result` is a reactive `Cell` evaluating the Julia body against a named
environment; other formulas cite each other by identity.
"""
module FormulaModule

import ..CellModule: Cell, ComputedCell, set_cell_function!, set_cell_value!
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector, ComputedCellVector
import ..ReferenceModule: Reference
import ..TextModule: TextBlock, TextString
import ..JuliaModule: JuliaDocument,
                      JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
                      JuliaNothing, JuliaSymbol, JuliaChar,
                      JuliaBinaryOperation, JuliaUnaryOperation, JuliaCall, JuliaTernary,
                      JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
                      JuliaTypeAnnotation, JuliaAssignment, JuliaForIterator, JuliaFor,
                      JuliaWhile, JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry,
                      JuliaBegin, JuliaIf, JuliaFunction, JuliaBlock, _julia_operator_string
export FormulaDocument, make_formula_result_text, wire_result!, resolve, get_column_letter, get_cell_name,
       get_formula_references, get_formula_dependencies, would_create_cycle, compute_topological_order,
       convert_formula_to_expr, evaluate_formula
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..TextModule: TextString
import ..StyleModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..StyleModule: StyleColor, color_default, color_solarized_blue, color_solarized_cyan,
                      color_solarized_green, color_solarized_magenta, color_solarized_gray,
                      color_solarized_violet
import ..StyleModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapModule: IoMap
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep,
                          RangeReferenceStep, FieldReferenceStep,
                          Reference, EmptyReference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference", var"@reference_step"
import ..PrinterContextModule: make_child_context
import ..JuliaModule: JuliaToSyntax
export FormulaInsertionToSyntaxLeaf, FormulaReferenceToSyntaxLeaf,
       FormulaFormulaToSyntaxNode, FormulaEnvironmentToSyntaxNode, FormulaToSyntax
export FormulaInsertion, FormulaReference




abstract type FormulaDocument <: Document end

"""
The Formula domain's type-in entry point: text typed on Enter parses into a
`FormulaFormula`.
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
`result` is wired to `ComputedCell(() -> evaluate_formula(self, env))` once placed in an
environment; see [`wire_result!`](@ref).
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
    for f in env.formulas
        f isa FormulaFormula || continue
        f.name == name && return f
    end
    return nothing
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
        for d in get_formula_dependencies(n)
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
        for d in get_formula_dependencies(n)
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
    convert_formula_to_expr(code, env) -> Expr | literal

Walk the Julia body `code` to a native Julia `Expr` (the inverse of
`parse_julia`), mapping each `FormulaReference` to a `Symbol` bound to its
target's name. The result is evaluated inside a `let` that binds those names to
the targets' values.
"""
convert_formula_to_expr(code, env::FormulaEnvironment) = _to_expr(code)

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
    elseif node isa JuliaBinaryOperation
        return Expr(:call, node.operator, _to_expr(node.left), _to_expr(node.right))
    elseif node isa JuliaUnaryOperation
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
        deps = get_formula_dependencies(formula)
        # Bind each dependency name to its evaluated value. Reading dep.result
        # here is the reactive subscription that triggers recompute on change.
        bindings = Expr[]
        for d in deps
            val = _result_value(d.result)
            push!(bindings, Expr(:(=), Symbol(d.name), QuoteNode(val)))
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
    set_cell_function!(getfield(formula, :result), () -> evaluate_formula(formula, env))
    formula
end


include("FormulaToSyntax.jl")

end # module
