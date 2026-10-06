# Fragment of `PivotModule`.
#
# A `PivotTable` drawn as the bar of its five zones above a table of its cross
# table. The column keys make the column headers and the row keys the row
# headers, one level for each dimension, and the table merges a run of equal
# labels into one header. The rows are a list, so the table builds only the rows
# that it shows, and a cell shows the document that the view of the pivot makes
# for its part.

"""
    PivotTableToWidget(; row_height, zone_gap, chip_gap)

Projects a [`PivotTable`](@ref) to a `GridLayout` of two rows: the bar of the
zones, and a `WidgetTable` of the cross table.

The bar has a row for each zone, in the order Fields, Columns, Rows, Cells and
Values: the name of the zone, and a badge for each dimension or measure in it.
An empty Values row shows the count, which is what a cell computes then. The
Cells row starts with an outlined badge that names the view of the cells, which
the menu of the pivot chooses. The badge of the selected item is filled and the
others are muted. A press on a
badge selects its item, and a drag of a badge moves the item: an outlined badge
shows where the drop puts it. The keys of the gesture table of the pivot move
the selected item.

The table has a column for each column key and a row for each row key. A header
of a column holds one label for each column dimension, and a header of a row one
label for each row dimension, so the table draws the levels of the headers and
merges their runs. The corner names the row dimensions. With no column
dimension, the one column is headed by the names of the measures; with no row
dimension, the one row is headed `all`. Each row is as tall as the lines that
the view of the cells takes (`get_pivot_cell_view_lines`), each `row_height`
tall.

An edit in a cell, such as a value of a row of a data frame, changes the source,
so the reader adds a write of `source_version` to it, and the pivot computes its
parts again.

A path of the pivot maps to the table and back: `cells[r][c]…` is the cell in
row `r` and column `c`, and `cells[r]` the row. `<zone>[i]` is the badge of
item `i` of a zone, and `<zone>` its row of the bar. A part of the table that the
pivot does not name, such as a run of headers, maps back as a part that the
projection introduced, and its selection shows in the table.
"""
@projection UntrackedCell struct PivotTableToWidget
    row_height::Int = 0
    zone_gap::Int = get_widget_style(nothing, :section_gap)
    chip_gap::Int = get_widget_style(nothing, :item_gap)
end

@iomap struct PivotTableToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    table::Any               # the WidgetTable of the cross table
end

# A weight and no minimum: the table gives each column an equal share of the
# width, and the width of its headers at least.
const _PIVOT_COLUMN_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)

# The name that the bar shows for each zone, in the order of `_PIVOT_ZONE_FIELDS`.
const _PIVOT_ZONE_NAMES = ("Fields", "Columns", "Rows", "Cells", "Values")

# How far a held press moves before it starts the drag of a badge, in pixels.
const _PIVOT_DRAG_THRESHOLD = 5

function print_document(p::PivotTableToWidget, recursion, pivot::PivotTable, ctx)
    bar = _make_pivot_bar(p, pivot)
    table = _make_pivot_table_widget(p, pivot)
    grid = GridLayout(Any[bar, table], 1; vertical_gap = p.zone_gap, column_policies = Any[Fill],
                      row_policies = Any[Content, Fill])
    set_cell_computation!(getfield(grid, :selection), () -> begin
        bar_path = _find_pivot_bar_path(pivot, pivot.selection)
        bar_path === nothing || return _make_pivot_grid_reference(1, bar_path)
        selection = table.selection
        selection === nothing ? nothing : _make_pivot_grid_reference(2, selection)
    end)
    PivotTableToWidgetIoMap(p, pivot, grid, table)
end

print_document(p::PivotTableToWidget, pivot::PivotTable) = print_document(p, nothing, pivot, nothing)

# ── The bar ──────────────────────────────────────────────────────────────────

