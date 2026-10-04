# A table whose rows are a list, which scrolls its own parts.
#
# The cost of such a table is the rows a viewport shows, so the first test
# counts rows built and not pixels; the rest read where a cell landed, what a
# press answered, where the offset stops, and what a reference maps to, against
# the eager table over the same data where the two must agree.

using ProjecturedKernel.CellModule: Cell, Computation, set_cell_computation!,
                                    set_cell_value!
using ProjecturedPlatform.CollectionModule: ListNode

# A weighted column with no minimum is at least as wide as its header. Wide, each
# column is its header and an equal share of what is left; narrow, each keeps
# its header, and the cells are wider than their viewport, which the table
# scrolls.
function test_widget_table_list_header_floor()
@testset "a weighted column is at least as wide as its header" begin
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    grow = SizePolicy(nothing, nothing, nothing, 1.0)
    head = ListNode(make_widget_table_row(Any["a", "b"]))
    table = WidgetTable(; column_headers = Any["id", "a much longer header"],
                        rows = head, column_count = 2, column_policies = Any[grow, grow])
    function print_at(width)
        ctx = with_exact_size(PrinterContext(); width = Cell(Int32(width)),
                              height = Cell(Int32(300)))
        print_document(rec, nothing, table, ctx)
    end
    widths(io) = Int[Int(c[]) for c in io.state.cells_pane.content_iomap.col_w]
    wide = print_at(900)
    @test Int(wide.output.w[]) == 900
    # The same share on top of each header, less a pixel of rounding.
    @test abs((widths(wide)[2] - widths(wide)[1]) - 8 * (length("a much longer header") - length("id"))) <= 1
    narrow = print_at(100)
    @test widths(narrow) == [8 * length("id"), 8 * length("a much longer header")]
    @test Int(narrow.output.w[]) == 100
    @test Int(narrow.state.cells_pane.content_iomap.output.w) > 100
end
end

function test_widget_table_list()
@testset "a table whose rows are a list" begin

det = FixedMeasure(8, 12, 4, 0)
rec = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
context() = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(300)))
mods = ModifierKeys()
alt = ModifierKeys(alt = true)

# A list of `count` rows whose nodes are built one at a time as a walk
# reaches them, counting the builds. `cell(i, c)` says what row i holds.
function make_list(count::Int, cell; built = Ref(0), from::Int = 1)
    function make_node(i)
        built[] += 1
        node = ListNode(make_widget_table_row(Any[cell(i, c) for c in 1:2]))
        set_cell_computation!(getfield(node, :next), () -> begin
            i < count || return nothing
            following = make_node(i + 1)
            set_cell_value!(getfield(following, :prev), node)
            following
        end)
        node
    end
    make_node(from)
end
texts_of(i, c) = c == 1 ? "row " * string(i) : string(i * 10)

policies = Any[Fixed(120), Fixed(80)]
make_table(rows; kw...) = WidgetTable(; column_headers = Any["name", "value"],
                                      rows, column_count = 2, column_policies = policies, kw...)

# Every text a canvas drew, as (x, y, text), through viewports and down a list
# for at most `limit` nodes in each direction.
function texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[]; limit = 50)
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            n = elements; seen = 0
            while n !== nothing && seen < limit
                texts(n.value, ox + Int(node.x), oy + Int(node.y), found; limit); n = n.next; seen += 1
            end
            n = elements.prev; seen = 0
            while n !== nothing && seen < limit
                texts(n.value, ox + Int(node.x), oy + Int(node.y), found; limit); n = n.prev; seen += 1
            end
        else
            for element in elements
                texts(element, ox + Int(node.x), oy + Int(node.y), found; limit)
            end
        end
    elseif node isa GraphicsViewport
        texts(node.content, ox + Int(node.x), oy + Int(node.y), found; limit)
    elseif node isa GraphicsText
        push!(found, (ox + Int(node.x), oy + Int(node.y), string(node.text)))
    end
    found
end
read(io, g) = begin
    change = read_intent(rec, nothing, Intent(g, nothing), io)
    change isa Intent ? change.operation : change
end
row_of(path) = path.tail.head.start + 1
column_of(path) = path.tail.tail.head.start + 1

# What a test reads of a printed table: the grid of the cells and the rows it
# placed, the gap between two rows, and the regions of the header row and of
# the cells, which are the last two elements of the table.
grid_of(io) = io.state.cells_pane.content_iomap
head_of(io) = get_grid_list_head(grid_of(io))
gap_of(io) = 2 * io.state.pad_y + io.state.bw
header_region(io) = io.output.elements[end - 1]
cells_region(io) = io.output.elements[end]
cells_viewport(io) = only(e for e in io.state.cells_pane.output.elements if e isa GraphicsViewport)
# The top and the bottom of the viewport of the cells, in the table.
body_top(io) = Int(cells_region(io).y) + Int(cells_viewport(io).y)
body_bottom(io) = body_top(io) + Int(cells_viewport(io).h)
label_y(io, label; limit = 50) = only(t[2] for t in texts(io.output; limit) if t[3] == label)
# Where the cell in row `k` and column `c` begins, in the table.
cell_reference(k, c) = ConcreteReference(FieldReferenceStep("rows"),
    ConcreteReference(RangeReferenceStep(k - 1, k),
        ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference())))
function place(io, k, c)
    image = map_reference_forward(io.projection, io, cell_reference(k, c))
    box = find_reference_box(io.output, image)
    (box.x, box.y)
end
wheel(io, dy) = read(io, MouseScroll(0, dy, 100, 150; time = 0.0))
# A scroll is view state that names the table, so it applies with no editor. A
# selection that a scroll moves is set on the table here, as an editor would.
function apply!(table, op)
    if op isa CompoundOperation
        foreach(inner -> apply!(table, inner), op.operations)
    elseif op isa ReplaceSelectionOperation
        getfield(table, :selection)[] = op.path
    else
        evaluate_operation(nothing, op)
    end
end

