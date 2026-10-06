# Fragment of `PivotModule`.
#
# The edits of the zones of a pivot: a move of a dimension in its zone or to
# another zone, a new measure from a dimension, and the removal of an item. Each
# is an operation with an inverse, so undo takes it back: a move is a
# `MoveRangeOperation`, which keeps the cell of the item, and an insert or a
# removal of a measure is a splice of `ReplaceReferencedValueOperation`. The keys
# act on the item that the selection names, and a drop acts on the item that
# the drag carries.

# The fields of the zones, in the order of the rows of the bar. The first four
# hold dimensions, and the last holds measures.
const _PIVOT_ZONE_FIELDS = ("unused_dimensions", "column_dimensions", "row_dimensions", "cell_dimensions",
                            "measures")
const _PIVOT_DIMENSION_ZONE_COUNT = 4

# The zone and the place of the item that `path`, a path of a pivot, names:
# `(field, index)` for `<zone>[i]…`; `nothing` for any other path.
function _find_pivot_zone_item(path)
    path isa Reference || return nothing
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name in _PIVOT_ZONE_FIELDS) ||
        return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep && is_element_reference_step(tail.head)) ||
        return nothing
    (path.head.name, tail.head.stop)
end

# The zone that `path` names as a whole, `<zone>` with nothing after it, or
# `nothing`.
function _find_pivot_zone(path)
    path isa Reference || return nothing
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name in _PIVOT_ZONE_FIELDS &&
     path.tail isa EmptyReference) || return nothing
    path.head.name
end

_make_pivot_zone_item_path(field::String, index::Int) =
    ConcreteReference(FieldReferenceStep(field), ConcreteReference(ElementReferenceStep(index), EmptyReference()))

_make_pivot_zone_path(field::String) = ConcreteReference(FieldReferenceStep(field), EmptyReference())

_get_pivot_zone(pivot::PivotTable, field::String) = getproperty(pivot, Symbol(field))

# The number of a zone in the order of the bar.
_get_pivot_zone_number(field::String) = findfirst(==(field), _PIVOT_ZONE_FIELDS)

# The aggregate of a new measure of `column`: the sum of a column of numbers, and
# the count of any other column.
function _get_default_aggregate(pivot::PivotTable, column::String)
    type = nonmissingtype(get_table_column_type(pivot.source, column))
    (type <: Real && !(type <: Bool)) ? :sum : :count
end

# The move of the item at place `index` of the zone `from` to the place `to` of
# the zone `into`, where `to` counts the places before the move, and the
# selection of the item where it lands.
function _make_pivot_item_move(pivot::PivotTable, from::String, index::Int, into::String, to::Int)
    source = _get_pivot_zone(pivot, from)
    destination = _get_pivot_zone(pivot, into)
    to = clamp(to, 1, length(destination) + 1)
    landed = (from == into && to > index) ? to - 1 : to
    (from == into && landed == index) && return nothing
    CompoundOperation(Any[MoveRangeOperation(source, index, index, destination, to),
                          ReplaceSelectionOperation(_make_pivot_zone_item_path(into, landed))])
end

# A new measure of the column of `dimension` at place `to` of the measures, and
# its selection. The dimension stays where it is.
function _make_pivot_measure_insert(pivot::PivotTable, dimension::PivotDimension, to::Int)
    to = clamp(to, 1, length(pivot.measures) + 1)
    measure = PivotMeasure(dimension.column, _get_default_aggregate(pivot, dimension.column))
    CompoundOperation(Any[
        ReplaceReferencedValueOperation(pivot, Reference(FieldReferenceStep("measures"), RangeReferenceStep(to - 1, to - 1)),
                                        Any[measure]),
        ReplaceSelectionOperation(_make_pivot_zone_item_path("measures", to))])
end

# The removal of the measure at place `index`, and the selection of the measure
# that takes its place, or of the zone when none does.
function _make_pivot_measure_removal(pivot::PivotTable, index::Int)
    count = length(pivot.measures)
    selection = count == 1 ? _make_pivot_zone_path("measures") :
                             _make_pivot_zone_item_path("measures", min(index, count - 1))
    CompoundOperation(Any[
        ReplaceReferencedValueOperation(pivot, Reference(FieldReferenceStep("measures"), RangeReferenceStep(index - 1, index)),
                                        Any[]),
        ReplaceSelectionOperation(selection)])
end

# ── The keys ─────────────────────────────────────────────────────────────────

# Alt+Left and Alt+Right: the selected item one place earlier or later in its zone.
function _make_pivot_item_shift(pivot::PivotTable, step::Int)
    found = _find_pivot_zone_item(pivot.selection)
    found === nothing && return nothing
    field, index = found
    target = index + step
    1 <= target <= length(_get_pivot_zone(pivot, field)) || return nothing
    _make_pivot_item_move(pivot, field, index, field, step > 0 ? target + 1 : target)
end

# Alt+Up and Alt+Down: the selected dimension into the zone above or below, at
# the same place or at the end. Down from the cell dimensions adds a measure of
# its column and keeps the dimension.
function _make_pivot_item_zone_move(pivot::PivotTable, step::Int)
    found = _find_pivot_zone_item(pivot.selection)
    found === nothing && return nothing
    field, index = found
    number = _get_pivot_zone_number(field)
    number > _PIVOT_DIMENSION_ZONE_COUNT && return nothing
    target = number + step
    1 <= target <= length(_PIVOT_ZONE_FIELDS) || return nothing
    into = _PIVOT_ZONE_FIELDS[target]
    into == "measures" && return _make_pivot_measure_insert(pivot, _get_pivot_zone(pivot, field)[index],
                                                            length(pivot.measures) + 1)
    _make_pivot_item_move(pivot, field, index, into, index)
end

# Delete: a dimension of the columns, the rows or the cells back to the fields,
# and a measure out of the pivot.
function _make_pivot_item_removal(pivot::PivotTable)
    found = _find_pivot_zone_item(pivot.selection)
    found === nothing && return nothing
    field, index = found
    field == "measures" && return _make_pivot_measure_removal(pivot, index)
    field == "unused_dimensions" && return nothing
    _make_pivot_item_move(pivot, field, index, "unused_dimensions", length(pivot.unused_dimensions) + 1)
end

@gestures PivotTable begin
    KeyDown(:left; alt) => "Move the field one place to the left" => _make_pivot_item_shift(doc, -1)
    KeyDown(:right; alt) => "Move the field one place to the right" => _make_pivot_item_shift(doc, 1)
    KeyDown(:up; alt) => "Move the field to the row above" => _make_pivot_item_zone_move(doc, -1)
    KeyDown(:down; alt) => "Move the field to the row below" => _make_pivot_item_zone_move(doc, 1)
    KeyDown(:delete) => "Take the field out of its row" => _make_pivot_item_removal(doc)
end

# ── The drop ─────────────────────────────────────────────────────────────────

# The edit of a drop of the item at `source`, `(field, index)`, at `target`,
# `(field, place)`: a dimension moves between the zones of dimensions, and gives
# a new measure in the measures; a measure moves among the measures, and goes out
# of the pivot anywhere else. `nothing` for no target.
function _make_pivot_drop_operation(pivot::PivotTable, source, target)
    (source === nothing || target === nothing) && return nothing
    from, index = source
    into, place = target
    if from == "measures"
        into == "measures" && return _make_pivot_item_move(pivot, from, index, into, place)
        return _make_pivot_measure_removal(pivot, index)
    end
    into == "measures" && return _make_pivot_measure_insert(pivot, _get_pivot_zone(pivot, from)[index], place)
    _make_pivot_item_move(pivot, from, index, into, place)
end
