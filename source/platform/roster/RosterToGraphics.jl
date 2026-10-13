# Fragment of `RosterModule` — what a roster shows: its rows through the
# recursion at their own path, where an arrangement finds them, and a list of rows
# as a table.

"""
    RosterToGraphics()

Prints a [`Roster`](@ref): its `rows` print through the recursion at the path
`rows`, with the keys of the columns in the printer context. So an entry of an
arrangement at `rows` puts its filter, its sort and its bar before the printer of
the rows, as at any collection, and the rows print as a table
([`RosterRowsToWidget`](@ref)). The output is the output of the rows.
"""
struct RosterToGraphics <: Projection end

@iomap struct RosterToGraphicsIoMap
    projection::Any
    input::Any          # Roster
    output::Any         # the output of the rows
    inner_iomap::Any
end

function print_document(p::RosterToGraphics, recursion, roster::Roster, ctx)
    context = make_child_context(ctx, roster, FieldReferenceStep("rows"))
    context = with_property(context, :roster_columns, getfield(roster, :columns))
    inner = make_reconciled_child_iomap_cell(() -> roster.rows, rows -> print_child(recursion, rows, context))
    RosterToGraphicsIoMap(p, roster, Cell(@computation inner[].output), inner)
end

get_child_iomaps(iomap::RosterToGraphicsIoMap) = Any[iomap.inner_iomap]

# Everything goes on to the rows, and the answer is rooted under the field `rows`,
# so its path is a path of the roster.
function read_intent(p::RosterToGraphics, recursion, change::Intent, iomap::RosterToGraphicsIoMap)
    change.route === nothing || return read_routed_child(recursion, change, iomap)
    inner = iomap.inner_iomap
    answer = read_intent(get_iomap_projection(inner), recursion, change, inner)
    operation = reroot_operation(answer isa Intent ? answer.operation : answer, (FieldReferenceStep("rows"),))
    Intent(change.gesture, operation)
end