# The bar: a composite whose one element is a grid of the name of each zone and
# the badges of what it holds. A change of a zone or of the drag builds a new
# grid, and the composite prints it again, because it keeps a child by its
# identity; a layout prints its children once. The selection does not build the
# grid again: each badge reads it.
function _make_pivot_bar(p::PivotTableToWidget, pivot::PivotTable)
    elements = CellVector(@computation Any[_make_pivot_bar_grid(p, pivot)])
    WidgetComposite(Cell(Point2D(0, 0)), elements, Cell(nothing), Cell(nothing), Cell(true), Cell(nothing),
                    Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
end

function _make_pivot_bar_grid(p::PivotTableToWidget, pivot::PivotTable)
    children = Any[]
    for (name, field) in zip(_PIVOT_ZONE_NAMES, _PIVOT_ZONE_FIELDS)
        push!(children, WidgetLabel(name))
        push!(children, _make_pivot_zone_row(p, pivot, field))
    end
    GridLayout(children, 2; horizontal_gap = p.zone_gap, vertical_gap = p.chip_gap)
end

# What the row of the zone `field` shows, badge by badge: the place of an item,
# `(:drop, place)` for the outlined badge where a drop of the dragged item puts
# it, `:count` for the outlined badge of an empty Values row, and `:view` for the
# outlined badge that names the view of the cells, first in the Cells row.
function _get_pivot_zone_entries(pivot::PivotTable, field::String)
    entries = Any[index for index in 1:length(_get_pivot_zone(pivot, field))]
    drag = pivot.drag
    if drag !== nothing && drag.started && drag.target !== nothing && drag.target[1] == field
        place = clamp(drag.target[2], 1, length(entries) + 1)
        insert!(entries, place, (:drop, drag.target[2]))
    end
    (isempty(entries) && field == "measures") && push!(entries, :count)
    field == "cell_dimensions" && pushfirst!(entries, :view)
    entries
end

# The name of the view of the cells of `pivot`, which says when the view is the
# automatic one.
function _describe_pivot_cells(pivot::PivotTable)
    name = "as " * describe_pivot_cell_view(typeof(get_pivot_cell_view(pivot)).name.wrapper)
    pivot.cell_view === nothing ? name * " (automatic)" : name
end

# The badges of the zone in the field `field` of `pivot`.
function _make_pivot_zone_row(p::PivotTableToWidget, pivot::PivotTable, field::String)
    zone = _get_pivot_zone(pivot, field)
    chips = Any[]
    for entry in _get_pivot_zone_entries(pivot, field)
        if entry isa Int
            item = zone[entry]
            # A row or a column dimension of many values says so, and the menu of
            # the dimension offers its bins and its limit.
            many = field in ("row_dimensions", "column_dimensions") ? _count_pivot_categories(pivot, item) : 0
            many > _PIVOT_MANY_VALUES || (many = 0)
            text = many == 0 ? _describe_pivot_zone_item(item) :
                               string(_describe_pivot_zone_item(item), " (", many, " values)")
            rest = many == 0 ? :secondary : :destructive
            badge = WidgetBadge(text; variant = rest)
            set_cell_computation!(getfield(badge, :variant),
                                  () -> _find_pivot_zone_item(pivot.selection) == (field, entry) ? :default : rest)
            push!(chips, badge)
        elseif entry === :count
            push!(chips, WidgetBadge("count"; variant = :outline))
        elseif entry === :view
            push!(chips, WidgetBadge(() -> _describe_pivot_cells(pivot); variant = :outline))
        else
            from, index = pivot.drag.source
            push!(chips, WidgetBadge(_describe_pivot_zone_item(_get_pivot_zone(pivot, from)[index]);
                                     variant = :outline))
        end
    end
    HorizontalLayout(chips; gap = p.chip_gap)
end

_describe_pivot_zone_item(dimension::PivotDimension) = dimension.column
_describe_pivot_zone_item(measure::PivotMeasure) = describe_pivot_measure(measure)
_describe_pivot_zone_item(item) = string(item)

# ── The table ────────────────────────────────────────────────────────────────

# The table of a pivot, in the layout of its cells: the cross table, or the rows
# of the source in their groups (`PivotGroupView`).
function _make_pivot_table_widget(p::PivotTableToWidget, pivot::PivotTable)
    grouped() = _is_pivot_group_layout(pivot)
    headers = CellVector(@computation grouped() ? _make_pivot_group_column_headers(pivot) :
                                                  _make_pivot_column_headers(pivot))
    rows = Cell(@computation grouped() ? _make_pivot_group_row_list(pivot) : _make_pivot_row_list(pivot))
    row_headers = Cell(@computation grouped() ? _make_pivot_group_header_list(pivot) :
                                                _make_pivot_row_header_list(pivot))
    corner = Cell(@computation grouped() ? _make_pivot_group_corner(pivot) : _make_pivot_corner(pivot))
    columns = Cell(@computation grouped() ?
        Any[WidgetTableColumn(; policy = _PIVOT_COLUMN_POLICY) for _ in _get_pivot_group_columns(pivot)] :
        Any[WidgetTableColumn(; policy = _PIVOT_COLUMN_POLICY, align = :right)
            for _ in 1:get_pivot_column_count(pivot.cross_table)])
    # Positional, so every declared field is named here in order: position,
    # column_headers, row_headers, corner, cells, cell_order, rows, columns,
    # border_width, column_policy, row_policy, cell_policy, visible, margin,
    # border, padding, style, scroll_position, top_row, column_drag,
    # vertical_scroll_bar, horizontal_scroll_bar, open_cells, tooltip.
    WidgetTable(Cell(Point2D(0, 0)), headers, row_headers, corner, rows,
                Cell(:row_major), Cell(WidgetTableRows(nothing)), columns, Cell(1),
                Cell(_PIVOT_COLUMN_POLICY),
                Cell(@computation Fixed(p.row_height * get_pivot_cell_view_lines(get_pivot_cell_view(pivot)))),
                # A number is cut at the edge of its column; any other view, such as a
                # table, is offered the width of its column and fills it.
                Cell(@computation get_pivot_cell_view(pivot) isa Union{PivotNumberView,PivotGroupView} ? :clip : :wrap),
                Cell(true), Cell(nothing), Cell(nothing), Cell(nothing),
                Cell(nothing), Cell(Point2D(0, 0)), Cell(1), Cell(nothing), Cell(:auto), Cell(:auto),
                Cell(nothing), Cell(nothing),
                Cell(@computation _get_pivot_table_selection(pivot)))
end

# The labels of a key, one for each level. Each label is a `WidgetLabel`, a
# document: a layout keeps the answer of an Alt+press of its child only when the
# answer names a document, so an Alt+press selects a label of the table, and its run.
_make_pivot_key_labels(key::Tuple) = CellVector(Any[WidgetLabel(format_pivot_value(value)) for value in key])

# The header of each column: the labels of its key, or the names of the measures
# for the one column of a pivot with no column dimension.
function _make_pivot_column_headers(pivot::PivotTable)
    cross = pivot.cross_table
    isempty(pivot.column_dimensions) &&
        return Any[WidgetLabel(join((describe_pivot_measure(measure) for measure in get_pivot_measures(pivot)), "  "))]
    Any[_make_pivot_key_labels(key) for key in cross.column_keys]
end

# The header of each row as a list that moves in step with the rows: the labels
# of its key, or `all` for the one row of a pivot with no row dimension. A pivot
# with no row has an empty vector.
function _make_pivot_row_header_list(pivot::PivotTable)
    # A new view of the cells changes the height of the rows, which a row reads
    # when it is built, so the list is built again.
    get_pivot_cell_view(pivot)
    cross = pivot.cross_table
    count = get_pivot_row_count(cross)
    count == 0 && return CellVector()
    leveled = !isempty(pivot.row_dimensions)
    make_index_list(count, 1, k -> leveled ? _make_pivot_row_labels(pivot, cross.row_keys[k]) : WidgetLabel("all"))
end

# The labels of the key of a row. The label of a closed run or group starts with ▸.
function _make_pivot_row_labels(pivot::PivotTable, key::Tuple)
    labels = Any[format_pivot_value(value) for value in key]
    total = findfirst(value -> value isa PivotTotal, key)
    if total === nothing
        (!isempty(labels) && any(isequal(key), pivot.collapsed)) && (labels[end] = "▸ " * labels[end])
    elseif total > 1 && any(isequal(key[1:(total - 1)]), pivot.collapsed)
        labels[total - 1] = "▸ " * labels[total - 1]
    end
    CellVector(Any[WidgetLabel(label) for label in labels])
end

# The corner: the names of the row dimensions, one for each level of the row
# headers.
_make_pivot_corner(pivot::PivotTable) =
    isempty(pivot.row_dimensions) ? WidgetLabel("") :
        CellVector(Any[dimension.column for dimension in pivot.row_dimensions])

# The rows of the table as a list: row `k` holds the document of each of its
# cells. A pivot with no row has an empty vector.
function _make_pivot_row_list(pivot::PivotTable)
    get_pivot_cell_view(pivot)
    cross = pivot.cross_table
    count = get_pivot_row_count(cross)
    count == 0 && return CellVector()
    width = get_pivot_column_count(cross)
    function row_of(k)
        cells = Cell[Cell(nothing) for _ in 1:width]
        for c in 1:width
            set_cell_computation!(cells[c], () -> pivot.cells[k][c])
        end
        CellVector(cells)
    end
    make_index_list(count, 1, row_of)
end

# ── The paths ────────────────────────────────────────────────────────────────

# The path in the grid of the pivot of its child `k`, followed by `tail`.
_make_pivot_grid_reference(k::Int, tail) =
    ConcreteReference(FieldReferenceStep("children"), ConcreteReference(RangeReferenceStep(k - 1, k), tail))

# The path inside child `k` of the grid from a path of the grid, or `nothing`.
function _find_pivot_grid_child_path(path, k::Int)
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name == "children") ||
        return nothing
    tail = path.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep && tail.head.stop == k &&
     tail.head.start == k - 1) || return nothing
    tail.tail
