# Fragment of `RosterModule` — what a roster shows: its rows through the
# recursion at their own path, where an arrangement finds them, and a list of rows
# as a table.

"""
    RosterToGraphics()

Prints a [`Roster`](@ref): its `rows` print through the recursion at the path
`rows`, with the keys of the columns and the roster itself in the printer context.
So an entry of an arrangement at `rows` puts its filter, its sort and its bar
before the printer of the rows, as at any collection, and the rows print as a
table ([`RosterRowsToWidget`](@ref)). The output is the output of the rows.
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
    context = with_property(context, :roster, roster)
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

Where the rows print inside an arrangement, each header is the key and the sort
glyph above the field of a filter, as the header of a data frame table is, over
the entry of the arrangement at the place of the rows. The field shows the
condition of its column in the first filter of the entry
([`find_column_filter_text`](@ref)), and an edit of it writes a `:matches` condition
there. The glyph shows the sort of the column, and a click or a Shift+click writes
the keys that [`compute_clicked_sort_keys`](@ref) gives. The menu of the key and the
glyph has "Filter by values…", which lists the values of the column over every row
of the roster. Each edit is an `ArrangeCollectionOperation` at the rows, which the
readers around the table carry to the arrangement. The caret of a field is a path
in the table that the table introduced (`‹column_headers[c]…›`). A table that does
not print inside an arrangement has a plain header of labels.

With `cells` set to `nothing`, a cell whose value is a document shows that document
itself, the same object as in its item, so a key edits it through its own reader,
as in any other place. A cell of any other value shows its text
([`format_roster_value`](@ref)), and a press there selects the item of the row, so
the context menu is the menu of the item. With another `cells` value, the cell of a
column is the widget that [`make_roster_cell`](@ref) makes, which a press also
selects the item of the row for; a method that returns `nothing` leaves the cell
of that item to the table, which makes it as it does for `nothing`. A page puts its own `RosterRowsToWidget` with its
`cells` value in the dispatch of its widgets.

The columns divide the width in the ratio of `shares` of the roster in the printer
context (`:roster`), and equally where the context has no roster or the roster has
no shares. The row of the item that `marked` of that roster names is the selected
row of the table while the selection of the editor is not in the rows.
The head of a list is the row of the item that `anchor` of the roster names, or the
first row when the rows do not show it; a roster with no `anchor` keeps the head in
the table. A scroll far from the head writes the item to `anchor`, as view state.
A row keeps its cells while it stays, so in a list the grid keeps the print of a
row that a filter or a sort keeps, and prints only the rows that are new to it.
"""
struct RosterRowsToWidget <: Projection
    widget::Any         # the widget theme that gives the styles of a header, or nothing
    cells::Any          # the value that make_roster_cell dispatches on, or nothing
end

Base.show(io::IO, ::RosterRowsToWidget) = print(io, "RosterRowsToWidget()")

RosterRowsToWidget(widget = nothing) = RosterRowsToWidget(widget, nothing)

make_roster_cell(::Nothing, item, key, value) = WidgetLabel(() -> format_roster_value(value[]))

