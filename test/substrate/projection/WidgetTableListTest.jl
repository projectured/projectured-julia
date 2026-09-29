# A table whose rows are a list.
#
# The cost of such a table is the rows a viewport shows, so the first test
# counts rows built and not pixels; the rest read where a cell landed, what a
# click answered, and what a reference maps to, against the eager table over
# the same data — the one test that says the two forms did not fork.

using ProjecturedKernel.CellModule: Cell, Computation, set_cell_computation!,
                                    set_cell_value!
using ProjecturedCollection.CollectionModule: ListNode
using ProjecturedWidget.WidgetModule: _wtl_row_node

# A weighted column with no minimum is at least as wide as its header. Wide, each
# column is its header and an equal share of what is left; narrow, each keeps
# its header, and the table is wider than the offer, which is what a pane
# scrolls.
function test_widget_table_list_header_floor()
@testset "a weighted column is at least as wide as its header" begin
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch)))
    grow = SizePolicy(nothing, nothing, nothing, 1.0)
    head = ListNode(make_widget_table_row(Any["a", "b"]))
    table = WidgetTable(; column_headers = Any["id", "a much longer header"],
                        rows = head, column_count = 2, column_policies = Any[grow, grow])
    function print_at(width)
        ctx = with_exact_size(PrinterContext(); width = Cell(Int32(width)),
                              height = Cell(Int32(300)))
        print_document(rec, nothing, table, ctx)
    end
    wide = print_at(900)
    @test Int(wide.output.w[]) == 900
    widths = wide.state.widths[]
    # The same share on top of each header, less a pixel of rounding.
    @test abs((widths[2] - widths[1]) - 8 * (length("a much longer header") - length("id"))) <= 1
    narrow = print_at(100)
    widths = narrow.state.widths[]
    @test widths == [8 * length("id"), 8 * length("a much longer header")]
    @test Int(narrow.output.w[]) > 100
end
end

function test_widget_table_list()
@testset "a table whose rows are a list" begin

det = FixedMeasure(8, 12, 4, 0)
rec = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch)))
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
body_of(io) = io.output.elements[end]
read(io, g) = begin
    change = read_intent(rec, nothing, Intent(g, nothing), io)
    change isa Intent ? change.operation : change
end
row_of(path) = path.tail.head.start + 1
column_of(path) = path.tail.tail.head.start + 1

@testset "a list of 100,000 rows builds a handful" begin
    built = Ref(0)
    io = print_document(rec, nothing, make_table(make_list(100_000, texts_of; built)), context())
    @test io isa WidgetTableListIoMap
    body = body_of(io)
    @test body.elements isa ListNode
    # Printing built the head and nothing else; following twenty links builds
    # twenty more, and the other 99,979 are never built.
    @test built[] == 1
    node = body.elements; seen = 0
    while node !== nothing && seen < 20
        seen += 1; node = node.next
    end
    @test seen == 20
    @test built[] == 21
    @test built[] < 1000
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

@testset "a widget in a list cell draws, and a click on it reaches it" begin
    box = WidgetCheckbox("abc")
    rows = make_list(3, (i, c) -> (i == 2 && c == 1) ? box : texts_of(i, c))
    io = print_document(rec, nothing, make_table(rows), context())
    st = io.state
    # The box is drawn: row two is built once walked to, and its first cell's
    # canvas has an extent.
    @test _wtl_row_node(st, 2) !== nothing
    box_canvas = st.built[2][2][1][3].output
    @test box_canvas isa GraphicsCanvas
    @test Int(box_canvas.w) > 0 && Int(box_canvas.h) > 0
    # Row two sits under row one; its cell one starts after the padding.
    x = Int(st.columns[][1]) + st.bw + st.pad_x + 2
    row_height = st.bw + st.pad_y + 16 + st.pad_y
    y = Int(st.header_height[]) + row_height + st.bw + st.pad_y + 2
    op = read(io, MousePress(:left, x, y, alt; time = 0.0))
    @test op isa ReplaceSelectionOperation
    @test op.path.head.name == "rows"
    @test row_of(op.path) == 2
    @test column_of(op.path) == 1
    # A plain click on the box goes to the checkbox, and what it answers —
    # a toggle of its own document — comes back as it is.
    plain = read(io, MousePress(:left, x + 4, y + 4, mods; time = 0.0))
    @test plain isa ReplaceReferencedValueOperation
    @test plain.document === box
    # A plain click on a label, which declines it, selects the row.
    on_text = read(io, MousePress(:left, Int(st.columns[][2]) + st.bw + st.pad_x + 2, y, mods; time = 0.0))
    @test on_text isa ReplaceSelectionOperation
    @test on_text.path.head.name == "rows"
    @test row_of(on_text.path) == 2
    @test on_text.path.tail.tail isa EmptyReference