end

# The path in the table of `path`, a path of the pivot: `cells[r][c]…` is the
# cell, `cells[r]` the row, and a part that this projection introduced is its
# path in the table. `nothing` for any other path, and for a cell of the pivot in
# the group layout, whose rows are the rows of the source.
function _find_pivot_table_path(p, path, grouped::Bool = false)
    path = strip_reference_types(path)
    path isa EmptyReference && return EmptyReference()
    path isa ConcreteReference || return nothing
    head = path.head
    if head isa ProjectionReferenceStep
        (p === nothing || head.projection === p) || return nothing
        return _find_pivot_grid_child_path(head.output_path, 2)
    end
    (head isa FieldReferenceStep && head.name == "cells" && !grouped) || return nothing
    row = path.tail
    (row isa ConcreteReference && row.head isa RangeReferenceStep) || return nothing
    row.tail isa EmptyReference &&
        return ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(row.head, EmptyReference()))
    path
end

# The selection of the table that shows the selection of `pivot`.
function _get_pivot_table_selection(pivot::PivotTable)
    selection = pivot.selection
    selection === nothing && return nothing
    _find_pivot_table_path(nothing, selection, _is_pivot_group_layout(pivot))
end

# The path of the pivot of `path`, a path in the table: `cells[r][c]…` is the
# cell, `rows[r]` the row; `nothing` for any other path.
function _find_pivot_path(path)
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep) || return nothing
    row = path.tail
    (row isa ConcreteReference && row.head isa RangeReferenceStep) || return nothing
    path.head.name == "cells" && return path
    (path.head.name == "rows" && row.tail isa EmptyReference) &&
        return ConcreteReference(FieldReferenceStep("cells"), ConcreteReference(row.head, EmptyReference()))
    nothing
