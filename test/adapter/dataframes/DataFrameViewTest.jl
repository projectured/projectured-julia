# Fragment of `ProjecturedDataFramesTest` — a data frame drawn as a table, through
# the natural renderer that a tab uses.

# A column of `1:length` that counts its reads, so a test sees how many rows a
# view of the frame read.
struct _CountingColumn <: AbstractVector{Int}
    length::Int
    reads::Base.RefValue{Int}
end
Base.size(column::_CountingColumn) = (column.length,)
Base.getindex(column::_CountingColumn, i::Int) = (column.reads[] += 1; i)
Base.IndexStyle(::Type{_CountingColumn}) = IndexLinear()

# Every text a canvas drew, as (x, y, text), through viewports and down a list
# for at most `limit` nodes in each direction.
function _data_frame_texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[]; limit = 50)
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            n = elements; seen = 0
            while n !== nothing && seen < limit
                _data_frame_texts(n.value, ox + Int(node.x), oy + Int(node.y), found; limit)
                n = n.next; seen += 1
            end
            n = elements.prev; seen = 0
            while n !== nothing && seen < limit
                _data_frame_texts(n.value, ox + Int(node.x), oy + Int(node.y), found; limit)
                n = n.prev; seen += 1
            end
        else
            for element in elements
                _data_frame_texts(element, ox + Int(node.x), oy + Int(node.y), found; limit)
            end
        end
    elseif node isa GraphicsViewport
        _data_frame_texts(node.content, ox + Int(node.x), oy + Int(node.y), found; limit)
    elseif node isa GraphicsText
        push!(found, (ox + Int(node.x), oy + Int(node.y), string(node.text)))
    end
    found
end

# The IO maps of the steps of the row of a view: the view, which holds the table
# and the scroll bar, and the grid that places them.
_data_frame_view_iomap(io) = io.step_iomaps[1][]
_data_frame_grid_iomap(io) = io.step_iomaps[end][]
# The IO maps of the table and of the scroll bar: the grid holds the expression
# bar and an empty cell in its first row, and the table and the bar in its second.
_data_frame_table_iomap(io) = _data_frame_grid_iomap(io).child_iomaps[3][3]
_data_frame_bar_entry(io) = _data_frame_grid_iomap(io).child_iomaps[4]

# The viewport of the cells: the rows as they are drawn under the header row.
# The table is the first cell of the grid; the region of the cells is its last
# element, and it holds the graphics of the rows and the pane of the cells.
function _data_frame_body(io)
    cells = _data_frame_table_iomap(io).output.elements[end]
    pane = only(e for e in cells.elements if e isa GraphicsCanvas)
    only(e for e in pane.elements if e isa GraphicsViewport)
end

_data_frame_texts_in_body(io; limit = 50) = _data_frame_texts(_data_frame_body(io); limit)

function _read_data_frame_key(projection, io, key::Symbol)
    change = read_intent(projection, nothing,
                         Intent(KeyDown(key, ModifierKeys(ctrl = true); time = 0.0), nothing), io)
    change isa Intent ? change.operation : change
end