end

@testset "rows of different heights, and the row at a coordinate" begin
    long = "a value that is far too wide for one hundred and twenty pixels"
    rows = make_list(3, (i, c) -> (i == 2 && c == 1) ? long : texts_of(i, c))
    io = print_document(rec, nothing, make_table(rows; cell_policy = :wrap), context())
    st = io.state
    body = body_of(io)
    first = body.elements.value
    second = body.elements.next.value
    third = body.elements.next.next.value
    @test Int(second.h) > Int(first.h)
    @test Int(second.y) == Int(first.y) + Int(first.h)
    @test Int(third.y) == Int(second.y) + Int(second.h)
    # A click near the bottom of row two names row two, not row three.
    x = Int(st.columns[][2]) + st.bw + st.pad_x + 2
    y = Int(st.header_height[]) + Int(second.y) + Int(second.h) - 2
    op = read(io, MousePress(:left, x, y, alt; time = 0.0))
    @test op isa ReplaceSelectionOperation
    @test row_of(op.path) == 2
    @test column_of(op.path) == 2
end

@testset "a row before the head has an index of zero, and a reference reaches it" begin
    head = make_list(3, texts_of; from = 2)
    pushfirst!(head, make_widget_table_row(Any["row 1", "10"]))
    io = print_document(rec, nothing, make_table(head), context())
    st = io.state
    body = body_of(io)
    before = body.elements.prev
    @test before !== nothing
    @test Int(before.value.y) == -Int(before.value.h)
    @test any(t -> t[3] == "row 1", texts(io.output))
    # `rows[0][1]` is the cell before the head; its image sits above the head's.
    reference = ConcreteReference(FieldReferenceStep("rows"),
                    ConcreteReference(RangeReferenceStep(-1, 0),
                        ConcreteReference(RangeReferenceStep(0, 1), EmptyReference())))
    image = map_reference_forward(io.projection, io, reference)
    at_head = map_reference_forward(io.projection, io,
                    ConcreteReference(FieldReferenceStep("rows"),
                        ConcreteReference(RangeReferenceStep(0, 1),
                            ConcreteReference(RangeReferenceStep(0, 1), EmptyReference()))))
    @test image isa PointReferenceStep
    @test at_head isa PointReferenceStep
    @test Int(image.y[]) < Int(at_head.y[])
end

@testset "an empty vector in the rows cell is the empty list" begin
    table = make_table(make_list(3, texts_of))
    io = print_document(rec, nothing, table, context())
    @test length(texts(io.output)) == 8
    set_cell_value!(getfield(table, :rows), CellVector())
    @test length(texts(io.output)) == 2      # the two names, and no rows
    @test !is_infinite_canvas(io.output)
    set_cell_value!(getfield(table, :rows), make_list(2, texts_of))
    @test length(texts(io.output)) == 6
    @test is_infinite_canvas(io.output)
end

@testset "a list is refused where it cannot be drawn lazily" begin
    rows = make_list(3, texts_of)
    content = WidgetTable(; column_headers = Any["name", "value"], rows,
                          column_count = 2, column_policies = Any[Fixed(120), Content])
    @test_throws ErrorException print_document(rec, nothing, content, context())
    weighted = make_table(make_list(3, texts_of); row_policy = Fill)
    @test_throws ErrorException print_document(rec, nothing, weighted, context())
end

@testset "a table over a list holds its header still" begin
    io = print_document(rec, nothing, make_table(make_list(1000, texts_of)), context())
    @test is_infinite_canvas(io.output)
    frozen = get_frozen_extent(io)[]
    @test frozen[2] == Int(io.state.header_height[])
    @test frozen[2] > 0
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

# A pane over a table of such a list, printed, with what a test reads of it:
# the body region, which is the first of the four viewports of a frozen
# header; the list state; and the screen y of the text of a row.
function print_pane(rows; scroll_y = 0)
    pane = WidgetScrollPane(make_table(rows); size = Point2D(600, 300),
                            scroll_position = Point2D(0, scroll_y))
    io = print_document(rec, nothing, pane, context())
    (; pane, io, state = io.content_iomap.state,
       body = first(e for e in io.output.elements if e isa GraphicsViewport))