end

# The path in the bar of `path`, a path of the pivot: `<zone>[i]…` is the badge
# of the item, and `<zone>` the row of the zone. `nothing` for any other path.
function _find_pivot_bar_path(pivot::PivotTable, path)
    path isa Reference || return nothing
    zone = _find_pivot_zone(path)
    zone === nothing || return _make_pivot_bar_row_reference(zone, EmptyReference())
    found = _find_pivot_zone_item(path)
    found === nothing && return nothing
    field, index = found
    k = findfirst(==(index), _get_pivot_zone_entries(pivot, field))
    k === nothing && return nothing
    rest = strip_reference_types(path).tail.tail
    _make_pivot_bar_row_reference(field, ConcreteReference(FieldReferenceStep("children"),
                                                           ConcreteReference(RangeReferenceStep(k - 1, k), rest)))
end

# The path in the bar of the row of the zone `field`, followed by `tail`. The grid
# of the bar is the one element of the composite, and it holds the name and the
# row of each zone in turn.
function _make_pivot_bar_row_reference(field::String, tail)
    k = 2 * _get_pivot_zone_number(field)
    ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(0, 1),
        ConcreteReference(FieldReferenceStep("children"), ConcreteReference(RangeReferenceStep(k - 1, k), tail))))
end

# The path of the pivot of `path`, a path in the bar: a badge of an item names
# the item, the outlined badge of a drop the place where the drop puts the item,
# and any other part of the row of a zone, or its name, the zone.
function _find_pivot_path_in_bar(pivot::PivotTable, path)
    path = strip_reference_types(path)
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name == "elements") ||
        return nothing
    grid = path.tail
    (grid isa ConcreteReference && grid.head isa RangeReferenceStep && grid.head.stop == 1) || return nothing
    path = grid.tail
    (path isa ConcreteReference && path.head isa FieldReferenceStep && path.head.name == "children") ||
        return nothing
    child = path.tail
    (child isa ConcreteReference && child.head isa RangeReferenceStep) || return nothing
    number = cld(child.head.stop, 2)
    1 <= number <= length(_PIVOT_ZONE_FIELDS) || return nothing
    field = _PIVOT_ZONE_FIELDS[number]
    row = child.tail
    (iseven(child.head.stop) && row isa ConcreteReference && row.head isa FieldReferenceStep &&
     row.head.name == "children") || return _make_pivot_zone_path(field)
    badge = row.tail
    (badge isa ConcreteReference && badge.head isa RangeReferenceStep) || return _make_pivot_zone_path(field)
    entries = _get_pivot_zone_entries(pivot, field)
    k = badge.head.stop
    1 <= k <= length(entries) || return _make_pivot_zone_path(field)
    entry = entries[k]
    entry isa Int && return _make_pivot_zone_item_path(field, entry)
    entry isa Tuple && return _make_pivot_zone_item_path(field, entry[2])
    _make_pivot_zone_path(field)