@testset "a list of 100,000 rows builds a handful" begin
    built = Ref(0)
    io = print_document(rec, nothing, make_table(make_list(100_000, texts_of; built)), context())
    @test io isa WidgetTableListIoMap
    @test head_of(io) isa ListNode
    # Printing built the head and nothing else; following twenty links builds
    # twenty more, and the other 99,979 are never built.
    @test built[] == 1
    node = head_of(io); seen = 0
    while node !== nothing && seen < 20
        seen += 1; node = node.next
    end
    @test seen == 20
    @test built[] == 21
end

@testset "the same rows, as a vector and as a list, draw the same texts at the same places" begin
    vector = WidgetTable(Any["name", "value"],
                         Any[Any[texts_of(i, 1), texts_of(i, 2)] for i in 1:3];
                         column_policies = policies)
    list = make_table(make_list(3, texts_of))
    eager = Set(texts(print_document(rec, nothing, vector, context()).output))
    lazy  = Set(texts(print_document(rec, nothing, list, context()).output))
    @test lazy == eager
    @test length(lazy) == 8   # two names and six cells
end

@testset "a widget in a list cell draws, and a press on it reaches it" begin
    box = WidgetCheckbox("abc")
    rows = make_list(3, (i, c) -> (i == 2 && c == 1) ? box : texts_of(i, c))
    io = print_document(rec, nothing, make_table(rows), context())
    # The box is drawn: row two is built once walked to, and its first cell's
    # canvas has an extent.
    found = find_grid_list_row(grid_of(io), 2)
    @test found !== nothing
    box_canvas = found[2][1][3].output
    @test box_canvas isa GraphicsCanvas
    @test Int(box_canvas.w) > 0 && Int(box_canvas.h) > 0
    # An Alt+press selects the cell.
    (x, y) = place(io, 2, 1)
    op = read(io, MouseClick(:left, x + 2, y + 2, alt; time = 0.0))
    @test op isa ReplaceSelectionOperation
    @test op.path.head.name == "rows"
    @test row_of(op.path) == 2
    @test column_of(op.path) == 1
    # A plain press on the box goes to the checkbox, and what it answers — a
    # toggle of its own document — comes back as it is.
    plain = read(io, MouseClick(:left, x + 4, y + 4, mods; time = 0.0))
    @test plain isa ReplaceReferencedValueOperation
    @test plain.document === box
    # A plain press on a label, which declines it, selects the row.
    (x2, y2) = place(io, 2, 2)
    on_text = read(io, MouseClick(:left, x2 + 2, y2 + 2, mods; time = 0.0))
    @test on_text isa ReplaceSelectionOperation
    @test on_text.path.head.name == "rows"
    @test row_of(on_text.path) == 2
    @test on_text.path.tail.tail isa EmptyReference
    # A press on a header selects its column.
    (hx, hy, _) = only(t for t in texts(io.output) if t[3] == "value")
    column = read(io, MouseClick(:left, hx + 2, hy + 2, mods; time = 0.0))
    @test column isa ReplaceSelectionOperation
    @test column.path.head.name == "columns"
    @test column.path.tail.head.start + 1 == 2
end

@testset "rows of different heights, and the row at a coordinate" begin
    long = "a value that is far too wide for one hundred and twenty pixels"
    rows = make_list(3, (i, c) -> (i == 2 && c == 1) ? long : texts_of(i, c))
    io = print_document(rec, nothing, make_table(rows; cell_policy = :wrap), context())
    first = head_of(io).value
    second = head_of(io).next.value
    third = head_of(io).next.next.value
    gap = gap_of(io)
    @test Int(second.h) > Int(first.h)
    @test Int(second.y) == Int(first.y) + Int(first.h) + gap
    @test Int(third.y) == Int(second.y) + Int(second.h) + gap
    # A press near the bottom of row two, and in the padding under it, names
    # row two; a press past the rule under it names row three.
    (x, top) = place(io, 2, 2)
    for y in (top + Int(second.h) - 2, top + Int(second.h) + io.state.pad_y - 1)
        op = read(io, MouseClick(:left, x + 2, y, alt; time = 0.0))
        @test op isa ReplaceSelectionOperation
        @test row_of(op.path) == 2
        @test column_of(op.path) == 2
    end
    below = read(io, MouseClick(:left, x + 2, top + Int(second.h) + gap + 1, alt; time = 0.0))
    @test row_of(below.path) == 3
end

@testset "a row before the head has an index of zero, and a reference reaches it" begin
    head = make_list(3, texts_of; from = 2)
    pushfirst!(head, make_widget_table_row(Any["row 1", "10"]))
    io = print_document(rec, nothing, make_table(head), context())
    before = head_of(io).prev
    @test before !== nothing
    @test Int(before.value.y) == -Int(before.value.h) - gap_of(io)
    @test any(t -> t[3] == "row 1", texts(io.output))
    # `rows[0][1]` is the cell before the head; its image sits above the head's.
    image = map_reference_forward(io.projection, io, cell_reference(0, 1))
    at_head = map_reference_forward(io.projection, io, cell_reference(1, 1))
    @test image !== nothing && at_head !== nothing
    top(image) = find_reference_box(io.output, image).y
    @test top(image) < top(at_head)
    @test top(at_head) - top(image) == Int(before.value.h) + gap_of(io)
end

@testset "an empty vector in the rows cell is the empty list" begin
    table = make_table(make_list(3, texts_of))
    io = print_document(rec, nothing, table, context())
    @test length(texts(io.output)) == 8
    set_cell_value!(getfield(table, :rows), CellVector())
    @test length(texts(io.output)) == 2      # the two names, and no rows
    @test head_of(io) === nothing
    set_cell_value!(getfield(table, :rows), make_list(2, texts_of))
    @test length(texts(io.output)) == 6
    @test head_of(io) isa ListNode
end

@testset "a list is refused where it cannot be drawn lazily" begin
    rows = make_list(3, texts_of)
    content = WidgetTable(; column_headers = Any["name", "value"], rows,
                          column_count = 2, column_policies = Any[Fixed(120), Content])
    @test_throws ErrorException print_document(rec, nothing, content, context())
    weighted = make_table(make_list(3, texts_of); row_policy = Fill)
    @test_throws ErrorException print_document(rec, nothing, weighted, context())
    no_height = with_exact_size(PrinterContext(); width = Cell(Int32(600)))
    @test_throws ErrorException print_document(rec, nothing, make_table(make_list(3, texts_of)), no_height)
