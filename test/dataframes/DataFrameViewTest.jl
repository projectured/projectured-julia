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

# The viewport of the cells: the rows as they are drawn under the header row.
# The region of the cells is the last element of the table, and it holds the
# graphics of the rows and the pane of the cells.
function _data_frame_body(io)
    cells = io.output.elements[end]
    pane = only(e for e in cells.elements if e isa GraphicsCanvas)
    only(e for e in pane.elements if e isa GraphicsViewport)
end

_data_frame_texts_in_body(io) = _data_frame_texts(_data_frame_body(io))

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

        @testset "a frame with no rows draws its header" begin
            view = DataFrameView(DataFrame(id = Int[], name = String[]))
            io = print_document(projection, nothing, view, context())
            found = Set(t[3] for t in _data_frame_texts(io.output))
            @test "id :: Int64" in found
            @test _read_data_frame_key(projection, io, :end) === nothing
        end
    end
end