end

function map_reference_forward(p::PivotTableToWidget, iomap::PivotTableToWidgetIoMap, reference)
    reference isa Reference || return nothing
    bar_path = _find_pivot_bar_path(iomap.input, reference)
    bar_path === nothing || return _make_pivot_grid_reference(1, bar_path)
    path = _find_pivot_table_path(p, reference, _is_pivot_group_layout(iomap.input))
    path === nothing && return nothing
    path isa EmptyReference && return EmptyReference()
    _make_pivot_grid_reference(2, path)
end

function map_reference_backward(p::PivotTableToWidget, iomap::PivotTableToWidgetIoMap, reference)
    bar = reference isa Reference ? _find_pivot_grid_child_path(reference, 1) : nothing
    bar_path = bar === nothing ? nothing : _find_pivot_path_in_bar(iomap.input, bar)
    bar_path === nothing || return annotate_reference_types(iomap.input, bar_path)
    inner = reference isa Reference ? _find_pivot_grid_child_path(reference, 2) : nothing
    target = (inner === nothing || _is_pivot_group_layout(iomap.input)) ? nothing : _find_pivot_path(inner)
    target === nothing || return annotate_reference_types(iomap.input, target)
    invoke(map_reference_backward, Tuple{Projection,Any,Any}, p, iomap, reference)
end

# ── The reader ───────────────────────────────────────────────────────────────