end

@testset "the table fills the size it is offered" begin
    io = print_document(rec, nothing, make_table(make_list(1000, texts_of)), context())
    @test Int(io.output.w) == 600
    @test Int(io.output.h) == 300
    @test !is_infinite_canvas(io.output)
    @test Int(io.state.header_height[]) > 0
    @test body_bottom(io) + io.state.pad_y + io.state.bw == 300
end

# A list of `count` rows that reaches both ways from row `at`. A node is built
# from its index alone, so the list starts at its last row as cheaply as at its
# first.
function make_indexed_list(count::Int, cell; at::Int = 1, built = Ref(0))
    function make_node(i, before, after)
        built[] += 1
        node = ListNode(make_widget_table_row(Any[cell(i, c) for c in 1:2]))
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

# A table of such a list, printed at an offset.
function print_table(rows; scroll_y = 0)
    table = make_table(rows; scroll_position = Point2D(0, scroll_y))
    (table, print_document(rec, nothing, table, context()))
end

@testset "the table stops at its first row" begin
    built = Ref(0)
    table, io = print_table(make_indexed_list(10_000_000, texts_of; built))
    first_row = body_top(io)
    @test label_y(io, "row 1") == first_row
    # Up at the first row moves nothing, and answers nothing.
    @test wheel(io, 1) === nothing
    down = wheel(io, -1)
    @test down !== nothing
    apply!(table, down)
    @test first_row - label_y(io, "row 1") > 0
    apply!(table, wheel(io, 1))
    @test label_y(io, "row 1") == first_row
    @test wheel(io, 1) === nothing
    @test built[] < 200
end

@testset "the table stops at its last row" begin
    built = Ref(0)
    count = 10_000_000
    # The head is the last row, and the stored offset puts it at the top: the
    # table draws it at the bottom instead, with the rows before it above it.
    table, io = print_table(make_indexed_list(count, texts_of; at = count, built))
    # The offset walks up from the last row as far as the viewport reaches,
    # which is a screenful of rows. (`texts` below walks fifty more.)
    Int(cells_viewport(io).content.y)
    @test built[] < 30
    last_bottom() = label_y(io, "row $count") + Int(head_of(io).value.h)
    @test last_bottom() == body_bottom(io)
    @test label_y(io, "row $(count - 1)") ==
          label_y(io, "row $count") - Int(head_of(io).value.h) - gap_of(io)
    # Down at the last row moves nothing; up moves at once.
    @test wheel(io, -1) === nothing
    up = wheel(io, 1)
    @test up !== nothing
    apply!(table, up)
    @test last_bottom() > body_bottom(io)
    @test built[] < 200
end

@testset "a stored offset past an end draws the end, and the wheel turns back at once" begin
    # The head is row 10 of 20, and the offset is far above row 1. The rows are
    # more than the viewport holds, so the wheel has rows to move.
    table, io = print_table(make_indexed_list(20, texts_of; at = 10); scroll_y = -10_000)
    first_row = body_top(io)
    @test label_y(io, "row 1") == first_row
    # The first turn moves one whole step, as the second does: no part of it
    # goes to the offset past the end.
    apply!(table, wheel(io, -1))
    after_one = label_y(io, "row 1")
    apply!(table, wheel(io, -1))
    after_two = label_y(io, "row 1")
    @test first_row - after_one > 0
    @test first_row - after_one == after_one - after_two
end

@testset "the header row holds still, and the rows before the head draw only under it" begin
    # The head is the last row, so the table shows the rows before it, at a
    # negative offset.
    table, io = print_table(make_indexed_list(40, texts_of; at = 40))
    in_cells = Set(t[3] for t in texts(cells_region(io)))
    in_header = Set(t[3] for t in texts(header_region(io)))
    @test "row 40" in in_cells
    @test "row 39" in in_cells
    @test "name" ∉ in_cells
    @test in_header == Set(["name", "value"])
    # A turn of the wheel over the header row scrolls the rows, and the header
    # stays where it is.
    name_y = label_y(io, "name")
    row_y = label_y(io, "row 39")
    over_header = read(io, MouseScroll(0, 1, 100, 5; time = 0.0))
    @test over_header !== nothing
    apply!(table, over_header)
    @test label_y(io, "name") == name_y
    @test label_y(io, "row 39") > row_y
end

@testset "a turn to the side stops at the right edge, and the header follows" begin
    wide = WidgetTable(; column_headers = Any["name", "value"],
                       rows = make_indexed_list(10, texts_of), column_count = 2,
                       column_policies = Any[Fixed(400), Fixed(400)])
    io = print_document(rec, nothing, wide, context())
    side(dx) = read(io, MouseScroll(dx, 0, 100, 150; time = 0.0))
    grid_w = Int(grid_of(io).output.w)
    view_w = Int(cells_viewport(io).w)
    @test grid_w > view_w
    header_x() = only(t[1] for t in texts(io.output) if t[3] == "value")
    cell_x() = only(t[1] for t in texts(io.output) if t[3] == "10")
    @test header_x() == cell_x()
    # Left at the left edge moves nothing.
    @test side(1) === nothing
    # Right, turn after turn, stops at the edge and then answers nothing.
    turns = 0
    while (op = side(-1)) !== nothing && turns < 1000
        apply!(wide, op)
        turns += 1
    end
    @test turns < 1000
    @test Int(wide.scroll_position.x[]) == grid_w - view_w
    @test header_x() == cell_x()
end

@testset "a list shorter than the table starts at its top" begin
    table, io = print_table(make_indexed_list(3, texts_of); scroll_y = 400)
    @test label_y(io, "row 1") == body_top(io)
    @test wheel(io, -1) === nothing
    @test wheel(io, 1) === nothing
end

