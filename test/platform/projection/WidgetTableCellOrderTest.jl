# The order of the cells of a table. A row-major body holds rows, and a cell is
# `cells[r][c]`; a column-major body holds columns, and a cell is `cells[c][r]`.
# The same table in each order draws the same, a press names the cell in the
# order of its body, and the rows and the columns are each a vector or a list,
# in either order.

using ProjecturedKernel.CellModule: Cell, set_cell_computation!, set_cell_value!
using ProjecturedPlatform.CollectionModule: ListNode

function test_widget_table_cell_order()
@testset "the order of the cells of a table" begin

det = FixedMeasure(8, 12, 4, 0)
rec = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
context() = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(300)))
alt = ModifierKeys(alt = true)
read(io, g) = (change = read_intent(rec, nothing, Intent(g, nothing), io);
               change isa Intent ? change.operation : change)
name(r, c) = "r$(r) c$(c)"

# What the graphics draw, as (kind, x, y, w, h, what): each text and each
# rectangle, through viewports and down a list for at most `limit` nodes in each
# direction.
function drawn(node, ox = 0, oy = 0, found = Any[]; limit = 50)
    if node isa GraphicsCanvas
        elements = node.elements
        x, y = ox + Int(node.x), oy + Int(node.y)
        if elements isa ListNode
            for link in (:next, :prev)
                n = link === :next ? elements : elements.prev
                seen = 0
                while n !== nothing && seen < limit
                    drawn(n.value, x, y, found; limit)
                    n = getproperty(n, link)
                    seen += 1
                end
            end
        else
            foreach(element -> drawn(element, x, y, found; limit), elements)
        end
    elseif node isa GraphicsViewport
        drawn(node.content, ox + Int(node.x), oy + Int(node.y), found; limit)
    elseif node isa GraphicsText
        push!(found, (:text, ox + Int(node.x), oy + Int(node.y), 0, 0, string(node.text)))
    elseif node isa GraphicsRect
        push!(found, (:rect, ox + Int(node.x), oy + Int(node.y), Int(node.w), Int(node.h), string(node.color)))
    end
    found
end
texts(io; limit = 50) = [(t[2], t[3], t[6]) for t in drawn(io.output; limit) if t[1] === :text]
text_at(io, text; limit = 50) = only((t[1], t[2]) for t in texts(io; limit) if t[3] == text)
cell_path(outer, inner) = ConcreteReference(FieldReferenceStep("cells"),
    ConcreteReference(RangeReferenceStep(outer - 1, outer),
        ConcreteReference(RangeReferenceStep(inner - 1, inner), EmptyReference())))
outer_of(path) = path.tail.head.start + 1
inner_of(path) = path.tail.tail.head.start + 1
# The cell that an Alt press on the text of a cell selects.
function press(io, text)
    (x, y) = text_at(io, text)
    read(io, MouseClick(:left, x + 2, y + 2, alt; time = 0.0)).path
end
# Where the forward map puts a path, in the graphics of the table.
function place(io, path)
    box = find_reference_box(io.output, map_reference_forward(io.projection, io, path))
    (box.x, box.y, box.width, box.height)
end
# A scroll and a head move are view state that names the table, so they apply
# with no editor. A selection is set on the table, as an editor would.
function apply!(table, op)
    if op isa CompoundOperation
        foreach(inner -> apply!(table, inner), op.operations)
    elseif op isa ReplaceSelectionOperation
        getfield(table, :selection)[] = op.path
    else
        evaluate_operation(nothing, op)
    end
end

# A list of `count` values, built one at a time as a walk reaches them, that
# reaches both ways from index `at`. `value_of(i)` makes the value of node `i`.
function make_list_of(count::Int, value_of; at::Int = 1, built = Ref(0))
    function make_node(i, before, after)
        built[] += 1
        node = ListNode(value_of(i))
        if after === nothing
            set_cell_computation!(getfield(node, :next),
                                  () -> i < count ? make_node(i + 1, node, nothing) : nothing)
        else
            set_cell_value!(getfield(node, :next), after)
        end
        if before === nothing
            set_cell_computation!(getfield(node, :prev),
                                  () -> i > 1 ? make_node(i - 1, nothing, node) : nothing)
        else
            set_cell_value!(getfield(node, :prev), before)
        end
        node
    end
    make_node(at, nothing, nothing)
