# Fragment of `FormulaModule` — a formula on the page: its equation, and its
# value beside it.
#
# A formula with math code draws as the assignment of its name to its code,
# through the math domain's own boxes, with a label of its value after it. A
# formula with Julia code draws as one line of text: the name, the code and
# the value. A sheet draws its formulas as a column. Each row ends in a plain
# layout stage, so the equation and the label re-enter the renderer of the
# page they stand in.

"""
    FormulaFormulaToLayout()

Printer-only projection `FormulaFormula → HorizontalLayout`: the equation and
its value. Reads the name, the code and the result inside the printer, so a
changed input redraws the row.
"""
struct FormulaFormulaToLayout <: Projection end

function print_document(p::FormulaFormulaToLayout, recursion, formula::FormulaFormula, ctx)
    name = formula.name
    code = formula.code
    value = _formula_value_text(get_formula_value(formula))
    children = if is_math_code(code)
        Any[MathAssignment(_formula_name_tree(name), code),
            WidgetLabel( "= " * value)]
    else
        Any[WidgetLabel( name * " = " * print_natural_text(code) * " = " * value)]
    end
    SimpleIoMap(p, formula, HorizontalLayout(children))
end

"""
    FormulaEnvironmentToLayout()

Printer-only projection `FormulaEnvironment → VerticalLayout`: one row per
formula, each drawn by its own projection.
"""
struct FormulaEnvironmentToLayout <: Projection end

print_document(p::FormulaEnvironmentToLayout, recursion, env::FormulaEnvironment, ctx) =
    SimpleIoMap(p, env, VerticalLayout(Any[formula for formula in env.formulas]))

# The name of a formula as a math tree: `p_{block}` draws with its subscript.
# A name the reader cannot read draws as text.
function _formula_name_tree(name::AbstractString)
    try
        return parse_math(String(name))
    catch e
        e isa ErrorException || rethrow()
    end
    MathText(String(name))
end

# A value, short enough to read beside an equation.
_formula_value_text(value::AbstractFloat) = string(round(value; sigdigits = 6))
_formula_value_text(value) = string(value)

"""
    make_formula_graphics_entry(; measure) -> Vector{Pair{Type,Any}}

The renderer rows that make a formula and a sheet draw themselves on any page.
"""
make_formula_graphics_entry(; measure = nothing) = Pair{Type,Any}[
    FormulaFormula     => ChainingProjection(FormulaFormulaToLayout(), HorizontalLayoutToGraphicsCanvas()),
    FormulaEnvironment => ChainingProjection(FormulaEnvironmentToLayout(), VerticalLayoutToGraphicsCanvas()),
]
