# A vertical, a horizontal and a grid layout whose children are a list.
#
# The cost of such a layout is the children a viewport shows, so the first test
# counts children built; the rest read where a child landed on the screen, where
# a pane stops, and what a press answered.

"""
    test_layout_list()

A `VerticalLayout` and a `HorizontalLayout` of a `ListNode` draw the children
that a pane shows, place each after its neighbour, stop the pane at the ends of
the list in their own direction, and root a press at `children[k]`, counted
from the head. A `GridLayout` of a `ListNode` of rows does the same with its
rows, places the cells of a row in its columns, and roots a press at
`children[k][c]`.
"""
function test_layout_list()
@testset "a layout whose children are a list" begin

det = FixedMeasure(8, 12, 4, 0)
rec = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch)))
context() = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(300)))
alt = ModifierKeys(alt = true)

# A list of `count` labels that reaches both ways from child `at`. A node is
# built from its index alone, so the list starts at its last child as cheaply as
# at its first.
function make_labels(count::Int; at::Int = 1, built = Ref(0))
    function make_node(i, before, after)
        built[] += 1
        node = ListNode(WidgetLabel("child " * string(i)))
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

# Every text a canvas drew, as (x, y, text), through viewports and along a list
# for at most `limit` nodes in each direction.
function texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[]; limit = 40)
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
viewport(io) = only(e for e in io.output.elements if e isa GraphicsViewport)
place(io, label) = only((t[1], t[2]) for t in texts(viewport(io)) if t[3] == label)
read(io, g) = begin
    change = read_intent(rec, nothing, Intent(g, nothing), io)
    change isa Intent ? change.operation : change
end
wheel(io, dx, dy) = read(io, MouseScroll(dx, dy, 50, 50; time = 0.0))
apply!(pane, op) = (getfield(pane, :scroll_position)[] = get_wrapped_operation(op).value)
column(list; kw...) = VerticalLayout(list; child_width = Fixed(200), gap = 4, kw...)
row(list; kw...) = HorizontalLayout(list; child_height = Fixed(40), gap = 4, kw...)

@testset "a column of ten million children builds a screenful" begin
    built = Ref(0)
    pane = WidgetScrollPane(column(make_labels(10_000_000; built)); size = Point2D(300, 200))
    io = print_document(rec, nothing, pane, context())
    @test io.content_iomap isa LayoutListIoMap
    Int(viewport(io).content.y)             # the pane places the list
    @test built[] < 30
    (x1, y1) = place(io, "child 1")
    (x2, y2) = place(io, "child 2")
    @test x2 == x1
    @test y2 > y1
    (_, y3) = place(io, "child 3")
    @test y3 - y2 == y2 - y1                # one extent and one gap each
    @test built[] < 100                     # `texts` walks forty more
end

@testset "a column stops the pane at its first and its last child" begin
    count = 10_000_000
    pane = WidgetScrollPane(column(make_labels(count; at = count)); size = Point2D(300, 200))
    io = print_document(rec, nothing, pane, context())
    # The head is the last child, and the pane shows it at the bottom: the
    # bottom of its canvas meets the bottom of the viewport.
    body = viewport(io)
    head = io.content_iomap.output.elements.value
    @test Int(body.content.y) + Int(head.y) + Int(head.h) == Int(body.h)
    @test place(io, "child $(count - 1)")[2] < place(io, "child $count")[2]
    @test wheel(io, 0, -1) === nothing                           # down: nothing
    @test wheel(io, 0, 1) !== nothing                            # up: at once
    top = WidgetScrollPane(column(make_labels(count)); size = Point2D(300, 200))
    top_io = print_document(rec, nothing, top, context())
    @test wheel(top_io, 0, 1) === nothing                        # up at the first child
end

