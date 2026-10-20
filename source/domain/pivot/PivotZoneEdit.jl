# Fragment of `PivotModule`.
#
# The edits of the zones of a pivot: a move of a dimension in its zone or to
# another zone, a new measure from a dimension, and the removal of an item. Each
# is an operation with an inverse, so undo takes it back: a move is a
# `MoveRangeOperation`, which keeps the cell of the item, and an insert or a
# removal of a measure is a splice of `ReplaceReferencedValueOperation`. The keys
# act on the item that the selection names, a drop acts on the item that the
# drag carries, and the verb of the assistant acts on the field that it names by
# its column.

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
    move = _make_pivot_range_move(pivot, from, index, into, to)
    move === nothing && return nothing
    operation, landed = move
    CompoundOperation(Any[operation, ReplaceSelectionOperation(_make_pivot_zone_item_path(into, landed))])
end

# The `MoveRangeOperation` of the item at place `index` of the zone `from` to the
# place `to` of the zone `into`, where `to` counts the places before the move,
# and the place where the item lands; `nothing` when the item stays where it is.
function _make_pivot_range_move(pivot::PivotTable, from::String, index::Int, into::String, to::Int)
    source = _get_pivot_zone(pivot, from)
    destination = _get_pivot_zone(pivot, into)
    to = clamp(to, 1, length(destination) + 1)
    landed = (from == into && to > index) ? to - 1 : to
    (from == into && landed == index) && return nothing
    (MoveRangeOperation(source, index, index, destination, to), landed)
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

# ── The runs of the rows ─────────────────────────────────────────────────────

# The row and the level of the run of the row headers that `selection` names, a
# part that the view introduced: `(row, level)` for the label of level `level` of
# row `row`; `nothing` for any other selection.
function _find_pivot_row_run(selection)
    selection isa ConcreteReference || return nothing
    selection = strip_reference_types(selection)
    head = selection isa ConcreteReference ? selection.head : nothing
    head isa ProjectionReferenceStep || return nothing
    path = _find_pivot_grid_child_path(head.output_path, 2)
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name == "row_headers") ||
        return nothing
    row = path.tail
    (row isa ConcreteReference && row.head isa RangeReferenceStep) || return nothing
    level = row.tail
    (level isa ConcreteReference && level.head isa RangeReferenceStep) || return nothing
    (row.head.stop, level.head.stop)
end

# Enter on a selected run of an outer row dimension: close it, so it shows only
# its subtotal row, or open it again. In the group layout a group of the last
# row dimension closes too, and shows one row. The selection goes to the first
# row of the run, which the change does not move.
function _make_pivot_run_toggle(pivot::PivotTable)
    found = _find_pivot_row_run(pivot.selection)
    found === nothing && return nothing
    row, level = found
    key = _get_pivot_table_row_key(pivot, row)
    levels = length(pivot.row_dimensions)
    (key !== nothing && (level < levels || (_is_pivot_group_layout(pivot) && level == levels))) ||
        return nothing
    prefix = key[1:level]
    any(value -> value isa PivotTotal, prefix) && return nothing
    collapsed = Any[pivot.collapsed...]
    closed = findfirst(isequal(prefix), collapsed)
    closed === nothing ? push!(collapsed, prefix) : deleteat!(collapsed, closed)
    place = row
    while place > 1
        above = _get_pivot_table_row_key(pivot, place - 1)
        (above !== nothing && isequal(above[1:level], prefix)) || break
        place -= 1
    end
    projection = strip_reference_types(pivot.selection).head.projection
    header = ConcreteReference(FieldReferenceStep("row_headers"), ConcreteReference(RangeReferenceStep(place - 1, place),
        ConcreteReference(RangeReferenceStep(level - 1, level), EmptyReference())))
    CompoundOperation(Any[ReplaceReferencedValueOperation(pivot, "collapsed", collapsed),
                          ReplaceSelectionOperation(ConcreteReference(
                              ProjectionReferenceStep(projection, _make_pivot_grid_reference(2, header)),
                              EmptyReference()))])
end