@testset "the table writes the row at the top as it scrolls" begin
    table, io = print_table(make_indexed_list(1000, texts_of))
    step = Int(head_of(io).value.h) + gap_of(io)
    @test table.top_row == 1
    getfield(table, :scroll_position)[] = Point2D(0, 5 * step)
    apply!(table, wheel(io, -1))
    @test table.top_row == 6
    # The top row is the row under the top edge of the cells.
    @test label_y(io, "row 6") <= body_top(io) < label_y(io, "row 7")
end

@testset "far from the head, the table moves the head to the row at the top" begin
    built = Ref(0)
    table, io = print_table(make_indexed_list(10_000_000, texts_of; built))
    step = Int(head_of(io).value.h) + gap_of(io)
    # A turn near the head moves the rows by one step of the wheel.
    near = label_y(io, "row 2")
    apply!(table, wheel(io, -1))
    turn = near - label_y(io, "row 2")
    @test turn > 0
    # Three hundred rows down, a turn moves the head to the row at the top and
    # the offset by the place of that row: every row moves by one turn, as it
    # would with no move of the head.
    getfield(table, :scroll_position)[] = Point2D(0, 300 * step)
    selection = cell_reference(305, 1)
    getfield(table, :selection)[] = selection
    before = label_y(io, "row 305"; limit = 400)    # 304 rows from the head
    op = wheel(io, -1)
    @test op isa CompoundOperation
    moved = [get_wrapped_operation(o) for o in op.operations if o isa ReplaceViewStateOperation]
    @test any(o -> o.reference.head.name == "rows", moved)
    # The selection moves with its row: it names the same row from the new head.
    rebased = only(o for o in op.operations if o isa ReplaceSelectionOperation)
    @test row_of(rebased.path) == 305 - 300
    apply!(table, op)
    @test table.rows.value[1].content == "row 301"
    @test table.top_row == 1
    @test 0 <= Int(table.scroll_position.y[]) < step
    @test label_y(io, "row 305") == before - turn
    @test built[] < 1000
    # Up past the head as far, the head moves back.
    getfield(table, :scroll_position)[] = Point2D(0, -250 * step)
    apply!(table, wheel(io, 1))
    @test table.rows.value[1].content == "row 50"
    @test table.top_row == 1
end

# The graphics of the header row and of row `k`: the band of the header row
# first, then the bands of the light and of the selection; a row has no band of
# its own, so its bands come first.
header_graphics(io) = only(e for e in header_region(io).elements if e isa GraphicsViewport).content.elements
function row_graphics(io, k)
    graphics = only(e for e in cells_region(io).elements if e isa GraphicsViewport).content
    # When the columns are a list, the rows are the first of two canvases, and
    # the rules of the columns the second.
    node = graphics.elements isa ListNode ? graphics.elements : graphics.elements[1].elements
    for _ in 1:(k - 1)
        node = node.next
    end
    node.value.elements
end
span(rect) = (Int(rect.x), Int(rect.w))

@testset "a column is banded in the header row and in every row" begin
    table = make_table(make_list(5, texts_of))
    io = print_document(rec, nothing, table, context())
    edges = io.state.edges[]
    column = (edges[2], edges[3] - edges[2])
    getfield(table, :selection)[] = ConcreteReference(FieldReferenceStep("columns"),
        ConcreteReference(RangeReferenceStep(1, 2), EmptyReference()))
    @test span(header_graphics(io)[3]) == column
    @test all(k -> span(row_graphics(io, k)[2]) == column, 1:3)
    # The header alone is a part of its own: it bands the header row only.
    getfield(table, :selection)[] = ConcreteReference(FieldReferenceStep("column_headers"),
        ConcreteReference(RangeReferenceStep(1, 2), EmptyReference()))
    @test span(header_graphics(io)[3]) == column
    @test all(k -> span(row_graphics(io, k)[2]) == (0, 0), 1:3)
    # The whole table bands every row from edge to edge.
    getfield(table, :selection)[] = EmptyReference()
    @test span(row_graphics(io, 2)[2]) == (0, last(edges) + io.state.bw)
    @test span(header_graphics(io)[3]) == (0, last(edges) + io.state.bw)
    # The pointer over a header lights its column: the point maps to the header,
    # and the light follows the mouse target of the table.
    (hx, hy, _) = only(t for t in texts(io.output) if t[3] == "value")
    getfield(table, :mouse_target)[] = compute_part_at_point(io, hx + 2, hy + 2)
    @test span(header_graphics(io)[2]) == column
    @test span(row_graphics(io, 1)[1]) == column
end

@testset "keys move a selected column, and go between a column and its cells" begin
    table = make_table(make_list(5, texts_of))
    io = print_document(rec, nothing, table, context())
    key(name; kw...) = read(io, KeyDown(name, ModifierKeys(; kw...); time = 0.0))
    column(c) = ConcreteReference(FieldReferenceStep("columns"),
                    ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference()))
    getfield(table, :selection)[] = column(1)
    @test key(:right).path == column(2)
    @test key(:left).path == column(1)
    # Down goes to the cell of the column in the row at the top.
    @test key(:down).path == cell_reference(table.top_row, 1)
    # Ctrl+Space goes from a cell to its column.
    getfield(table, :selection)[] = cell_reference(3, 2)
    @test key(:space; ctrl = true).path == column(2)
end

@testset "a button down reaches the cell under it" begin
    button = WidgetButton("go")
    rows = make_list(3, (i, c) -> (i == 2 && c == 2) ? button : texts_of(i, c))
    io = print_document(rec, nothing, make_table(rows), context())
    (x, y) = place(io, 2, 2)
    op = read(io, MouseDown(:left, x + 4, y + 4, mods; time = 0.0))
    @test op isa ReplaceViewStateOperation
    @test get_wrapped_operation(op).document === button
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
# A table of lists both ways: `rows` rows and `columns` columns, with the head
# column at `at_column`. The header of column 3 is longer than the width of a
# column.
function make_wide_table(rows::Int, columns::Int; at_column = 1, cells = Ref(0))
    header(c) = WidgetLabel(c == 3 ? "a longer header" : "h$(c)")
    WidgetTable(; column_headers = make_list_of(columns, header; at = at_column),
                rows = make_list_of(rows, i -> make_list_of(columns, c -> WidgetLabel("r$(i) c$(c)");
                                                            at = at_column, built = cells)),
                column_count = 0, column_policy = Fixed(60), row_policy = Fixed(16))
