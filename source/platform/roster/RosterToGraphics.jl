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
in a `GridLayout` that gives it the height that the rows are given: a header with
the key of each column, and one row of cells for each row. The keys come from the
printer context, which the roster gives, or else from the first row.

Where the context gives the rows a height, as a tab does, the body of the table
is a list of the rows from the row at its head, so the table builds only the
rows that it shows, fills the height and scrolls its rows. Every column then
takes an equal share of the width, and the width of its header at least, because
a table of a list measures no cell for a column. Where no height is given, as in
a print with no window, the body is a vector of every row, and a column is as
wide as its widest cell.

A cell whose value is a document shows that document itself, the same object as
in its item, so a key edits it through its own reader, as in any other place. A
cell of any other value shows its text ([`format_roster_value`](@ref)), and a press
there selects the item of the row, so the context menu is the menu of the item.
A row keeps its cells while it stays, so in a list the grid keeps the print of a
row that a filter or a sort keeps, and prints only the rows that are new to it.
"""
struct RosterRowsToWidget <: Projection end

@iomap struct RosterRowsToWidgetIoMap
    projection::Any
    input::Any          # CellVector{RosterRow}
    output::Any         # GridLayout of the table
    columns::Any        # the keys of the columns
    table::Any          # the WidgetTable of the rows
    view::Any           # the _RosterTableView of a body that is a list, or nothing
end

# The row of `rows` at the head of the body of a roster table that is a list.
# The table moves its head far down by a write of its body, which the roster
# turns into a write of `anchor`.
@document struct _RosterTableView
    anchor::Int
end

# A weight and no minimum: the table gives a column an equal share of the width,
# and the width of its header at least.
const _ROSTER_COLUMN_POLICY = SizePolicy(nothing, nothing, nothing, 1.0)

function print_document(p::RosterRowsToWidget, recursion, rows::CellVector, ctx)
    columns = _find_roster_columns(rows, ctx)
    made = IdDict{Any,Any}()
    headers = CellVector(Cell[Cell(WidgetLabel(key)) for key in columns])
    view = (ctx !== nothing && get_exact_height(ctx) !== nothing) ? _RosterTableView(1) : nothing
    table = view === nothing ?
        WidgetTable(headers, CellVector(Computation(() -> _collect_row_cells(rows, made)))) :
        _make_roster_list_table(rows, made, headers, view)
    layout = GridLayout(Any[table], 1; column_policies = Any[Fill], row_policies = Any[Fill])
    iomap = RosterRowsToWidgetIoMap(p, rows, layout, columns, table, view)
    # The layout and the table hold their part of the selection and of the part
    # under the pointer. The walk stops at the table: a cell can hold a document
    # of an item, which keeps its own selection.
    is_followed = node -> node isa GridLayout || node isa WidgetTable
    follow_output_selection!(layout, () -> _map_rows_forward(iomap, getfield(rows, :selection)[]);
                             forward_mouse_target = () -> map_mouse_target_forward(rows,
                                 path -> _map_rows_forward(iomap, path)),
                             is_followed)
    iomap
end

# An operation that a route brings to a row or a part of it, which no printed cell
# takes, such as the choice of the menu of the item of a row: the rows answer it
# at that place, so the readers above carry it on. A cell of text prints a label
# and no document, so no child takes such a route.
function read_intent(p::RosterRowsToWidget, recursion, change::Intent, iomap::RosterRowsToWidgetIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    (change.route isa ConcreteReference && change.operation !== nothing) || return answer
    (answer isa Intent ? answer.operation : answer) === nothing || return answer
    steps = Tuple(get_reference_steps(strip_reference_types(change.route)))
    Intent(change.gesture, reroot_operation(change.operation, steps), change.description, change.domain)
end

# The keys of the columns: those that the roster put in the context, or else
# those of the first row, or none.
function _find_roster_columns(rows, ctx)
    columns = ctx === nothing ? nothing : get_property(ctx, :roster_columns, nothing)
    columns === nothing || return collect(String, unwrap_cell(columns))
    isempty(rows) ? String[] : collect(String, rows[1].columns)
end

# The table whose body is the list of the rows from the row `anchor` of `view`.
# Positional, so every declared field is named here in order: position,
# column_headers, row_headers, corner, cells, cell_order, rows, columns,
# border_width, column_policy, row_policy, cell_policy, visible, margin, border,
# padding, style, scroll_position, top_row, column_drag, vertical_scroll_bar,
# horizontal_scroll_bar, open_cells, tooltip.
function _make_roster_list_table(rows, made, headers, view)
    WidgetTable(Cell(Point2D(0, 0)), headers, CellVector(), Cell(nothing),
                Cell(@computation _make_roster_row_list(rows, made, view.anchor)),
                Cell(:row_major), Cell(WidgetTableRows(nothing)),
                Cell(@computation WidgetTableColumns(length(headers))), Cell(1),
                Cell(_ROSTER_COLUMN_POLICY), Cell(Content), Cell(:clip), Cell(true),
                Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                Cell(Point2D(0, 0)), Cell(1), Cell(nothing), Cell(:auto), Cell(:auto),
                Cell(nothing), Cell(nothing))
end

# The list of the cells of the rows of `rows` from the row `anchor`, the same cells
# for a row that stays, made when a walk first reaches the row; no rows is an
# empty vector. `made` keeps the cells from one list to the next, and forgets a
# row that left.
function _make_roster_row_list(rows, made::IdDict{Any,Any}, anchor::Int)
    present = IdDict{Any,Bool}(row => true for row in rows)
    filter!(entry -> haskey(present, entry.first), made)
    isempty(rows) && return CellVector()
    make_index_list(length(rows), anchor, i -> (row = rows[i]; get!(() -> _make_row_cells(row), made, row)))
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
# value. The table reads every cell of a row when it prints, so a cell that
# computes again prints the whole table again. A value that is text when the row
# is made gets a cell that holds its label, and only the text of the label reads
# the value. A value that is a document gets a cell that follows it, so a new
# document shows.
function _make_row_cells(row::RosterRow)
    values = row.values
    slots = Cell[]
    for c in 1:length(values)
        value = get_cell_at(values, c)
        label = WidgetLabel(() -> format_roster_value(value[]))
        push!(slots, peek(value) isa Document ?
                         Cell(Computation(() -> (v = value[]; v isa Document ? v : label))) :
                         Cell(label))
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
    k = r - _get_roster_head_row(iomap) + 1
    whole = _make_table_path(FieldReferenceStep("rows"), ElementReferenceStep(k))
    length(steps) == 1 && return whole
    for c in 1:length(row.columns)
        place = get_reference_steps(_get_column_path(row, r, c))
        length(steps) >= length(place) && all(steps[i] == place[i] for i in eachindex(place)) || continue
        return _make_table_path(FieldReferenceStep("cells"), ElementReferenceStep(k), ElementReferenceStep(c),
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
    head = _get_roster_head_row(iomap)
    item_of(r) = extend_reference(EmptyReference(), ElementReferenceStep(r), FieldReferenceStep("item"))
    if rest[1] == FieldReferenceStep("rows") && length(rest) >= 2 && _is_index_step(rest[2])
        r = head + rest[2].start
        return (1 <= r <= length(rows)) ? item_of(r) : nothing
    end
    if rest[1] == FieldReferenceStep("cells") && length(rest) >= 3 && _is_index_step(rest[2]) &&
       _is_index_step(rest[3])
        r, c = head + rest[2].start, rest[3].start + 1
        (1 <= r <= length(rows)) || return nothing
        row = rows[r]
        (1 <= c <= length(row.columns)) || return nothing
        row.values[c] isa Document || return item_of(r)
        return extend_reference(_get_column_path(row, r, c), rest[4:end]...)
    end
    nothing
end

_is_index_step(step) = step isa RangeReferenceStep && is_element_reference_step(step)

# The row of `rows` at the head of the body: the first for a vector, and the
# anchor for a list, in the range of the rows, as the list takes it. A path of the
# table counts a row from the head.
_get_roster_head_row(iomap::RosterRowsToWidgetIoMap) =
    iomap.view === nothing ? 1 : clamp(iomap.view.anchor, 1, max(1, length(iomap.input)))

# The table moves the head of a list of rows far down by a write of `cells`, with
# a shift of its selection. The roster keeps the head as the anchor of its view,
# so the write of `cells` becomes a write of the anchor, and the shift goes: the
# selection of the rows names a row of `rows`, which the maps place from the
# anchor. Every other answer goes back as it goes from any projection.
function read_intent(p::RosterRowsToWidget, iomap::RosterRowsToWidgetIoMap, operation)
    k = _find_roster_head_move(iomap, operation)
    k === nothing && return invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, operation)
    anchor = _get_roster_head_row(iomap) + k - 1
    moved = Any[ReplaceViewStateOperation(ReplaceReferencedValueOperation(iomap.view, "anchor", anchor))]
    for member in operation.operations
        (member isa ReplaceSelectionOperation || _find_written_cells(iomap.table, member) !== nothing) ||
            push!(moved, member)
    end
    CompoundOperation(moved)
end

# The count from the head of the row that `operation` moves the head of the body
# to, or `nothing` when it moves no head.
function _find_roster_head_move(iomap::RosterRowsToWidgetIoMap, operation)
    (iomap.view !== nothing && operation isa CompoundOperation) || return nothing
    for member in operation.operations
        head = _find_written_cells(iomap.table, member)
        head === nothing || return find_list_index(iomap.table.cells, head)
    end
    nothing
end

# The value that `operation` writes to the whole field `cells` of `table`, or
# `nothing`.
function _find_written_cells(table, operation)
    write = operation isa ReplaceViewStateOperation ? get_wrapped_operation(operation) : operation
    (write isa ReplaceReferencedValueOperation && write.document === table &&
     write.reference isa ConcreteReference && write.reference.head == FieldReferenceStep("cells") &&
     write.reference.tail isa EmptyReference) || return nothing
    write.value
end

# The rows of the natural renderer: a roster, and a list of rows of a roster, which
# a filter or a sort of the rows gives as a list of the same kind. The table is a
# layout of widgets, which the renderer draws.
function _make_roster_graphics_entries(; measure = nothing, appearance)
    Pair{Type,Any}[Roster => RosterToGraphics(),
                   CellVector{RosterRow} => ChainingProjection(RosterRowsToWidget(),
                                                               GridLayoutToGraphicsCanvas())]
end
