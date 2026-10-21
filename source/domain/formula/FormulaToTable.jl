# Fragment of `FormulaModule` — a sheet as the grid of a spreadsheet: the value of
# each formula whose name is a cell name, in the cell that the name names.

"""
    FormulaEnvironmentToTable()

Printer-only projection `FormulaEnvironment → WidgetTable`: the grid of a
spreadsheet. A formula whose name is a cell name, such as `B3`, shows its stored
value in column `B` and row `3`, with a mark while a computation of it runs. A
text value shows without its quotes. The grid has a column for each letter and a
row for each number up to the last cell that a name names; a formula with another
name is not in the grid. It runs no code of a formula.
"""
struct FormulaEnvironmentToTable <: Projection end

function print_document(p::FormulaEnvironmentToTable, recursion, env::FormulaEnvironment, ctx)
    cells = Dict{Tuple{Int,Int},FormulaFormula}()
    for formula in env.formulas
        index = _find_cell_index(formula.name)
        # The first formula of a name is the one that the name resolves to.
        index === nothing || haskey(cells, index) || (cells[index] = formula)
    end
    column_count = maximum(first, keys(cells); init = 0)
    row_count = maximum(last, keys(cells); init = 0)
    table = WidgetTable(;
        column_headers = Any[WidgetLabel(get_column_letter(column)) for column in 1:column_count],
        row_headers = Any[WidgetLabel(string(row)) for row in 1:row_count],
        cells = Any[Any[_make_grid_cell(get(cells, (column, row), nothing)) for column in 1:column_count]
                    for row in 1:row_count])
    SimpleIoMap(p, env, table)
end

# The column and the row of the cell that `name` names in the A1 style, such as
# `(2, 3)` for `B3`, or `nothing` when `name` is no cell name.
function _find_cell_index(name::AbstractString)
    found = match(r"^([A-Z]+)([1-9][0-9]*)$", name)
    found === nothing && return nothing
    column = 0
    for letter in found[1]
        column = 26 * column + (letter - 'A' + 1)
    end
    (column, parse(Int, found[2]))
end

# A cell of the grid: the stored value of `formula`, which the label reads, so a
# new value draws only its own cell again; an empty cell for no formula.
_make_grid_cell(::Nothing) = WidgetLabel("")
_make_grid_cell(formula::FormulaFormula) =
    WidgetLabel(() -> _format_grid_value(formula); tooltip = () -> _make_grid_cell_note(formula))

# What a cell says when the pointer rests on it: the name and the code of its
# formula, the type of the stored result, and that a computation of it runs.
function _make_grid_cell_note(formula::FormulaFormula)
    facts = Any["Type" => formula.result === nothing ? "not computed" : string(typeof(formula.result))]
    formula.is_computing && push!(facts, "Computing" => "yes")
    TooltipNote(; title = formula.name, code = print_natural_text(formula.code), facts)
end

function _format_grid_value(formula::FormulaFormula)
    value = formula.result
    value isa AbstractString || return _format_stored_formula_value(formula)
    formula.is_computing ? value * " ⋯" : String(value)
end