@iomap struct RosterRowsToWidgetIoMap
    projection::Any
    input::Any          # CellVector{RosterRow}
    output::Any         # GridLayout of the table
    columns::Any        # the keys of the columns
    table::Any          # the WidgetTable of the rows
    view::Any           # the _RosterTableView of a body that is a list, or nothing
    head::Any           # the Cell of the row at the head of a body that is a list, or nothing
    roster::Any         # the roster of the printer context, or nothing
    is_filtering::Bool  # whether the header holds the parts of a filter and a sort
    entry::Any          # the Cell of the entry of the place, or nothing for a plain header
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
    entry = is_arranged_place(ctx) ? Cell(@computation find_arranged_entry(ctx)) : nothing
    headers = entry === nothing ? CellVector(Cell[Cell(WidgetLabel(format_roster_column_label(key))) for key in columns]) :
              CellVector(@computation Any[_make_filter_header(p, rows, entry, ctx, key, c)
                                          for (c, key) in enumerate(columns)])
    roster = ctx === nothing ? nothing : get_property(ctx, :roster, nothing)
    view = (ctx !== nothing && get_exact_height(ctx) !== nothing) ? _RosterTableView(1) : nothing
    head = view === nothing ? nothing : Cell(@computation _compute_head_row(rows, roster, view))
    table = view === nothing ?
        WidgetTable(headers, CellVector(Computation(() -> _collect_row_cells(p, rows, made)))) :
        _make_roster_list_table(p, rows, made, headers, head)
    layout = GridLayout(Any[table], 1; column_policies = Any[Fill], row_policies = Any[Fill])
    iomap = RosterRowsToWidgetIoMap(p, rows, layout, columns, table, view, head, roster, entry !== nothing, entry)
    _set_column_shares!(table, roster, length(columns))
    # The layout and the table hold their part of the selection and of the part
    # under the pointer. The walk stops at the table: a cell can hold a document
    # of an item, which keeps its own selection.
    is_followed = node -> node isa GridLayout || node isa WidgetTable
    follow_output_selection!(layout, () -> _map_selection_or_mark(iomap, roster);
                             forward_mouse_target = () -> map_mouse_target_forward(rows,
                                 path -> _map_rows_forward(iomap, path)),
                             is_followed)
    iomap
end

# ── The header of a table in an arrangement ──────────────────────────────────

# The steps below the table to the text of the filter field of header `c`,
# `column_headers[c].children[2].content[a:b]`, where `make_labeled_field` puts
# the field.
_make_header_field_path(c::Int, a::Int, b::Int) =
    _make_table_path(FieldReferenceStep("column_headers"), ElementReferenceStep(c), FieldReferenceStep("children"),
                     ElementReferenceStep(2), FieldReferenceStep("content"), RangeReferenceStep(a, b))

# The number of the header, and the start and the stop of the range, of the path
# `steps` in the layout when it goes into the text of a filter field, or
# `nothing`.
function _find_header_field(steps)
    n = length(_TABLE_STEPS)
    (length(steps) == n + 6 && all(steps[k] == _TABLE_STEPS[k] for k in 1:n) &&
     steps[n + 1] == FieldReferenceStep("column_headers") && _is_index_step(steps[n + 2]) &&
     steps[n + 3] == FieldReferenceStep("children") && steps[n + 4] == ElementReferenceStep(2) &&
     steps[n + 5] == FieldReferenceStep("content") && steps[n + 6] isa RangeReferenceStep) || return nothing
    (steps[n + 2].start + 1, steps[n + 6].start, steps[n + 6].stop)
end

# Whether `path`, a path in the layout of the table, goes into a header: a part
# that makes an operation there arranges the rows, so its place is the rows.
function _is_header_path(path)
    path isa ConcreteReference || return false
    steps = get_reference_steps(strip_reference_types(path))
    n = length(_TABLE_STEPS)
    length(steps) > n && all(steps[k] == _TABLE_STEPS[k] for k in 1:n) && steps[n + 1] == FieldReferenceStep("column_headers")
end

# `operation` made at a part of a header, put at the rows, or `nothing` for any
# other operation: the arrangement of the rows that the part edits, and the menu
# of the part, are of the rows, which the readers around the table can place.
function _retarget_header_operation(operation)
    inner = operation isa WrappingOperation ? get_wrapped_operation(operation) : operation
    inner isa Union{ArrangeCollectionOperation,OpenContextMenuOperation} || return nothing
    _is_header_path(operation_reference(inner)) || return nothing
    moved = retarget_operation(inner, EmptyReference())
    operation isa WrappingOperation ? rewrap_operation(operation, moved) : moved
end

# The range `(start, stop)` of the caret in the filter field of header `c`, or
# `nothing`: the selection of `rows` is the step that the table introduced.
function _find_header_range(rows, c::Int)
    selection = getfield(rows, :selection)[]
    (selection isa ConcreteReference && selection.head isa ProjectionReferenceStep &&
     selection.head.projection isa RosterRowsToWidget) || return nothing
    found = _find_header_field(get_reference_steps(strip_reference_types(selection.head.output_path)))
    (found === nothing || found[1] != c) ? nothing : (found[2], found[3])