# The press, the drag and the drop of a badge of the bar. The pivot knows the
# part under the pointer by its mouse target, which the moves keep up to date, so
# the reader reads no point. A press on a badge selects its item and keeps the
# press. A held move past the threshold starts the drag, and the drag tracker
# sends the pivot `DragMove`, `DragEnd` and `DragCancel` by its path. A move
# writes the place where a drop puts the item, which the bar shows; the release
# makes the edit of the drop, and a cancel drops nothing.
function read_intent(p::PivotTableToWidget, recursion, change::Intent, iomap::PivotTableToWidgetIoMap)
    pivot = iomap.input
    gesture = change.gesture
    drag = pivot.drag
    if drag !== nothing && gesture isa Union{DragMove,DragEnd,DragCancel}
        gesture isa DragCancel && return Intent(gesture, _write_pivot_drag(pivot, nothing))
        target = _find_pivot_drop_target(pivot, get_mouse_target(pivot), drag.target)
        gesture isa DragMove &&
            return Intent(gesture, target == drag.target ? nothing :
                                       _write_pivot_drag(pivot, merge(drag, (target = target,))))
        return Intent(gesture, _join_pivot_operations(_make_pivot_drop_operation(pivot, drag.source, target),
                                                      _write_pivot_drag(pivot, nothing)))
    end
    if gesture isa MouseDown && gesture.button === :left && !gesture.modifiers.alt && drag === nothing
        source = _find_pivot_zone_item(get_mouse_target(pivot))
        source === nothing ||
            return Intent(gesture, _join_pivot_operations(
                _write_pivot_drag(pivot, (source = source, x = gesture.x, y = gesture.y, started = false,
                                          target = nothing)),
                ReplaceSelectionOperation(_make_pivot_zone_item_path(source...))))
    end
    (drag !== nothing && !drag.started && gesture isa MouseUp) &&
        return Intent(gesture, _write_pivot_drag(pivot, nothing))
    answer = invoke(read_intent, Tuple{Projection,Any,Intent,Any}, p, recursion, change, iomap)
    operation = answer isa Intent ? answer.operation : answer
    if operation !== nothing && _is_pivot_source_edit(operation)
        version = ReplaceReferencedValueOperation(pivot, "source_version", pivot.source_version + 1)
        answer = Intent(gesture, _join_pivot_operations(operation, version))
    end
    if drag !== nothing && !drag.started && gesture isa MouseMove && !is_move_without_button(gesture) &&
       hypot(gesture.x - drag.x, gesture.y - drag.y) >= _PIVOT_DRAG_THRESHOLD
        start = _join_pivot_operations(_write_pivot_drag(pivot, merge(drag, (started = true,))),
                                       StartDragOperation(EmptyReference(), _make_pivot_zone_item_path(drag.source...)))
        return Intent(gesture, _join_pivot_operations(start, answer isa Intent ? answer.operation : answer))
    end
    answer
end

# A key that the table and the bar do not take: the gestures of the pivot answer it.
read_intent(::PivotTableToWidget, iomap::PivotTableToWidgetIoMap, event::KeyDown) =
    read_gesture(iomap.input, event)

# Where a drop of the dragged item lands with the pointer on `target`, the mouse
# target of the pivot: before the item that it names, at the end of the zone that
# it names, or where the drop landed before, `before`, when it names neither.
function _find_pivot_drop_target(pivot::PivotTable, target, before)
    item = _find_pivot_zone_item(target)
    item === nothing || return item
    zone = _find_pivot_zone(target)
    zone === nothing && return before
    (zone, length(_get_pivot_zone(pivot, zone)) + 1)
end

# Whether `operation`, the answer of the table, edits the data: anything but a
# selection, the part under the pointer, view state, the start of a drag and a
# timer. An edit in a cell writes the source, which no cell of the pivot reads.
_is_pivot_source_edit(operation::CompoundOperation) = any(_is_pivot_source_edit, operation.operations)
_is_pivot_source_edit(::Union{ReplaceSelectionOperation,ReplaceMouseTargetOperation,ReplaceViewStateOperation,
                              StartDragOperation,SetTimerOperation,DoNothingOperation}) = false
_is_pivot_source_edit(::Any) = true

# A write of the state of the drag, which a history does not record.
_write_pivot_drag(pivot::PivotTable, drag) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(pivot, "drag", drag))

# The operations in order, without the ones that are `nothing`, as one operation.
function _join_pivot_operations(operations...)
    kept = Any[operation for operation in operations if operation !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

"""
    make_pivot_table_projection(; measure, appearance = Appearance()) -> Projection

The projection that draws a [`PivotTable`](@ref): [`PivotTableToWidget`](@ref)
with the row height of the font of the widget theme of `appearance`, and the
grid that places its bar and its table. The natural renderer uses it for a pivot.
"""
function make_pivot_table_projection(; measure::TextMeasure, appearance::Appearance = Appearance())
    theme = get_scaled_theme!(appearance, WidgetTheme)
    row_height = UntrackedCell{Int}(@computation ceil(Int, compute_line_box(measure, "M", theme.font).height))
    grid = last(only(p for p in LayoutToGraphics().dispatch if first(p) === GridLayout))
    ChainingProjection(PivotTableToWidget(; row_height, zone_gap = get_widget_style(theme, :section_gap),
                                          chip_gap = get_widget_style(theme, :item_gap)), grid)
end
