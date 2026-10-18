# Fragment of `ProjectionModule` — what a print shows while a value is still to
# come: a cell that keeps its last final value while its value is provisional, so
# a drawing does not jump while a task computes the values below it.

"""
    make_final_holding_cell(compute; is_usable = value -> true) -> Cell

A cell that answers `compute()` when that value is final, and, while it is
provisional (`is_cell_provisional`), the last final value that it answered, when
`is_usable` accepts that value; else the provisional value. The cell is
provisional while `compute()` is, so a reader can tell that a newer value comes,
and it computes again when the values below it come.

Use it where a print must not jump while values come, such as the order of a sort
whose keys a task still reads: the table keeps its last order until the sort is
final. A value that never was final shows as it is, so a label shows its default
until its value comes.

# Example

    rows = make_final_holding_cell(() -> sortperm([key(item) for item in items]);
                                   is_usable = rows -> length(rows) == length(items))

The last final value is a collector outside the graph: only a final computation
of this cell changes it, so the cell answers the same for the same values below
it.
"""
function make_final_holding_cell(compute::Function; is_usable::Function = _ -> true)
    computed = Cell(Computation(compute))
    held = _HeldFinalValue(false, nothing)
    Cell(@computation _compute_held_value(computed, held, is_usable))
end

mutable struct _HeldFinalValue
    has_value::Bool
    value::Any
end

function _compute_held_value(computed::Cell, held::_HeldFinalValue, is_usable::Function)
    value = computed[]
    if !is_cell_provisional(computed)
        held.has_value = true
        held.value = value
        return value
    end
    held.has_value && is_usable(held.value) ? held.value : value
end