end

# The header of column `key`, number `c`: the key and the sort glyph above the
# field of the filter. The key and the glyph have the menu of the column.
function _make_filter_header(p::RosterRowsToWidget, rows, entry, ctx, key::String, c::Int)
    style(name) = unwrap_cell(get_widget_style(p.widget, name))
    text() = find_column_filter_text(entry[], key)
    function reason()
        condition = parse_filter_text(text())
        condition isa String ? condition : nothing
    end
    glyph = make_sort_glyph(get_column_sort_keys(entry[]), key, style(:unsorted_glyph),
                            adding -> _make_sort_operation(entry, key, adding); domain = "roster")
    menu = WidgetMenu(Any[WidgetMenuItem("Filter by values…";
                                         action = Action("Filter by values…";
                                                         callback = editor -> _open_value_list!(p, editor, rows, ctx, entry, key)))])
    label = WidgetContextMenu(HorizontalLayout(Any[WidgetLabel(format_roster_column_label(key)), glyph...]; gap = Int(style(:header_gap))), menu)
    make_labeled_field(label, make_filter_field(text, () -> _find_header_range(rows, c), reason,
                                                0, style(:invalid_filter)),
                       Int(style(:header_field_minimum_width)))
end

# The edit of a click on the glyph of column `key`: the new sort of the entry.
function _make_sort_operation(entry, key::String, adding::Bool)
    keys = compute_clicked_sort_keys(get_column_sort_keys(entry[]), key, adding)
    ArrangeCollectionOperation(EmptyReference(), make_column_sort(entry[], keys))
end

# The edit of a key in the filter field of header `c`, or `nothing` for an edit
# elsewhere: the new filter of the entry, and the caret after the text that was
# put in, as one step.
function _make_header_edit(p::RosterRowsToWidget, iomap::RosterRowsToWidgetIoMap, operation::ReplaceStringRangeOperation)
    iomap.is_filtering || return nothing
    found = _find_header_field(get_reference_steps(strip_reference_types(operation.reference)))
    found === nothing && return nothing
    (c, a, b) = found
    key = iomap.columns[c]
    old = find_column_filter_text(iomap.entry, key)
    new = string(first(old, a), operation.replacement, chop(old; head = b, tail = 0))
    caret = a + length(operation.replacement)
    CompoundOperation(Any[ArrangeCollectionOperation(EmptyReference(), make_column_filter(iomap.entry, key, new)),
                          ReplaceSelectionOperation(make_introduced_reference(p, iomap.input,
                              _make_header_field_path(c, caret, caret)))])
end

# Open the dialog of the values of column `key` over every row of the roster. The
# boxes are ticked by the filter text of the column, and "Apply" posts the filter
# that writes `= a, b` as the condition of the column.
function _open_value_list!(p::RosterRowsToWidget, editor, rows, ctx, entry, key::String)
    roster = get_property(ctx, :roster, nothing)
    items = roster === nothing ? rows : roster.rows
    text = find_column_filter_text(entry[], key)
    function write(values, ticked)
        written = make_value_list_text(values, ticked)
        found = roster === nothing ? Any[] : search_references(editor.document, node -> node === roster; maxdepth = 24)
        (written === nothing || isempty(found)) && return nothing
        filter = make_column_filter(entry[], key, written)
        make_filter_collection_operation(ReferencedDocument(roster, strip_reference_types(found[1])),
                                         filter.conditions...; editor)
    end
    dialog, take = make_value_list_dialog(format_roster_column_label(key), collect_column_values(items, key),
                                          value -> is_value_listed(text, value), write; widget = p.widget)
    window = unwrap_cell(get_widget_style(p.widget, :value_list_window_size))
    apply = last(collect(dialog.buttons))
    apply.action = Action(apply.action.label;
                          callback = _ -> (operation = take();
                                           operation === nothing || post_operation!(editor, operation);
                                           nothing))
    evaluate_operation(editor, OpenWindowOperation(id = :value_list, title = "Filter by values",
                                                   x = -1, y = -1, width = Int(window.x[]),
                                                   height = Int(window.y[]),
                                                   style = :floating, content = dialog))
    nothing