end
text_x(io, label) = only(t[1] for t in texts(io.output) if t[3] == label)

@testset "a table whose columns are a list builds what it shows, and each header sits over its column" begin
    cells = Ref(0)
    table = make_wide_table(10_000_000, 1_000_000; cells)
    io = print_document(rec, nothing, table, context())
    @test io isa WidgetTableListIoMap
    Int(cells_viewport(io).content.x); Int(cells_viewport(io).content.y)
    @test cells[] < 100
    @test text_x(io, "h2") == text_x(io, "r1 c2")
    @test text_x(io, "h4") == text_x(io, "r1 c4")
    # The header row is as tall as the header of the head column, one line.
    @test Int(io.state.header_height[]) == 16 + io.state.bw + 2 * io.state.pad_y
    # A column is at least as wide as its header.
    @test text_x(io, "r1 c4") - text_x(io, "r1 c3") ==
          8 * length("a longer header") + 2 * io.state.pad_x + io.state.bw
    @test text_x(io, "r1 c3") - text_x(io, "r1 c2") == 60 + 2 * io.state.pad_x + io.state.bw
    # A press on a header selects its column, and on a cell its row.
    (hx, hy, _) = only(t for t in texts(io.output) if t[3] == "h2")
    column = read(io, MouseClick(:left, hx + 2, hy + 2, mods; time = 0.0))
    @test column.path.head.name == "columns" && column.path.tail.head.start + 1 == 2
    (x, y) = place(io, 2, 4)
    cell = read(io, MouseClick(:left, x + 2, y + 2, alt; time = 0.0))
    @test (row_of(cell.path), column_of(cell.path)) == (2, 4)
    # The band of a selected column: its span in the header row and in a row.
    getfield(table, :selection)[] = column.path
    @test span(header_graphics(io)[3]) == span(row_graphics(io, 1)[2])
    @test span(row_graphics(io, 1)[2])[2] == 60 + 2 * io.state.pad_x + io.state.bw
end

@testset "a table whose columns are a list stops at its first and its last column" begin
    columns = 1_000
    table = make_wide_table(20, columns; at_column = columns)
    io = print_document(rec, nothing, table, context())
    side(dx) = read(io, MouseScroll(dx, 0, 100, 150; time = 0.0))
    # The head column is the last: the table shows it at the right edge, and
    # the header of the last column over it.
    @test side(-1) === nothing
    @test side(1) !== nothing
    @test text_x(io, "h$(columns)") == text_x(io, "r1 c$(columns)")
    first_table = make_wide_table(20, columns)
    first_io = print_document(rec, nothing, first_table, context())
    @test read(first_io, MouseScroll(1, 0, 100, 150; time = 0.0)) === nothing
    # Right, and back to the first column.
    apply!(first_table, read(first_io, MouseScroll(-1, 0, 100, 150; time = 0.0)))
    @test Int(first_table.scroll_position.x[]) > 0
    @test text_x(first_io, "h2") == text_x(first_io, "r1 c2")
end

@testset "far from the head column, the table moves the head column to the column at the left" begin
    table = make_wide_table(5, 100_000)
    io = print_document(rec, nothing, table, context())
    step = 60 + 2 * io.state.pad_x + io.state.bw
    side(dx) = read(io, MouseScroll(dx, 0, 100, 150; time = 0.0))
    # A turn near the head column moves the columns by one step of the wheel.
    near = text_x(io, "h2")
    apply!(table, side(-1))
    turn = near - text_x(io, "h2")
    @test turn > 0
    # Three hundred columns to the side, a turn moves the head column to the
    # column at the left edge, and the offset by the place of that column:
    # every column moves by one turn, as it would with no move of the head.
    # The place of column 301 is where the table put it: the long header of
    # column 3 widens that column.
    left = only(t[1] for t in texts(io.output; limit = 400) if t[3] == "h301") -
           text_x(io, "h1")
    getfield(table, :scroll_position)[] = Point2D(left, 0)
    column = ConcreteReference(FieldReferenceStep("column_headers"),
                 ConcreteReference(RangeReferenceStep(304, 305), EmptyReference()))
    getfield(table, :selection)[] = column
    before = only(t[1] for t in texts(io.output; limit = 400) if t[3] == "h305")
    op = side(-1)
    @test op isa CompoundOperation
    rebased = only(o for o in op.operations if o isa ReplaceSelectionOperation)
    @test rebased.path.tail.head.start + 1 == 305 - 300
    apply!(table, op)
    @test table.column_headers.value.content == "h301"
    @test table.rows.value.value.content == "r1 c301"
    @test 0 <= Int(table.scroll_position.x[]) < step
    @test text_x(io, "h305") == before - turn
    @test text_x(io, "r1 c305") == text_x(io, "h305")
end

@testset "the bands of the light and of the selection follow the rows" begin
    table = make_table(make_list(5, texts_of))
    io = print_document(rec, nothing, table, context())
    # The graphics of a row: its bands first, the light and then the selection.
    function graphics_of(k)
        node = only(e for e in cells_region(io).elements if e isa GraphicsViewport).content.elements
        for _ in 1:(k - 1)
            node = node.next
        end
        node.value
    end
    band_width(k, band) = Int(graphics_of(k).elements[band].w)
    (x, y) = place(io, 3, 1)
    # A move names no part by itself: the point maps to the cell, and the light
    # follows the mouse target of the table.
    @test read(io, MouseMove(x + 2, y + 2, MouseButtons(), mods; time = 0.0)) === nothing
    getfield(table, :mouse_target)[] = compute_part_at_point(io, x + 2, y + 2)
    @test band_width(3, 1) > 0
    @test band_width(2, 1) == 0
    getfield(table, :selection)[] = make_widget_table_row_selection(2)
    @test band_width(2, 2) == band_width(3, 1)
    @test band_width(3, 2) == 0
    getfield(table, :selection)[] = cell_reference(4, 2)
    @test 0 < band_width(4, 2) < band_width(3, 1)