@testset "a row stops the pane at its ends to the side" begin
    count = 1_000_000
    pane = WidgetScrollPane(row(make_labels(count; at = count)); size = Point2D(300, 100))
    io = print_document(rec, nothing, pane, context())
    (last_x, _) = place(io, "child $count")
    (before_x, before_y) = place(io, "child $(count - 1)")
    @test before_x < last_x
    @test place(io, "child $count")[2] == before_y              # one row
    @test wheel(io, -1, 0) === nothing                          # right at the last child: nothing
    left = wheel(io, 1, 0)
    @test left !== nothing                                      # left: at once
    apply!(pane, left)
    @test place(io, "child $count")[1] > last_x
    start = WidgetScrollPane(row(make_labels(count)); size = Point2D(300, 100))
    start_io = print_document(rec, nothing, start, context())
    @test wheel(start_io, 1, 0) === nothing                     # left at the first child
end

@testset "a press is rooted at the child's index from the head" begin
    pane = WidgetScrollPane(column(make_labels(20; at = 10)); size = Point2D(300, 200),
                            scroll_position = Point2D(0, -60))
    io = print_document(rec, nothing, pane, context())
    (x, y) = place(io, "child 9")
    op = read(io, MouseClick(:left, x + 2, y + 2, alt; time = 0.0))
    @test op isa ReplaceSelectionOperation
    step = op.path.tail.tail.head               # .content.children[k]
    @test step isa RangeReferenceStep
    @test step.start == -1                      # child 9 is one before the head: k = 0
end

# A list of `count` rows of three labels each, reaching both ways from row `at`.
function make_rows(count::Int; at::Int = 1, built = Ref(0))
    function make_node(i, before, after)
        built[] += 1
        node = ListNode(Any[WidgetLabel("r$(i) c$(c)") for c in 1:3])
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
grid(rows) = GridLayout(rows, 3; column_policies = Any[Fixed(90), Fixed(90), Fixed(90)],
                        horizontal_gap = 6, vertical_gap = 4)

@testset "a grid of ten million rows builds a screenful and places cells in columns" begin
    built = Ref(0)
    pane = WidgetScrollPane(grid(make_rows(10_000_000; built)); size = Point2D(400, 200))
    io = print_document(rec, nothing, pane, context())
    @test io.content_iomap isa GridLayoutListIoMap
    Int(viewport(io).content.y)
    @test built[] < 30
    (x11, y11) = place(io, "r1 c1")
    (x12, y12) = place(io, "r1 c2")
    (x21, y21) = place(io, "r2 c1")
    @test y12 == y11
    @test x12 - x11 == 90 + 6                  # a column and a gap
    @test x21 == x11
    @test y21 > y11
    @test Int(io.content_iomap.col_x[2][]) == 96
    @test built[] < 100
end

@testset "a grid stops the pane at its last row" begin
    count = 1_000_000
    pane = WidgetScrollPane(grid(make_rows(count; at = count)); size = Point2D(400, 200))
    io = print_document(rec, nothing, pane, context())
    body = viewport(io)
    head = io.content_iomap.output.elements.value
    @test Int(body.content.y) + Int(head.y) + Int(head.h) == Int(body.h)
    @test wheel(io, 0, -1) === nothing
    @test wheel(io, 0, 1) !== nothing
end

@testset "a press in a grid is rooted at the cell's row from the head and its column" begin
    pane = WidgetScrollPane(grid(make_rows(20; at = 10)); size = Point2D(400, 200),
                            scroll_position = Point2D(0, -40))
    io = print_document(rec, nothing, pane, context())
    (x, y) = place(io, "r9 c2")
    op = read(io, MouseClick(:left, x + 2, y + 2, alt; time = 0.0))
    @test op isa ReplaceSelectionOperation
    rows_step = op.path.tail.tail.head          # .content.children[k][c]
    column_step = op.path.tail.tail.tail.head
    @test rows_step isa RangeReferenceStep && rows_step.start == -1
    @test column_step isa RangeReferenceStep && column_step.start == 1
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
# A grid of `rows` rows and `columns` columns, both lists, with the head row at
# `at_row` and the head column at `at_column`.
function make_grid_of_lists(rows::Int, columns::Int; at_row = 1, at_column = 1, cells = Ref(0))
    row_of(i) = make_list_of(columns, c -> WidgetLabel("r$(i) c$(c)"); at = at_column, built = cells)
    GridLayout(make_list_of(rows, row_of; at = at_row), 1;
               column_policies = make_list_of(columns, c -> Fixed(90); at = at_column),
               row_policy = Fixed(20), horizontal_gap = 6, vertical_gap = 4)