end
label(r, c) = WidgetLabel(name(r, c))
headers(columns::Int) = Any["h$(c)" for c in 1:columns]
header_list(columns::Int) = make_list_of(columns, c -> WidgetLabel("h$(c)"))
sized(; kw...) = WidgetTable(; column_policy = Fixed(60), row_policy = Fixed(16), kw...)

@testset "each order draws the same, and names a cell in its own order" begin
    rows, columns = 3, 4
    by_rows = WidgetTable(; column_headers = headers(columns),
                          cells = [[name(r, c) for c in 1:columns] for r in 1:rows])
    by_columns = WidgetTable(; column_headers = headers(columns), cell_order = :column_major,
                             cells = [[name(r, c) for r in 1:rows] for c in 1:columns])
    @test by_columns.cell_order === :column_major
    @test by_rows.cell_order === :row_major
    @test by_columns.rows.count == rows
    @test get_widget_table_row_count(by_columns) == get_widget_table_row_count(by_rows) == rows
    @test get_widget_table_column_count(by_columns) == columns
    row_io = print_document(rec, nothing, by_rows, context())
    column_io = print_document(rec, nothing, by_columns, context())
    @test !(column_io isa WidgetTableListIoMap)
    @test drawn(column_io.output) == drawn(row_io.output)
    @test press(row_io, name(2, 3)) == cell_path(2, 3)
    @test press(column_io, name(2, 3)) == cell_path(3, 2)
    @test place(column_io, cell_path(3, 2)) == place(row_io, cell_path(2, 3))
    @test try_evaluate_reference(by_columns, cell_path(3, 2)).content == name(2, 3)
    # The band of a selected cell is where the cell is.
    getfield(by_rows, :selection)[] = cell_path(2, 3)
    getfield(by_columns, :selection)[] = cell_path(3, 2)
    @test drawn(column_io.output) == drawn(row_io.output)
    # A column shorter than the others has empty cells at its end.
    short = WidgetTable(; column_headers = headers(2), cell_order = :column_major,
                        cells = [[name(r, 1) for r in 1:3], [name(1, 2)]])
    @test short.rows.count == 3
    @test [t[3] for t in texts(print_document(rec, nothing, short, context()))] ⊇ [name(3, 1), name(1, 2)]
end

@testset "rows of lists, columns of lists, and both, draw as the rows" begin
    # Each column-major table beside the row-major table that holds the same
    # cells.
    rows, columns = 10_000_000, 1_000_000
    built = Ref(0)
    pairs = [
        # Rows that are lists: a vector of columns, each a list of its rows.
        (sized(; column_headers = headers(3), cell_order = :column_major,
               cells = Any[make_list_of(rows, r -> label(r, c)) for c in 1:3]),
         sized(; column_headers = headers(3),
               cells = make_list_of(rows, r -> make_widget_table_row(Any[label(r, c) for c in 1:3])))),
        # Columns that are a list, each a vector of its rows.
        (sized(; column_headers = header_list(columns), cell_order = :column_major,
               cells = make_list_of(columns, c -> make_widget_table_row(Any[label(r, c) for r in 1:5]))),
         sized(; column_headers = header_list(columns),
               cells = make_list_of(5, r -> make_list_of(columns, c -> label(r, c))))),
        # Both: a list of columns, each a list of its rows.
        (sized(; column_headers = header_list(columns), cell_order = :column_major,
               cells = make_list_of(columns, c -> make_list_of(rows, r -> label(r, c); built))),
         sized(; column_headers = header_list(columns),
               cells = make_list_of(rows, r -> make_list_of(columns, c -> label(r, c))))),
    ]
    for (by_columns, by_rows) in pairs
        column_io = print_document(rec, nothing, by_columns, context())
        @test column_io isa WidgetTableListIoMap
        # The cells that a print builds are the cells that the viewport shows.
        viewport = only(e for e in column_io.state.cells_pane.output.elements if e isa GraphicsViewport)
        Int(viewport.content.x); Int(viewport.content.y)
        @test built[] < 200
        row_io = print_document(rec, nothing, by_rows, context())
        @test sort(texts(column_io)) == sort(texts(row_io))
        @test press(column_io, name(2, 3)) == cell_path(3, 2)
        @test press(row_io, name(2, 3)) == cell_path(2, 3)
        @test place(column_io, cell_path(3, 2)) == place(row_io, cell_path(2, 3))
    end