end

# An operation that a route brings to a row or a part of it, which no printed cell
# takes, such as the choice of the menu of the item of a row: the rows answer it
# at that place, so the readers above carry it on. A cell of text prints a label
# and no document, so no child takes such a route.
#
# A double click on a row opens the item of the row as a page, as a double click
# on a file opens the file: the first press selects the item, and the second one
# opens what the row selects.
function read_intent(p::RosterRowsToWidget, recursion, change::Intent, iomap::RosterRowsToWidgetIoMap)
    answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
    operation = answer isa Intent ? answer.operation : answer
    if change.route isa ConcreteReference && change.operation !== nothing
        operation === nothing || return answer
        steps = Tuple(get_reference_steps(strip_reference_types(change.route)))
        return Intent(change.gesture, reroot_operation(change.operation, steps), change.description, change.domain)
    end
    item = answer isa Intent ? _find_double_clicked_item(change.gesture, operation) : nothing
    item === nothing && return answer
    Intent(answer.gesture, CompoundOperation(Any[operation, OpenPageOperation(nothing, item)]),
           answer.description, answer.domain)
end

# The keys of the columns: those that the roster put in the context, or else
# those of the first row, or none.
function _find_roster_columns(rows, ctx)
    columns = ctx === nothing ? nothing : get_property(ctx, :roster_columns, nothing)
    columns === nothing || return collect(String, unwrap_cell(columns))
    isempty(rows) ? String[] : collect(String, rows[1].columns)
end

# The table whose body is the list of the rows from the row `head`.
# Positional, so every declared field is named here in order: position,
# column_headers, row_headers, corner, cells, cell_order, rows, columns,
# border_width, column_policy, row_policy, cell_policy, visible, margin, border,
# padding, style, scroll_position, top_row, column_drag, vertical_scroll_bar,
# horizontal_scroll_bar, open_cells, tooltip.
function _make_roster_list_table(p, rows, made, headers, head)
    WidgetTable(Cell(Point2D(0, 0)), headers, CellVector(), Cell(nothing),
                Cell(@computation _make_roster_row_list(p, rows, made, head[])),
                Cell(:row_major), Cell(WidgetTableRows(nothing)),
                Cell(@computation WidgetTableColumns(length(headers))), Cell(1),
                Cell(_ROSTER_COLUMN_POLICY), Cell(Content), Cell(:clip), Cell(true),
                Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                Cell(Point2D(0, 0)), Cell(1), Cell(nothing), Cell(nothing), Cell(:auto), Cell(:auto),
                Cell(nothing), Cell(nothing))
end

# The list of the cells of the rows of `rows` from the row `anchor`, the same cells
# for a row that stays, made when a walk first reaches the row; `nothing` is a
# list with no rows. `made` keeps the cells from one list to the next, and
# forgets a row that left.
function _make_roster_row_list(p, rows, made::IdDict{Any,Any}, anchor::Int)
    present = IdDict{Any,Bool}(row => true for row in rows)
    filter!(entry -> haskey(present, entry.first), made)
    isempty(rows) && return nothing
    make_index_list(length(rows), anchor, i -> (row = rows[i]; get!(() -> _make_row_cells(p, row), made, row)))
end

# The cells of each row of `rows`, the same cells for a row that stays. `made`
# keeps them from one computation to the next.
function _collect_row_cells(p, rows, made::IdDict{Any,Any})
    kept = IdDict{Any,Any}()
    found = Any[]
    for row in rows
        cells = get(made, row, nothing)
        cells === nothing && (cells = _make_row_cells(p, row))
        kept[row] = cells
        push!(found, cells)
    end
    empty!(made)
    merge!(made, kept)
    found
end