end


# A table of `count` rows with a header of each row, both lists from row `at`,
# a corner, and rows 20 tall.
make_headed_table(count::Int; at::Int = 1, corner = WidgetLabel("corner")) =
    make_table(make_indexed_list(count, texts_of; at);
               row_headers = make_list_of(count, i -> WidgetLabel("#$(i)"); at), corner,
               row_policy = Fixed(20))
corner_region(io) = io.output.elements[end - 3]
# Where the text `label` starts in a printed table.
text_at(io, label) = only((t[1], t[2]) for t in texts(io.output) if t[3] == label)
row_header_reference(k) = ConcreteReference(FieldReferenceStep("row_headers"),
    ConcreteReference(RangeReferenceStep(k - 1, k), EmptyReference()))
corner_reference = ConcreteReference(FieldReferenceStep("corner"), EmptyReference())

@testset "a header of each row sits at its row, and the corner at the top left" begin
    io = print_document(rec, nothing, make_headed_table(1000), context())
    width = Int(io.state.header_width[])
    @test width > 0
    for k in 1:3
        @test text_at(io, "#$(k)")[2] == text_at(io, "row $(k)")[2]
        @test text_at(io, "#$(k)")[1] < width <= text_at(io, "row $(k)")[1]
    end
    # The corner sits in the header row, over the header column.
    @test text_at(io, "corner")[2] == text_at(io, "name")[2]
    @test text_at(io, "corner")[1] < width <= text_at(io, "name")[1]
    # The header row and the cells start where the header column ends, and the
    # table is as wide as it is offered.
    @test Int(header_region(io).x) - Int(corner_region(io).x) == width
    @test Int(cells_region(io).x) - Int(corner_region(io).x) == width
    @test Int(io.output.w) == 600
end

@testset "the header column is as wide as the corner and as the header of the head row" begin
    narrow = print_document(rec, nothing, make_headed_table(1000; corner = WidgetLabel("c")), context())
    wide = print_document(rec, nothing, make_headed_table(1000; corner = WidgetLabel("a wide corner")),
                          context())
    @test Int(wide.state.header_width[]) > Int(narrow.state.header_width[])
    # From row 1000 on, the header of the head row is wider than a short corner.
    late = print_document(rec, nothing, make_headed_table(1000; at = 1000, corner = WidgetLabel("c")),
                          context())
    @test Int(late.state.header_width[]) > Int(narrow.state.header_width[])
end

@testset "a press on a row header selects its row, and a press on the corner the table" begin
    table = make_headed_table(1000)
    io = print_document(rec, nothing, table, context())
    (x, y) = text_at(io, "#2")
    op = read(io, MouseClick(:left, x + 2, y + 2, mods; time = 0.0))
    @test op.path.head.name == "rows" && row_of(op.path) == 2
    (x, y) = text_at(io, "corner")
    @test read(io, MouseClick(:left, x + 2, y + 2, mods; time = 0.0)).path == EmptyReference()
    # The row bands its cells; its header alone is a part of its own and bands
    # none of them.
    getfield(table, :selection)[] = op.path
    @test span(row_graphics(io, 2)[2])[2] > 0
    getfield(table, :selection)[] = row_header_reference(2)
    @test span(row_graphics(io, 2)[2]) == (0, 0)
end

@testset "a reference reaches a row header and the corner, and a point maps back to them" begin
    io = print_document(rec, nothing, make_headed_table(1000), context())
    box_of(reference) = find_reference_box(io.output, map_reference_forward(io.projection, io, reference))
    @test box_of(row_header_reference(3)).y == place(io, 3, 1)[2]
    @test box_of(row_header_reference(3)).x < Int(io.state.header_width[])
    @test box_of(corner_reference).x < Int(io.state.header_width[])
    @test box_of(corner_reference).y < place(io, 1, 1)[2]
    (x, y) = text_at(io, "#3")
    @test compute_part_at_point(io, x + 2, y + 2) == row_header_reference(3)
    (x, y) = text_at(io, "corner")
    @test compute_part_at_point(io, x + 2, y + 2) == corner_reference
end

@testset "far from the head, the row headers move with the rows" begin
    table = make_headed_table(10_000_000)
    io = print_document(rec, nothing, table, context())
    step = Int(head_of(io).value.h) + gap_of(io)
    getfield(table, :scroll_position)[] = Point2D(0, 300 * step)
    op = wheel(io, -1)
    moved = [get_wrapped_operation(o) for o in op.operations if o isa ReplaceViewStateOperation]
    @test any(o -> o.reference.head.name == "row_headers", moved)
    apply!(table, op)
    @test table.rows.value[1].content == "row 301"
    @test table.row_headers.value.content == "#301"
    @test text_at(io, "#305")[2] == text_at(io, "row 305")[2]
end

@testset "row headers on a list need Fixed rows, and a corner needs a header row" begin
    rows() = make_indexed_list(10, texts_of)
    headers() = make_list_of(10, i -> WidgetLabel("#$(i)"))
    @test_throws ErrorException print_document(rec, nothing, make_table(rows(); row_headers = headers()),
                                               context())
    no_header_row = WidgetTable(; column_headers = Any[], rows = rows(), column_count = 2,
                                column_policies = policies, corner = WidgetLabel("c"), row_policy = Fixed(20))
    @test_throws ErrorException print_document(rec, nothing, no_header_row, context())
    @test_throws ErrorException make_table(rows(); row_headers = Any["#1"])
    @test_throws ErrorException WidgetTable(; column_headers = Any["a"], rows = Any[Any["x"]],
                                            column_count = 1, corner = WidgetLabel("c"))
end

@testset "a corner makes a table of a list, also while its rows are an empty vector" begin
    table = make_table(Any[]; corner = WidgetLabel("none yet"), row_policy = Fixed(20))
    io = print_document(rec, nothing, table, context())
    @test io isa WidgetTableListIoMap
    @test Set(t[3] for t in texts(io.output)) == Set(["none yet", "name", "value"])
    @test text_at(io, "none yet")[1] < Int(io.state.header_width[]) <= text_at(io, "name")[1]