"""
    test_data_frame_view()

A `DataFrameView` draws through the natural renderer as a table that scrolls
its own parts: a header with the name and the type of each column, the rows that
the table shows and no others, and Ctrl+Home and Ctrl+End that jump to the first
and the last row.
"""
function test_data_frame_view()
    @testset "a data frame drawn as a table" begin
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(600)),
                                    height = Cell(Int32(300)))

        @testset "the header names each column and its type" begin
            view = DataFrameView(make_data_frame_example(rows = 3))
            io = print_document(projection, nothing, view, context())
            found = Set(t[3] for t in _data_frame_texts(io.output))
            @test "id :: Int64" in found
            @test "name :: String" in found
            @test "in_stock :: Bool" in found
            @test "discount :: Float64?" in found
            # Rows 1 to 3 have a discount; row 5 has none, and shows it.
            @test "item 1" in found
            @test "missing" ∉ found
            five = DataFrameView(make_data_frame_example(rows = 5); anchor = 5)
            @test "missing" in Set(t[3] for t in
                                   _data_frame_texts(print_document(projection, nothing, five,
                                                                    context()).output))
        end

        @testset "the table follows the widget theme of its appearance at each print" begin
            appearance = Appearance()
            scaled = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0), appearance)
            view = DataFrameView(make_data_frame_example(rows = 3))
            io = print_document(scaled, nothing, view, context())
            view_projection = _data_frame_view_iomap(io).projection
            step = view_projection.row_step
            # The padding of a cell is the control padding of the theme, 5 above
            # and 5 below, so a spacing scale of 2 adds 10 to the step of a row.
            appearance.spacing_scale = 2.0
            @test view_projection.row_step == step + 10
            size_of(text, canvas) = begin
                found = Ref(0)
                walk(node) = if node isa GraphicsCanvas
                    foreach(e -> walk(e isa Cell ? e[] : e), node.elements isa ListNode ? Any[] : node.elements)
                elseif node isa GraphicsViewport
                    walk(node.content)
                elseif node isa GraphicsText && string(node.text) == text
                    found[] = Int(node.font.size)
                end
                walk(canvas)
                found[]
            end
            plain = size_of("id :: Int64", io.output)
            appearance.font_scale = 2.0
            large = size_of("id :: Int64", print_document(scaled, nothing, view, context()).output)
            @test plain > 0 && large == 2 * plain
        end

        @testset "each row shows its row number, and the corner the count of the rows" begin
            frame = DataFrame(id = 1001:1200)
            io = print_document(projection, nothing, DataFrameView(frame), context())
            place_of(text) = only((t[1], t[2]) for t in _data_frame_texts(io.output) if t[3] == text)
            for k in 1:3
                @test place_of(string(k))[2] == place_of(string(1000 + k))[2]
                @test place_of(string(k))[1] < place_of(string(1000 + k))[1]
            end
            @test place_of("200")[2] == place_of("id :: Int64")[2]
            @test place_of("200")[1] < place_of("id :: Int64")[1]
            # From row 150 on, the numbers follow the rows.
            io = print_document(projection, nothing, DataFrameView(frame; anchor = 150), context())
            @test place_of("150")[2] == place_of("1150")[2]
        end

        @testset "a frame of ten million rows reads a screenful" begin
            reads = Ref(0)
            frame = DataFrame(id = _CountingColumn(10_000_000, reads); copycols = false)
            io = print_document(projection, nothing, DataFrameView(frame), context())
            body = _data_frame_body(io)
            Int(body.content.y)          # the table places the list: a walk to its bottom
            @test reads[] < 30
            found = _data_frame_texts_in_body(io)
            @test any(t -> t[3] == "1", found)
            # `_data_frame_texts` walks fifty rows more.
            @test reads[] < 100
        end

        @testset "Ctrl+End shows the last row at the bottom, Ctrl+Home the first at the top" begin
            count = 10_000_000
            reads = Ref(0)
            view = DataFrameView(DataFrame(id = _CountingColumn(count, reads); copycols = false))
            io = print_document(projection, nothing, view, context())
            first_row_y = only(t[2] for t in _data_frame_texts_in_body(io) if t[3] == "1")

            last_op = _read_data_frame_key(projection, io, :end)
            @test last_op !== nothing
            evaluate_operation(nothing, last_op)
            @test view.anchor == count
            found = _data_frame_texts_in_body(io)
            last_y = only(t[2] for t in found if t[3] == string(count))
            before_y = only(t[2] for t in found if t[3] == string(count - 1))
            @test before_y < last_y
            body = _data_frame_body(io)
            # The first row starts at the top of the cells, and the last row
            # ends at their bottom. A line of text is the ascent and the
            # descent of the measure, 12 and 4.
            @test first_row_y == Int(body.y)
            @test last_y + 12 + 4 == Int(body.y) + Int(body.h)
            @test reads[] < 200

            first_op = _read_data_frame_key(projection, io, :home)
            evaluate_operation(nothing, first_op)
            @test view.anchor == 1
            @test only(t[2] for t in _data_frame_texts_in_body(io) if t[3] == "1") == first_row_y
        end

        @testset "a scroll far from the anchor moves the anchor, and the rows stay in place" begin
            reads = Ref(0)
            view = DataFrameView(DataFrame(id = _CountingColumn(10_000_000, reads); copycols = false))
            io = print_document(projection, nothing, view, context())
            y_of(text; limit = 50) = only(t[2] for t in _data_frame_texts_in_body(io; limit) if t[3] == text)
            wheel(dy) = read_intent(projection, nothing,
                                    Intent(MouseScroll(0, dy, 100, 150; time = 0.0), nothing), io).operation
            step = y_of("2") - y_of("1")
            # A turn near the anchor moves the rows by one step of the wheel.
            near = y_of("2")
            evaluate_operation(nothing, wheel(-1))
            turn = near - y_of("2")
            @test turn > 0
            @test view.anchor == 1
            # Three hundred rows down, a turn moves the anchor to the row at the
            # top, and every row moves by one turn as before.
            getfield(view, :scroll_position)[] = Point2D(0, 300 * step)
            before = y_of("305"; limit = 400)       # 304 rows from the anchor
            evaluate_operation(nothing, wheel(-1))
            @test view.anchor == 301
            @test y_of("305") == before - turn
            @test reads[] < 1000
        end

        @testset "a frame of many columns draws them as a list, and a far turn moves the column anchor" begin
            # Three rows, and a value in each cell that no other cell has.
            frame = DataFrame([Symbol("c", j) => collect(1:3) .+ 1000 * j for j in 1:1000])
            view = DataFrameView(frame)
            io = print_document(projection, nothing, view, context())
            texts(; limit = 50) = _data_frame_texts(io.output; limit)
            x_of(text; limit = 50) = only(t[1] for t in texts(; limit) if t[3] == text)
            side(dx) = read_intent(projection, nothing,
                                   Intent(MouseScroll(dx, 0, 100, 150; time = 0.0), nothing), io).operation
            found = Set(t[3] for t in texts())
            @test "c1 :: Int64" in found
            @test "c2 :: Int64" in found
            @test "c1000 :: Int64" ∉ found
            # A header sits over its column, and a number at the right of it.
            @test x_of("c2 :: Int64") < x_of("2001")
            # Three hundred columns to the side, a turn moves the column anchor
            # to the column at the left edge, and every column moves by the
            # turn, as it would with no move.
            step = x_of("c2 :: Int64") - x_of("c1 :: Int64")
            getfield(view, :scroll_position)[] = Point2D(300 * step, 0)
            before = x_of("c305 :: Int64"; limit = 400)
            near = side(-1)
            evaluate_operation(nothing, near)
            @test view.column_anchor == 301
            @test view.anchor == 1
            after = x_of("c305 :: Int64")
            @test 0 < before - after < step
        end

        @testset "the scroll bar shows the row at the top, and a click on it moves the rows" begin
            count = 10_000
            view = DataFrameView(DataFrame(id = collect(1:count)))
            io = print_document(projection, nothing, view, context())
            bar = _data_frame_view_iomap(io).bar
            @test bar.value == 0.0
            @test 0 < bar.thumb_size < 0.01
            # Ctrl+End shows the last row at the bottom: the thumb is at the end.
            evaluate_operation(nothing, _read_data_frame_key(projection, io, :end))
            @test bar.value == 1.0
            # Shift and a click in the middle of the bar jump to the middle of the frame.
            (x_cell, y_cell, cim) = _data_frame_bar_entry(io)
            x = Int(x_cell[]) + Int(cim.output.w) ÷ 2
            y = Int(y_cell[]) + Int(cim.output.h) ÷ 2
            click(y, modifiers) = read_intent(projection, nothing,
                Intent(MouseClick(:left, x, y, 1, modifiers; time = 0.0), nothing), io).operation
            evaluate_operation(nothing, click(y, ModifierKeys(shift = true)))
            @test abs(view.anchor - count ÷ 2) < count ÷ 50
            @test abs(bar.value - 0.5) < 0.02
            # A click below the thumb moves one page: the rows that the table shows.
            top = view.anchor + view.top_row - 1
            evaluate_operation(nothing, click(y + Int(cim.output.h) ÷ 4, ModifierKeys()))
            moved = view.anchor + view.top_row - 1 - top
            @test 0 < moved < count ÷ 100
            @test bar.value > 0.5
            # A turn of the wheel moves the thumb with the row at the top.
            before = bar.value
            evaluate_operation(nothing, read_intent(projection, nothing,
                Intent(MouseScroll(0, -5, 100, 150; time = 0.0), nothing), io).operation)
            @test view.top_row > 1
            @test bar.value > before
        end

        @testset "a frame with no rows draws its header" begin
            view = DataFrameView(DataFrame(id = Int[], name = String[]))
            io = print_document(projection, nothing, view, context())
            found = Set(t[3] for t in _data_frame_texts(io.output))
            @test "id :: Int64" in found
            @test _read_data_frame_key(projection, io, :end) === nothing
        end
    end
end