# The cells of one row: the document that a value is, or a label of the text of the
# value, which in the first column is a link to the item of the row. The table
# reads every cell of a row when it prints, so a cell that computes again prints
# the whole table again. A value that is text when the row is made gets a cell
# that holds its label, and only the text of the label reads the value. A value
# that is a document gets a cell that follows it, so a new document shows.
function _make_row_cells(p::RosterRowsToWidget, row::RosterRow)
    values = row.values
    slots = Cell[]
    for c in 1:length(values)
        value = get_cell_at(values, c)
        made = p.cells === nothing ? nothing : make_roster_cell(p.cells, row.item, row.columns[c], value)
        is_default = made === nothing
        label = !is_default ? made :
                c == 1 ? _make_item_link(value) : make_roster_cell(nothing, row.item, row.columns[c], value)
        _follow_cell_mouse_target!(label, row, c)
        push!(slots, is_default && peek(value) isa Document ?
                         Cell(Computation(() -> (v = value[]; v isa Document ? v : label))) :
                         Cell(label))
    end
    CellVector(slots)
end

# A cell that the rows make holds the empty path while the mouse target of its row
# names it, below the item, as a part that the rows draw, so a link lights under
# the pointer.
function _follow_cell_mouse_target!(widget, row::RosterRow, c::Int)
    hasfield(typeof(widget), :mouse_target) || return widget
    set_cell_computation!(getfield(widget, :mouse_target), () ->
        _find_cell_column(get_mouse_target(row)) == c ? EmptyReference() : nothing)
    widget
end

# The column of the cell that `target`, a path from a row, names below the item of
# the row as a part that the rows draw, or `nothing`.
function _find_cell_column(target)
    target isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(target))
    (length(steps) == 2 && steps[1] == FieldReferenceStep("item") &&
     steps[2] isa ProjectionReferenceStep && steps[2].projection isa RosterRowsToWidget) || return nothing
    column = get_reference_steps(steps[2].output_path)
    (length(column) == 1 && _is_index_step(column[1])) ? column[1].start + 1 : nothing
end

# The link of the first cell of a row, with the text of `value`. Its open names the
# part itself, and the rows map the path of a cell that is no document to the item.
_make_item_link(value) = WidgetLink(() -> format_roster_value(value[]), EmptyReference())

# The path of a column `c` of the row at `r`, as the roster holds it: below the item
# for a path of fields, below the outer item for a path after `within`, and the
# value cell of the column for a facet.
function _get_column_path(row::RosterRow, r::Int, c::Int)
    key = row.columns[c]
    names = split(key, '.')
    head = String(names[1])
    steps = if head == "within" && length(names) > 1 && has_item_facet(row.within, String(names[2]))
        Any[FieldReferenceStep("values"), ElementReferenceStep(c)]
    elseif head == "within"
        Any[FieldReferenceStep("within"), (FieldReferenceStep(String(n)) for n in names[2:end])...]
    elseif has_item_facet(row.item, head)
        Any[FieldReferenceStep("values"), ElementReferenceStep(c)]
    else
        Any[FieldReferenceStep("item"), (FieldReferenceStep(String(n)) for n in names)...]
    end
    extend_reference(EmptyReference(), ElementReferenceStep(r), steps...)
end

# The steps from the layout to the table.
const _TABLE_STEPS = (FieldReferenceStep("children"), ElementReferenceStep(1))

_make_table_path(steps...) = extend_reference(EmptyReference(), _TABLE_STEPS..., steps...)

# The path in the layout of the whole row `r` of the rows. A list counts the row
# from its head, so a row before the head has a number of zero or less.
_make_row_path(iomap::RosterRowsToWidgetIoMap, r::Int) =
    _make_table_path(FieldReferenceStep("rows"), ElementReferenceStep(r - _get_roster_head_row(iomap) + 1))