end


@testset "a scroll keeps the parts, and a change of the column count builds them again" begin
    table = make_table(make_indexed_list(10_000, texts_of))
    io = print_document(rec, nothing, table, context())
    state = io.state
    apply!(table, wheel(io, -1))
    @test io.state === state
    @test "value" in Set(t[3] for t in texts(io.output))
    # A move of the head writes the rows, and is no change of shape either.
    step = Int(head_of(io).value.h) + gap_of(io)
    getfield(table, :scroll_position)[] = Point2D(0, 300 * step)
    apply!(table, wheel(io, -1))
    @test table.top_row == 1 && table.rows.value[1].content != "row 1"
    @test io.state === state
    getfield(table, :column_count)[] = 1
    @test io.state !== state
    found = Set(t[3] for t in texts(io.output))
    @test "value" ∉ found
    @test "name" in found
end


@testset "a press and a key reach a header, as they reach a cell" begin
    field = WidgetText("abc")
    table = WidgetTable(; column_headers = Any[WidgetLabel("name"), field], rows = make_list(5, texts_of),
                        column_count = 2, column_policies = policies)
    io = print_document(rec, nothing, table, context())
    (x, y) = text_at(io, "abc")
    op = read(io, MouseClick(:left, x + 2, y + 2, mods; time = 0.0))
    @test op isa ReplaceSelectionOperation
    steps = get_reference_steps(strip_reference_types(op.path))
    @test steps[1:3] == [FieldReferenceStep("column_headers"), RangeReferenceStep(1, 2),
                         FieldReferenceStep("content")]
    # The selection is in the field, so a key goes to it through the table.
    set_selection!(table, op.path)
    key = read(io, KeyPress('X', "X", mods; time = 0.0))
    @test key isa ReplaceStringRangeOperation
    @test get_reference_steps(strip_reference_types(key.reference))[1:2] ==
          [FieldReferenceStep("column_headers"), RangeReferenceStep(1, 2)]
    # A header that declines a press selects its column, and an Alt+press selects
    # the header itself.
    (x, y) = text_at(io, "name")
    path = read(io, MouseClick(:left, x + 2, y + 2, mods; time = 0.0)).path
    @test strip_reference_types(path) == ConcreteReference(FieldReferenceStep("columns"),
        ConcreteReference(RangeReferenceStep(0, 1), EmptyReference()))
    path = read(io, MouseClick(:left, x + 2, y + 2, ModifierKeys(alt = true); time = 0.0)).path
    @test strip_reference_types(path) == ConcreteReference(FieldReferenceStep("column_headers"),
        ConcreteReference(RangeReferenceStep(0, 1), EmptyReference()))
end

@testset "a drag of the right edge of a header sets the width of its column" begin
    table = WidgetTable(; column_headers = Any[WidgetLabel("name"), WidgetLabel("age")],
                        rows = make_list(5, texts_of), column_count = 2, column_policies = policies)
    io = print_document(rec, nothing, table, context())
    (x1, y1) = text_at(io, "name")
    (x2, _) = text_at(io, "age")
    # The right edge of the first column is the rule before the second, a cell
    # padding and a rule before the text of the second header.
    edge = x2 - io.state.pad_x - io.state.bw
    start = read(io, MouseDown(:left, edge, y1 + 2; time = 0.0))
    @test start isa CompoundOperation && any(op -> op isa StartDragOperation, start.operations)
    apply!(table, start)
    @test table.column_drag.column == 1 && table.column_drag.width == 120
    # A move gives the column the width at the press plus the move.
    move = read(io, DragMove(edge + 30, y1; time = 0.1))
    @test get_wrapped_operation(move) isa SetTableColumnWidthOperation
    apply!(table, move)
    @test table.column_policies[1] == Fixed(150)
    @test text_at(io, "age")[1] == x2 + 30
    # The width does not go under the narrowest width.
    apply!(table, read(io, DragMove(edge - 500, y1; time = 0.2)))
    @test table.column_policies[1] == Fixed(24)
    # A cancel puts back the width at the press, and ends the drag.
    apply!(table, read(io, DragCancel(; time = 0.3)))
    @test table.column_policies[1] == Fixed(120)
    @test table.column_drag === nothing
    @test text_at(io, "age")[1] == x2
    # A press on a header away from its edge starts no drag.
    away = read(io, MouseDown(:left, x1 + 10, y1 + 2; time = 0.4))
    @test !(away isa CompoundOperation && any(op -> op isa StartDragOperation, away.operations))
end

@testset "the right edge of a header lights under the pointer, and a rest there says what a drag does" begin
    table = WidgetTable(; column_headers = Any[WidgetLabel("name"), WidgetLabel("age")],
                        rows = make_list(5, texts_of), column_count = 2, column_policies = policies)
    io = print_document(rec, nothing, table, context())
    (x1, y1) = text_at(io, "name")
    (x2, _) = text_at(io, "age")
    edge = x2 - io.state.pad_x - io.state.bw
    point(x, y) = ConcreteReference(PointReferenceStep(x, y), EmptyReference())
    # A point on the edge maps to the width of the column, and a point beside it
    # to the header.
    edge_ref = ConcreteReference(FieldReferenceStep("column_policies"),
                                 ConcreteReference(RangeReferenceStep(0, 1), EmptyReference()))
    @test map_reference_backward(io.projection, io, point(edge, y1 + 2)) == edge_ref
    @test map_reference_backward(io.projection, io, point(x1 + 10, y1 + 2)) ==
          ConcreteReference(FieldReferenceStep("column_headers"),
                            ConcreteReference(RangeReferenceStep(0, 1), EmptyReference()))
    # The edge that is the mouse target lights: a bar over its rule.
    light = last(header_graphics(io))
    @test Int(light.w[]) == 0
    getfield(table, :mouse_target)[] = edge_ref
    @test Int(light.w[]) == 3 && Int(light.h[]) > 0
    @test abs(Int(light.x[]) + 1 - (Int(io.state.edges[][2]) + io.state.bw ÷ 2)) <= 1
    getfield(table, :mouse_target)[] = nothing
    @test Int(light.w[]) == 0
    # A rest on the edge says what a drag there does.
    tooltip = read(io, MouseDwell(edge, y1 + 2; time = 0.0))
    @test get_wrapped_operation(tooltip) isa OpenTooltipOperation
    layers = get_wrapped_operation(tooltip).layers
    @test any(layer -> last(layer) isa PrimitiveString && last(layer).value == "Drag to set the width", layers)