end

@testset "far from the head, a column-major table moves the head of each column" begin
    table = sized(; column_headers = headers(2), cell_order = :column_major,
                  cells = Any[make_list_of(10_000_000, r -> label(r, c)) for c in 1:2])
    io = print_document(rec, nothing, table, context())
    y_of(text) = text_at(io, text; limit = 400)[2]
    wheel(dy) = read(io, MouseScroll(0, dy, 100, 150; time = 0.0))
    step = y_of(name(2, 1)) - y_of(name(1, 1))
    near = y_of(name(2, 1))
    apply!(table, wheel(-1))
    turn = near - y_of(name(2, 1))
    @test turn > 0
    getfield(table, :scroll_position)[] = Point2D(0, 300 * step)
    getfield(table, :selection)[] = cell_path(2, 305)
    before = y_of(name(305, 2))
    op = wheel(-1)
    @test op isa CompoundOperation
    # The selection names the same cell from the new head.
    @test only(o for o in op.operations if o isa ReplaceSelectionOperation).path == cell_path(2, 5)
    apply!(table, op)
    @test [column.value.content for column in table.cells] == [name(301, 1), name(301, 2)]
    @test y_of(name(305, 2)) == before - turn
    @test y_of(name(305, 1)) == y_of(name(305, 2))
end

@testset "far from the head, a column-major table of lists moves its heads" begin
    # Each table is a list in both directions, and short in the direction that
    # does not move, so a walk of the drawn output stays small.
    lists(columns, rows) = sized(; column_headers = header_list(columns), cell_order = :column_major,
                                 cells = make_list_of(columns, c -> make_list_of(rows, r -> label(r, c))))
    # Three hundred rows down, the head of each column moves to the row at the
    # top.
    table = lists(5, 10_000_000)
    io = print_document(rec, nothing, table, context())
    position_of(text) = text_at(io, text; limit = 400)
    step = position_of(name(2, 1))[2] - position_of(name(1, 1))[2]
    getfield(table, :scroll_position)[] = Point2D(0, 300 * step)
    getfield(table, :selection)[] = cell_path(2, 305)
    op = read(io, MouseScroll(0, -1, 100, 150; time = 0.0))
    @test only(o for o in op.operations if o isa ReplaceSelectionOperation).path == cell_path(2, 5)
    apply!(table, op)
    @test table.cells.value.value.content == name(301, 1)
    @test table.cells.next.value.value.content == name(301, 2)
    @test position_of(name(305, 1))[1] == position_of("h1")[1]
    @test position_of(name(305, 2))[2] == position_of(name(305, 1))[2]
    # Three hundred columns to the side, the head of the list of columns moves
    # to the column at the left.
    table = lists(100_000, 5)
    io = print_document(rec, nothing, table, context())
    left = position_of("h301")[1] - position_of("h1")[1]
    getfield(table, :scroll_position)[] = Point2D(left, 0)
    getfield(table, :selection)[] = cell_path(305, 2)
    before = position_of("h305")[1]
    op = read(io, MouseScroll(-1, 0, 100, 150; time = 0.0))
    @test only(o for o in op.operations if o isa ReplaceSelectionOperation).path == cell_path(5, 2)
    apply!(table, op)
    @test table.column_headers.value.content == "h301"
    @test table.cells.value.value.content == name(1, 301)
    @test position_of(name(1, 305))[1] == position_of("h305")[1]
    @test position_of("h305")[1] < before
end
end
end