# The path in the layout of the selection of the rows; where the selection is not
# in the rows, the path of the row of the item that `roster` marks, or `nothing`.
function _map_selection_or_mark(iomap::RosterRowsToWidgetIoMap, roster)
    shown = _map_rows_forward(iomap, getfield(iomap.input, :selection)[])
    (shown !== nothing || roster === nothing) && return shown
    marked = roster.marked
    marked === nothing && return nothing
    r = findfirst(row -> peek(getfield(row, :item)) === marked, iomap.input)
    r === nothing ? nothing : _make_row_path(iomap, r)
end

# The width of the columns of `table` in the ratio of the `shares` of `roster`,
# which a column beyond the weights takes as 1; the table keeps what it has for a
# roster with no shares.
function _set_column_shares!(table, roster, count::Int)
    (roster === nothing || roster.shares === nothing) && return table
    set_cell_computation!(getfield(table, :columns), () -> begin
        shares = roster.shares
        shares === nothing ? WidgetTableColumns(count) :
            Any[WidgetTableColumn(; policy = SizePolicy(nothing, nothing, nothing,
                                                        Float64(c <= length(shares) ? shares[c] : 1.0)))
                for c in 1:count]
    end)
    table
end

# The path in the layout of the path `path` of the rows: a whole row for the row
# or its item, and a cell for a path at or below the place of its column.
function _map_rows_forward(iomap::RosterRowsToWidgetIoMap, path)
    path === nothing && return nothing
    is_introduced_reference(path, iomap.projection) && return path.head.output_path
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
    whole = _make_row_path(iomap, r)
    length(steps) == 1 && return whole
    c = _find_cell_column(extend_reference(EmptyReference(), steps[2:end]...))
    c === nothing ||
        return _make_table_path(FieldReferenceStep("cells"), ElementReferenceStep(k), ElementReferenceStep(c))
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
    # A part of the header is a part that the table drew, which a gesture routes to
    # and a caret in a field holds, by the introduced step.
    iomap.is_filtering && rest[1] == FieldReferenceStep("column_headers") &&
        return make_introduced_reference(get_iomap_projection(iomap), iomap.input, extend_reference(EmptyReference(), steps...))
    rows = iomap.input
    head = _get_roster_head_row(iomap)
    item_of(r) = extend_reference(EmptyReference(), ElementReferenceStep(r), FieldReferenceStep("item"))
    if rest[1] == FieldReferenceStep("rows") && length(rest) >= 2 && _is_index_step(rest[2])
        r = head + rest[2].start
        return (1 <= r <= length(rows)) ? item_of(r) : nothing
    end
    cell = _find_table_cell(iomap, rest)
    cell === nothing && return nothing
    (r, c) = cell
    row = rows[r]
    row.values[c] isa Document || return item_of(r)
    extend_reference(_get_column_path(row, r, c), rest[4:end]...)
end

# The row and the column of the cell that `rest`, the steps of a path of the table,
# names, or `nothing`.
function _find_table_cell(iomap::RosterRowsToWidgetIoMap, rest)
    (length(rest) >= 3 && rest[1] == FieldReferenceStep("cells") && _is_index_step(rest[2]) &&
     _is_index_step(rest[3])) || return nothing
    rows = iomap.input
    r, c = _get_roster_head_row(iomap) + rest[2].start, rest[3].start + 1
    (1 <= r <= length(rows) && 1 <= c <= length(rows[r].columns)) ? (r, c) : nothing
end

# The part under the pointer in a cell that holds no document: the item of its
# row and, below it, the cell as a part that the rows draw. So the item stays the
# document under the pointer, whose menu a right click shows, and the cell lights.
# Any other part maps as a path does.
function _map_mouse_target_backward(p::RosterRowsToWidget, iomap::RosterRowsToWidgetIoMap,
                                    operation::ReplaceMouseTargetOperation)
    path = get_operation_path(operation)
    steps = path isa ConcreteReference ? get_reference_steps(strip_reference_types(path)) : ReferenceStep[]
    inside = length(steps) >= length(_TABLE_STEPS) && all(steps[k] == _TABLE_STEPS[k] for k in eachindex(_TABLE_STEPS))
    cell = inside ? _find_table_cell(iomap, steps[(length(_TABLE_STEPS) + 1):end]) : nothing
    (cell === nothing || iomap.input[cell[1]].values[cell[2]] isa Document) &&
        return invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, operation)
    (r, c) = cell
    make_path_operation(operation, extend_reference(EmptyReference(), ElementReferenceStep(r), FieldReferenceStep("item"),
                                                    ProjectionReferenceStep(p, Reference(ElementReferenceStep(c)))))