end

@testset "a table whose columns are a list takes the width of a column from its owner" begin
    widths = make_list_of(1_000, c -> c == 2 ? Fixed(100) : nothing)
    table = make_wide_table(100, 1_000)
    table.column_policies = widths
    io = print_document(rec, nothing, table, context())
    hgap = 2 * io.state.pad_x + io.state.bw
    # The width that the owner gives wins; the other columns are as before.
    @test text_x(io, "r1 c3") - text_x(io, "r1 c2") == 100 + hgap
    @test text_x(io, "r1 c2") - text_x(io, "r1 c1") == 60 + hgap
    # A drag of the edge of the second column answers its width, counted from
    # the head column, and the owner keeps it.
    (_, hy, _) = only(t for t in texts(io.output) if t[3] == "h2")
    edge = text_x(io, "r1 c3") - io.state.pad_x - io.state.bw
    apply!(table, read(io, MouseDown(:left, edge, hy + 2; time = 0.0)))
    @test table.column_drag.column == 2 && table.column_drag.width == 100
    move = get_wrapped_operation(read(io, DragMove(edge + 20, hy; time = 0.1)))
    @test move isa SetTableColumnWidthOperation && move.column == 2 && move.width == 120
end

# The rects that a graphics tree draws in `color`, through viewports and down a
# list for at most `limit` nodes in each direction.
function rects_in(node, color, found = Ref(0); limit = 50)
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            for link in (:next, :prev)
                n = link === :next ? elements : elements.prev; seen = 0
                while n !== nothing && seen < limit
                    rects_in(n.value, color, found; limit); n = getproperty(n, link); seen += 1
                end
            end
        else
            foreach(element -> rects_in(element, color, found; limit), elements)
        end
    elseif node isa GraphicsViewport
        rects_in(node.content, color, found; limit)
    elseif node isa GraphicsRect
        unwrap_cell(node.color) == color && (found[] += 1)
    end
    found[]
end

@testset "an open cell takes Enter, Tab and Escape, and a failed commit marks it, in $form" for
        form in ("a table of a list", "a table of a vector")
    rows = form == "a table of a list" ? make_list(5, texts_of) :
           Any[Any[texts_of(i, 1), texts_of(i, 2)] for i in 1:5]
    table = make_table(rows; open_cells = Any[(row = 2, column = 1, reason = nothing)])
    io = print_document(rec, nothing, table, context())
    key(name; kw...) = read(io, KeyDown(name, ModifierKeys(; kw...); time = 0.0))
    getfield(table, :selection)[] = cell_reference(2, 1)
    commit = key(:return)
    @test commit isa CommitTableCellOperation && commit.table === table
    @test (commit.row, commit.column, commit.key) == (2, 1, :return)
    @test key(:tab).key === :tab && key(:tab; shift = true).key === :backtab
    drop = key(:escape)
    @test drop isa DropTableCellOperation && (drop.row, drop.column) == (2, 1)
    # A cell that is not open gives the keys to the table and to the cell as before.
    getfield(table, :selection)[] = cell_reference(3, 1)
    @test !(key(:return) isa CommitTableCellOperation)
    @test key(:escape) === nothing
    # On a whole cell that is not open, F2 and a typed character that the cell
    # takes no key for open it, which the owner converts; a key with Ctrl, and a
    # key in the open cell, open nothing.
    edit = key(:f2)
    @test edit isa EditTableCellOperation && edit.table === table
    @test (edit.row, edit.column, edit.text) == (3, 1, nothing)
    typed = read(io, KeyPress('x'; time = 0.0))
    @test typed isa EditTableCellOperation && typed.text == "x"
    @test !(read(io, KeyPress('x', "x", ModifierKeys(ctrl = true); time = 0.0)) isa EditTableCellOperation)
    @test !(key(:f2; ctrl = true) isa EditTableCellOperation)
    getfield(table, :selection)[] = cell_reference(2, 1)
    @test !(key(:f2) isa EditTableCellOperation)
    # A table that no owner opens, the default, gives F2 to the parts around it.
    plain = make_table(form == "a table of a list" ? make_list(5, texts_of) :
                       Any[Any[texts_of(i, 1), texts_of(i, 2)] for i in 1:5])
    plain_io = print_document(rec, nothing, plain, context())
    getfield(plain, :selection)[] = cell_reference(3, 1)
    @test read(plain_io, KeyDown(:f2, ModifierKeys(); time = 0.0)) === nothing
    @test read(plain_io, KeyPress('x'; time = 0.0)) === nothing
    # A failed commit marks the cell with a frame of four bars, which each region
    # of a table of a vector draws behind its pane, and a rest on it shows the
    # reason.
    marks = rects_in(io.output, get_theme_defaults(WidgetTheme).destructive)
    getfield(table, :open_cells)[] = Any[(row = 2, column = 1, reason = "not a number")]
    added = rects_in(io.output, get_theme_defaults(WidgetTheme).destructive) - marks
    @test added > 0 && added % 4 == 0
    (x, y) = place(io, 2, 1)
    tooltip = read(io, MouseDwell(x + 2, y + 2; time = 0.0))
    @test get_wrapped_operation(tooltip) isa OpenTooltipOperation
    layers = get_wrapped_operation(tooltip).layers
    @test any(layer -> last(layer) isa PrimitiveString && last(layer).value == "not a number", layers)
    getfield(table, :open_cells)[] = Any[]
    @test rects_in(io.output, get_theme_defaults(WidgetTheme).destructive) == marks
end

end
end