end

@testset "a grid lazy both ways builds a screenful, and places each cell in its column" begin
    cells = Ref(0)
    pane = WidgetScrollPane(make_grid_of_lists(10_000_000, 1_000_000; cells); size = Point2D(400, 200))
    io = print_document(rec, nothing, pane, context())
    @test io.content_iomap isa GridLayoutListIoMap
    Int(viewport(io).content.y); Int(viewport(io).content.x)   # the pane places both lists
    @test cells[] < 100
    (x11, y11) = place(io, "r1 c1")
    (x12, y12) = place(io, "r1 c2")
    (x21, y21) = place(io, "r2 c1")
    @test (x12 - x11, y12) == (90 + 6, y11)
    @test (x21, y21 - y11) == (x11, 20 + 4)
    cell = find_grid_list_cell(io.content_iomap, 2, 3)
    @test cell !== nothing && cell[3].output isa GraphicsCanvas
end

@testset "a grid lazy both ways stops the pane at its last column, and roots a press at its cell" begin
    columns = 1_000_000
    # The head column is the last, and the offset puts it at the left: the pane
    # draws it at the right instead.
    pane = WidgetScrollPane(make_grid_of_lists(100, columns; at_column = columns); size = Point2D(400, 200))
    io = print_document(rec, nothing, pane, context())
    body = viewport(io)
    last = get_grid_list_column_head(io.content_iomap).value
    @test Int(body.content.x) + Int(last.x) + Int(last.w) == Int(body.w)
    @test wheel(io, -1, 0) === nothing                           # right: nothing
    @test wheel(io, 1, 0) !== nothing                            # left: at once
    (x, y) = place(io, "r2 c$(columns - 1)")
    op = read(io, MouseClick(:left, x + 2, y + 2, alt; time = 0.0))
    @test op isa ReplaceSelectionOperation
    rows_step = op.path.tail.tail.head          # .content.children[k][c]
    column_step = op.path.tail.tail.tail.head
    @test rows_step isa RangeReferenceStep && rows_step.start == 1       # row 2
    @test column_step isa RangeReferenceStep && column_step.start == -1  # one before the head: 0
end

@testset "a grid lazy both ways needs Fixed columns and Fixed rows" begin
    rows = make_list_of(3, i -> make_list_of(3, c -> WidgetLabel("x")))
    @test_throws ErrorException print_document(rec, nothing,
        WidgetScrollPane(GridLayout(rows, 1; column_policies = make_list_of(3, c -> Fixed(90)),
                                    row_policy = Content); size = Point2D(400, 200)), context())
    content = WidgetScrollPane(GridLayout(make_list_of(3, i -> make_list_of(3, c -> WidgetLabel("x"))), 1;
                                          column_policies = make_list_of(3, c -> Content),
                                          row_policy = Fixed(20)); size = Point2D(400, 200))
    io = print_document(rec, nothing, content, context())
    @test_throws ErrorException Int(viewport(io).content.x)
end

@testset "a grid of a list needs a width for every column and no weight on its rows" begin
    @test_throws ErrorException print_document(rec, nothing,
        GridLayout(make_rows(3), 3; column_policies = Any[Fixed(90), Content, Fixed(90)]), context())
    @test_throws ErrorException print_document(rec, nothing,
        GridLayout(make_rows(3), 3; column_policy = Fixed(90), row_policy = Fill), context())
end

@testset "a list needs an extent across and no weight along" begin
    @test_throws ErrorException print_document(rec, nothing, VerticalLayout(make_labels(3)), PrinterContext())
    @test_throws ErrorException print_document(rec, nothing,
        VerticalLayout(make_labels(3); child_width = Fixed(100), child_height = Fill), context())
end

end
end