read_intent(p::RosterToGraphics, iomap::RosterToGraphicsIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

function map_reference_forward(::RosterToGraphics, iomap::RosterToGraphicsIoMap, reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    (head isa FieldReferenceStep && head.name == "rows") || return nothing
    inner = iomap.inner_iomap
    map_reference_forward(get_iomap_projection(inner), inner, get_reference_tail(reference))
end

function map_reference_backward(::RosterToGraphics, iomap::RosterToGraphicsIoMap, reference)
    inner = iomap.inner_iomap
    path = map_reference_backward(get_iomap_projection(inner), inner, reference)
    path === nothing ? nothing : ConcreteReference(FieldReferenceStep("rows"), path)
end

"""
    RosterRowsToWidget()

Prints a list of rows of a roster, a `CellVector{RosterRow}`, as a `WidgetTable`
in a `VerticalLayout`: a header with the key of each column, and one row of cells
for each row. The keys come from the printer context, which the roster gives, or
else from the first row.

A cell whose value is a document shows that document itself, the same object as
in its item, so a key edits it through its own reader, as in any other place. A
cell of any other value shows its text ([`format_roster_value`](@ref)), and a press
there selects the item of the row, so the context menu is the menu of the item.
The table of a row keeps its cells while the row stays, so a row that a filter or
a sort moves draws again only where it moved.
"""
struct RosterRowsToWidget <: Projection end

@iomap struct RosterRowsToWidgetIoMap
    projection::Any
    input::Any          # CellVector{RosterRow}
    output::Any         # VerticalLayout of the table
    columns::Any        # the keys of the columns
end

function print_document(p::RosterRowsToWidget, recursion, rows::CellVector, ctx)
    columns = _find_roster_columns(rows, ctx)
    made = IdDict{Any,Any}()
    cells = CellVector(Computation(() -> _collect_row_cells(rows, made)))
    headers = CellVector(Cell[Cell(WidgetLabel(key)) for key in columns])
    table = WidgetTable(headers, cells)
    layout = VerticalLayout(Any[table]; child_width = Fill)
    iomap = RosterRowsToWidgetIoMap(p, rows, layout, columns)
    # The layout and the table hold their part of the selection and of the part
    # under the pointer. The walk stops at the table: a cell can hold a document
    # of an item, which keeps its own selection.
    is_followed = node -> node isa VerticalLayout || node isa WidgetTable
    follow_output_selection!(layout, () -> _map_rows_forward(iomap, getfield(rows, :selection)[]);
                             forward_mouse_target = () -> map_mouse_target_forward(rows,
                                 path -> _map_rows_forward(iomap, path)),
                             is_followed)
    iomap
end

# The keys of the columns: those that the roster put in the context, or else
# those of the first row, or none.
function _find_roster_columns(rows, ctx)
    columns = ctx === nothing ? nothing : get_property(ctx, :roster_columns, nothing)
    columns === nothing || return collect(String, unwrap_cell(columns))
    isempty(rows) ? String[] : collect(String, rows[1].columns)
end

# The cells of each row of `rows`, the same cells for a row that stays. `made`
# keeps them from one computation to the next.
function _collect_row_cells(rows, made::IdDict{Any,Any})
    kept = IdDict{Any,Any}()
    found = Any[]
    for row in rows
        cells = get(made, row, nothing)
        cells === nothing && (cells = _make_row_cells(row))
        kept[row] = cells
        push!(found, cells)
    end
    empty!(made)
    merge!(made, kept)
    found
end

# The cells of one row: the document that a value is, or a label of the text of the
# value. Each cell keeps its label, so a value that changes and stays text draws
# again only its text.
function _make_row_cells(row::RosterRow)
    values = row.values
    slots = Cell[]
    for c in 1:length(values)
        value = get_cell_at(values, c)
        label = WidgetLabel(() -> format_roster_value(value[]))
        push!(slots, Cell(Computation(() -> (v = value[]; v isa Document ? v : label))))
    end
    CellVector(slots)
end

# The path of a column `c` of the row at `r`, as the roster holds it: below the item
# for a path of fields, below the outer item for a path after `within`, and the
# value cell of the column for a facet.
function _get_column_path(row::RosterRow, r::Int, c::Int)
    key = row.columns[c]
    names = split(key, '.')
    head = String(names[1])
    steps = if head == "within" && length(names) > 1 && _has_item_facet(typeof(row.within), String(names[2]))
        Any[FieldReferenceStep("values"), ElementReferenceStep(c)]
    elseif head == "within"
        Any[FieldReferenceStep("within"), (FieldReferenceStep(String(n)) for n in names[2:end])...]
    elseif _has_item_facet(typeof(row.item), head)
        Any[FieldReferenceStep("values"), ElementReferenceStep(c)]
    else
        Any[FieldReferenceStep("item"), (FieldReferenceStep(String(n)) for n in names)...]
    end
    extend_reference(EmptyReference(), ElementReferenceStep(r), steps...)
end

# The steps from the layout to the table.
const _TABLE_STEPS = (FieldReferenceStep("children"), ElementReferenceStep(1))

_make_table_path(steps...) = extend_reference(EmptyReference(), _TABLE_STEPS..., steps...)

# The path in the layout of the path `path` of the rows: a whole row for the row
# or its item, and a cell for a path at or below the place of its column.
function _map_rows_forward(iomap::RosterRowsToWidgetIoMap, path)
    path === nothing && return nothing
    path isa EmptyReference && return EmptyReference()
    path isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(path))
    head = steps[1]
    (head isa RangeReferenceStep && is_element_reference_step(head)) || return nothing
    r = head.start + 1
    rows = iomap.input
    (1 <= r <= length(rows)) || return nothing
    row = rows[r]
    whole = _make_table_path(FieldReferenceStep("rows"), ElementReferenceStep(r))
    length(steps) == 1 && return whole
    for c in 1:length(row.columns)
        place = get_reference_steps(_get_column_path(row, r, c))
        length(steps) >= length(place) && all(steps[k] == place[k] for k in eachindex(place)) || continue
        return _make_table_path(FieldReferenceStep("cells"), ElementReferenceStep(r), ElementReferenceStep(c),
                                steps[(length(place) + 1):end]...)
    end
    steps[2] == FieldReferenceStep("item") && length(steps) == 2 ? whole : nothing
end

map_reference_forward(::RosterRowsToWidget, iomap::RosterRowsToWidgetIoMap, reference) =
    _map_rows_forward(iomap, reference)

function map_reference_backward(::RosterRowsToWidget, iomap::RosterRowsToWidgetIoMap, reference)
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    length(steps) >= length(_TABLE_STEPS) && all(steps[k] == _TABLE_STEPS[k] for k in eachindex(_TABLE_STEPS)) ||
        return nothing
    rest = steps[(length(_TABLE_STEPS) + 1):end]
    isempty(rest) && return EmptyReference()
    rows = iomap.input
    item_of(r) = extend_reference(EmptyReference(), ElementReferenceStep(r), FieldReferenceStep("item"))
    if rest[1] == FieldReferenceStep("rows") && length(rest) >= 2 && _is_index_step(rest[2])
        r = rest[2].start + 1
        return (1 <= r <= length(rows)) ? item_of(r) : nothing
    end
    if rest[1] == FieldReferenceStep("cells") && length(rest) >= 3 && _is_index_step(rest[2]) &&
       _is_index_step(rest[3])
        r, c = rest[2].start + 1, rest[3].start + 1
        (1 <= r <= length(rows)) || return nothing
        row = rows[r]
        (1 <= c <= length(row.columns)) || return nothing
        row.values[c] isa Document || return item_of(r)
        return extend_reference(_get_column_path(row, r, c), rest[4:end]...)
    end
    nothing
end

_is_index_step(step) = step isa RangeReferenceStep && is_element_reference_step(step)

# The rows of the natural renderer: a roster, and a list of rows of a roster, which
# a filter or a sort of the rows gives as a list of the same kind. The table is a
# layout of widgets, which the renderer draws.
function _make_roster_graphics_entries(; measure = nothing, appearance)
    Pair{Type,Any}[Roster => RosterToGraphics(),
                   CellVector{RosterRow} => ChainingProjection(RosterRowsToWidget(),
                                                               VerticalLayoutToGraphicsCanvas())]
end