end

_is_index_step(step) = step isa RangeReferenceStep && is_element_reference_step(step)

# The row of `rows` at the head of the body: the first for a vector, and the
# anchor for a list, in the range of the rows, as the list takes it. A path of the
# table counts a row from the head.
_get_roster_head_row(iomap::RosterRowsToWidgetIoMap) =
    iomap.view === nothing ? 1 : clamp(iomap.head, 1, max(1, length(iomap.input)))

# The row of `rows` at the head of a list: the row of the item that `anchor` of
# `roster` names, or the first row when the rows do not show that item, or the
# anchor of `view` for a roster that names no item.
function _compute_head_row(rows, roster, view)
    item = roster === nothing ? nothing : roster.anchor
    item === nothing && return view.anchor
    something(findfirst(row -> peek(getfield(row, :item)) === item, rows), 1)
end

# The table moves the head of a list of rows far down by a write of `cells`, with
# a shift of its selection. The roster keeps the head as the anchor of its view,
# so the write of `cells` becomes a write of the anchor, and the shift goes: the
# selection of the rows names a row of `rows`, which the maps place from the
# anchor. Every other answer goes back as it goes from any projection.
function read_intent(p::RosterRowsToWidget, iomap::RosterRowsToWidgetIoMap, operation)
    operation isa ReplaceMouseTargetOperation && return _map_mouse_target_backward(p, iomap, operation)
    if operation isa ReplaceStringRangeOperation
        edit = _make_header_edit(p, iomap, operation)
        edit === nothing || return edit
    end
    moved = _retarget_header_operation(operation)
    moved === nothing || return moved
    k = _find_roster_head_move(iomap, operation)
    k === nothing && return invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, operation)
    anchor = _get_roster_head_row(iomap) + k - 1
    moved = Any[ReplaceViewStateOperation(_make_head_write(iomap, anchor))]
    for member in operation.operations
        (member isa ReplaceSelectionOperation || _find_written_cells(iomap.table, member) !== nothing) ||
            push!(moved, member)
    end
    CompoundOperation(moved)
end

# The write of the head of a list at row `anchor`: the item of that row as the
# `anchor` of the roster when the roster names one, else the anchor of the view.
function _make_head_write(iomap::RosterRowsToWidgetIoMap, anchor::Int)
    roster = iomap.roster
    (roster !== nothing && roster.anchor !== nothing && 1 <= anchor <= length(iomap.input)) ?
        ReplaceReferencedValueOperation(roster, "anchor", peek(getfield(iomap.input[anchor], :item))) :
        ReplaceReferencedValueOperation(iomap.view, "anchor", anchor)
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

# The path of the item of a row that a plain double click selects, or `nothing`.
function _find_double_clicked_item(gesture, operation)
    (gesture isa MouseClick && gesture.button === :left && gesture.count == 2 &&
     gesture.modifiers == ModifierKeys() && operation isa ReplaceSelectionOperation) || return nothing
    steps = get_reference_steps(strip_reference_types(operation.path))
    (length(steps) == 2 && _is_index_step(steps[1]) && steps[2] == FieldReferenceStep("item")) || return nothing
    operation.path
end

# The rows of the natural renderer: a roster, and a list of rows of a roster, which
# a filter or a sort of the rows gives as a list of the same kind. The table is a
# layout of widgets, which the renderer draws.
function _make_roster_graphics_entries(; measure = nothing, appearance)
    Pair{Type,Any}[Roster => RosterToGraphics(),
                   CellVector{RosterRow} => ChainingProjection(RosterRowsToWidget(get_scaled_theme!(appearance, WidgetTheme)),
                                                               GridLayoutToGraphicsCanvas())]
end
