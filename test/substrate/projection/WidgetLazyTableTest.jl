# WidgetLazyTable — a table whose cost is the rows a person can see.
#
# The point of it is what it does NOT do, so the tests count nodes rather than
# look at a picture: a table of 100,000 rows must build a handful of them, and a
# click far down it must answer the right row without the rows above it ever
# being built.

using ProjecturedKernel.CellModule: Cell, ComputedCell
using ProjecturedCollection.CollectionModule: ListNode

function test_widget_lazy_table()
@testset "WidgetLazyTable" begin

_measure = (t, f) -> (length(t) * 8, 16)
_projection() = WidgetToGraphics(font_ubuntu_regular_20; measure = _measure)

# A table of `rows` rows, counting how many times a cell was asked for.
function _table(rows::Int; header::Bool = true)
    asked = Ref(0)
    cell = (row, column) -> begin
        asked[] += 1
        column == 1 ? "row " * string(row) : "value " * string(row * column)
    end
    (WidgetLazyTable(Point2D(0, 0), [("ID", 80), ("Value", 120)], rows, 20, cell;
                     header = header), asked)
end

# How many row canvases the list holds, walking at most `limit` of them. The walk
# is what a renderer does, so counting it counts the work.
function _walk(canvas, limit::Int)
    node = canvas.elements
    @assert node isa ListNode
    seen = 0
    while node !== nothing && seen < limit
        seen += 1
        node = node.next
    end
    seen
end

@testset "the whole table is one lazy list" begin
    table, _ = _table(100_000)
    io = print_document(_projection().dispatch |> TypeDispatchingProjection |>
                        RecursiveProjection, table)
    canvas = io.output
    # Its extent is arithmetic, so a table nobody walked still says how tall it is.
    @test Int(canvas.w) == 200
    @test Int(canvas.h) == (100_000 + 1) * 20
    @test canvas.elements isa ListNode
end

@testset "only the rows that are walked are built" begin
    table, asked = _table(100_000)
    io = print_document(RecursiveProjection(TypeDispatchingProjection(
             _projection().dispatch)), table)
    canvas = io.output
    # Building the document asks for nothing: the head node is the header.
    before = asked[]
    # A viewport 300 tall shows fifteen rows of twenty, so a renderer walks
    # about that many. Counting twenty is already generous.
    @test _walk(canvas, 20) == 20
    # Two columns for each of twenty rows, and the header asks for none of them.
    @test asked[] - before <= 2 * 20
    # The whole table is 100,000 rows, and nothing like that was built.
    @test asked[] < 1000
end

@testset "a header is the prefix a pane holds still" begin
    table, _ = _table(50)
    io = print_document(RecursiveProjection(TypeDispatchingProjection(
             _projection().dispatch)), table)
    extent = get_frozen_extent(io)
    @test extent !== nothing
    @test extent[] == (0, 20)

    bare, _ = _table(50; header = false)
    bare_io = print_document(RecursiveProjection(TypeDispatchingProjection(
                  _projection().dispatch)), bare)
    @test get_frozen_extent(bare_io)[] == (0, 0)
    # With no header the first node is row 1, so the table is one band shorter.
    @test Int(bare_io.output.h) == 50 * 20
end

@testset "a click answers the row the arithmetic names" begin
    table, _ = _table(100_000)
    io = print_document(RecursiveProjection(TypeDispatchingProjection(
             _projection().dispatch)), table)
    # Band 0 is the header and answers no row.
    @test read_intent(io.projection, io, MousePress(:left, 10, 5, ModifierKeys())) === nothing
    # Band 1 is row 1.
    first_row = read_intent(io.projection, io, MousePress(:left, 10, 25, ModifierKeys()))
    @test get_widget_lazy_table_selected_row(
        WidgetLazyTable(Point2D(0, 0), [("ID", 80)], 1, 20, (r, c) -> "";
                        header = true)) == 0
    @test first_row isa ReplaceSelectionOperation

    # Far down it, and no row above it was built to answer.
    deep = read_intent(io.projection, io, MousePress(:left, 10, 20 * 50_000 + 5,
                                                     ModifierKeys()))
    @test deep isa ReplaceSelectionOperation
    # A press past the last row answers nothing rather than a row that is not there.
    @test read_intent(io.projection, io,
                      MousePress(:left, 10, 20 * 200_000, ModifierKeys())) === nothing
    # And a press to the right of the last column is outside the table.
    @test read_intent(io.projection, io,
                      MousePress(:left, 500, 25, ModifierKeys())) === nothing
end

end
end