@gestures PivotTable begin
    KeyDown(:left; alt) => "Move the field one place to the left" => _make_pivot_item_shift(doc, -1)
    KeyDown(:right; alt) => "Move the field one place to the right" => _make_pivot_item_shift(doc, 1)
    KeyDown(:up; alt) => "Move the field to the row above" => _make_pivot_item_zone_move(doc, -1)
    KeyDown(:down; alt) => "Move the field to the row below" => _make_pivot_item_zone_move(doc, 1)
    KeyDown(:delete) => "Take the field out of its row" => _make_pivot_item_removal(doc)
    KeyPress('\n') => "Open or close the run of rows" => _make_pivot_run_toggle(doc)
    splice(_PIVOT_MENU)
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

# ── The verb of the assistant ────────────────────────────────────────────────

# The zones that hold fields, by the names of the rows of the bar.
const _PIVOT_FIELD_ZONES = (fields = "unused_dimensions", columns = "column_dimensions",
                            rows = "row_dimensions", cells = "cell_dimensions")

"""
    move_pivot_field!(pivot, column, zone; place = nothing, editor = get_evaluation_editor())
        -> ReferencedDocument

Move the field of the column `column` of `pivot` into `zone`, at the 1-based
`place` among the fields of that zone, or at its end when `place` is `nothing`.
`zone` is `:fields`, `:columns`, `:rows` or `:cells`, a row of the bar of the
pivot that holds fields. It is the move that a drag of the badge of the field
makes, so the tool `undo` takes it back in one step. The selection of the person
does not move. Answer `pivot`.

Use it to change how a pivot cuts its rows: which fields go down, which go
across, and which split a cell.

# Example

    pivot_1 = get_edited_document(find_pane("Sales"))
    move_pivot_field!(pivot_1, "country", :columns)
    move_pivot_field!(pivot_1, "year", :rows; place = 1)

See also `find_pivot_value`, `replace_referenced_value!`, `insert_elements!`.
"""
function move_pivot_field! end

function move_pivot_field!(pivot, column::AbstractString, zone::Symbol;
                           place::Union{Integer,Nothing} = nothing, editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "move_pivot_field!") do
        document = pivot isa ReferencedDocument ? get_document(pivot) : pivot
        document isa PivotTable ||
            throw(ArgumentError("move_pivot_field! moves a field of a pivot, not of a " *
                                string(nameof(typeof(document))) * "."))
        into = get(_PIVOT_FIELD_ZONES, zone, nothing)
        into === nothing &&
            throw(ArgumentError("A field goes to :fields, :columns, :rows or :cells, not :" * string(zone) *
                                ". A value is an element of `pivot.measures`: " *
                                "`insert_elements!(pivot.measures, 1, [PivotMeasure(\"amount\", :sum)])` adds one."))
        found = _find_pivot_field(document, String(column))
        found === nothing &&
            throw(ArgumentError("The pivot has no field " * repr(String(column)) * ". Its fields: " *
                                join(_collect_pivot_field_names(document), ", ") * "."))
        from, index = found
        count = length(_get_pivot_zone(document, into))
        landing = place === nothing ? (from == into ? count : count + 1) : Int(place)
        move = _make_pivot_range_move(document, from, index, into,
                                      (from == into && landing > index) ? landing + 1 : landing)
        move === nothing ||
            _evaluate_pivot_operation!(editor, pivot, first(move), "Move the field " * String(column))
        pivot
    end
end

# The zone and the place of the field of `column`: `(field, index)`, or `nothing`.
function _find_pivot_field(pivot::PivotTable, column::String)
    for field in values(_PIVOT_FIELD_ZONES)
        index = findfirst(dimension -> dimension.column == column, collect(_get_pivot_zone(pivot, field)))
        index === nothing || return (field, index)
    end
    nothing
end

_collect_pivot_field_names(pivot::PivotTable) =
    String[dimension.column for field in values(_PIVOT_FIELD_ZONES) for dimension in _get_pivot_zone(pivot, field)]

# Evaluate `operation`, an edit of `pivot`, as an edit of the person: the readers
# of the editor carry it from the pivot to the root, so the history of the tab
# that shows the pivot records it. A pivot that no view shows takes the
# operation directly.
function _evaluate_pivot_operation!(editor, pivot, operation, description)
    if pivot isa ReferencedDocument && editor isa Editor && editor.iomap !== nothing
        rooted = find_rooted_operation(editor, get_reference(pivot), relative -> operation; description)
        rooted === nothing || return evaluate_operation(editor, rooted)
    end
    evaluate_operation(editor, operation)
end