end
label_y(printed, label) = only(t[2] for t in texts(printed.body) if t[3] == label)
# The text of a row starts under the border and the padding of its cell.
text_inset(printed) = printed.state.bw + printed.state.pad_y
row_height(printed) = Int(body_of(printed.io.content_iomap).elements.value.h)
body_top(printed) = Int(printed.body.y)
body_bottom(printed) = Int(printed.body.y) + Int(printed.body.h)
wheel(printed, dy) = read(printed.io, MouseScroll(0, dy, 100, 150; time = 0.0))
apply!(printed, op) = (getfield(printed.pane, :scroll_position)[] = get_wrapped_operation(op).value)

@testset "a pane over a list stops at its first row" begin
    built = Ref(0)
    printed = print_pane(make_indexed_list(10_000_000, texts_of; built))
    first_row = body_top(printed) + text_inset(printed)
    @test label_y(printed, "row 1") == first_row
    # Up at the first row moves nothing, and answers nothing.
    @test wheel(printed, 1) === nothing
    down = wheel(printed, -1)
    @test down !== nothing
    apply!(printed, down)
    step = first_row - label_y(printed, "row 1")
    @test step > 0
    back = wheel(printed, 1)
    apply!(printed, back)
    @test label_y(printed, "row 1") == first_row
    @test wheel(printed, 1) === nothing
    @test built[] < 200
end

@testset "a pane over a list stops at its last row" begin
    built = Ref(0)
    count = 10_000_000
    # The head is the last row, and the stored offset puts it at the top: the
    # pane draws it at the bottom instead, with the rows before it above it.
    printed = print_pane(make_indexed_list(count, texts_of; at = count, built))
    # The offset walks up from the last row as far as the viewport reaches,
    # which is a screenful of rows. (`texts` below walks fifty more.)
    Int(printed.body.content.y)
    @test built[] < 30
    last_bottom() = label_y(printed, "row $count") - text_inset(printed) + row_height(printed)
    @test last_bottom() == body_bottom(printed)
    @test label_y(printed, "row $(count - 1)") == label_y(printed, "row $count") - row_height(printed)
    # Down at the last row moves nothing; up moves at once.
    @test wheel(printed, -1) === nothing
    up = wheel(printed, 1)
    @test up !== nothing
    apply!(printed, up)
    @test last_bottom() > body_bottom(printed)
    @test built[] < 200
end

@testset "a stored offset past an end draws the end, and the wheel turns back at once" begin
    # The head is row 5 of 10, and the offset is far above row 1.
    printed = print_pane(make_indexed_list(10, texts_of; at = 5); scroll_y = -10_000)
    first_row = body_top(printed) + text_inset(printed)
    @test label_y(printed, "row 1") == first_row
    # The first turn moves one whole step, as the second does: no part of it
    # goes to the offset past the end.
    apply!(printed, wheel(printed, -1))
    after_one = label_y(printed, "row 1")
    apply!(printed, wheel(printed, -1))
    after_two = label_y(printed, "row 1")
    @test first_row - after_one > 0
    @test first_row - after_one == after_one - after_two
end

@testset "rows before the head draw in the body, and the header only in its strip" begin
    # The head is the last row, so the pane shows the rows before it, at a
    # negative offset, and its offset is negative too.
    printed = print_pane(make_indexed_list(40, texts_of; at = 40))
    regions = [e for e in printed.io.output.elements if e isa GraphicsViewport]
    strip = regions[2]                      # the vertical axis held
    in_body = Set(t[3] for t in texts(printed.body))
    in_strip = Set(t[3] for t in texts(strip))
    @test "row 40" in in_body
    @test "row 39" in in_body
    @test "name" ∉ in_body
    @test "value" ∉ in_body
    @test in_strip == Set(["name", "value"])
end

@testset "a list shorter than the pane starts at its top" begin
    printed = print_pane(make_indexed_list(3, texts_of); scroll_y = 400)
    @test label_y(printed, "row 1") == body_top(printed) + text_inset(printed)
    @test wheel(printed, -1) === nothing
    @test wheel(printed, 1) === nothing
end

end
end
