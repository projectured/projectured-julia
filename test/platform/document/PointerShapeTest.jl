# Tests of `find_pointer_shape`: the shape of the pointer at a point of what a
# window draws.

# A row of a laid-out list at `index`, 20 pixels high, that holds an I-beam over
# its whole box. `reads[]` counts the rows whose elements the walk read.
function _make_pointer_shape_row(index::Int, reads::Ref{Int})
    GraphicsCanvas(Cell(Int32(0)), Cell(Int32(20 * (index - 1))), Cell(Int32(100)), Cell(Int32(20)),
                   Cell(@computation (reads[] += 1;
                                      CellVector(Cell[Cell(GraphicsPointerShape(0, 0, 100, 20, :ibeam))]))),
                   Cell(layout_none), Cell(true), Cell(nothing))
end

function test_pointer_shape()
    @testset "find_pointer_shape" begin
        @testset "no region is the default" begin
            canvas = GraphicsCanvas([GraphicsRect(0, 0, 50, 50)]; w = 200, h = 100)
            @test find_pointer_shape(canvas, 10, 10) === :default
        end

        @testset "the last region that holds the point wins" begin
            canvas = GraphicsCanvas([GraphicsPointerShape(0, 0, 100, 100, :ibeam),
                                     GraphicsPointerShape(40, 0, 20, 100, :double_arrow_horizontal)];
                                    w = 200, h = 100)
            @test find_pointer_shape(canvas, 10, 10) === :ibeam
            @test find_pointer_shape(canvas, 45, 10) === :double_arrow_horizontal
            @test find_pointer_shape(canvas, 60, 10) === :ibeam      # the right edge is outside
            @test find_pointer_shape(canvas, 150, 10) === :default
        end

        @testset "a region of a drag wins over a plain region in any order" begin
            canvas = GraphicsCanvas([GraphicsPointerShape(0, 0, 200, 100, :closed_hand; drag = true),
                                     GraphicsPointerShape(0, 0, 50, 50, :ibeam)];
                                    w = 200, h = 100)
            @test find_pointer_shape(canvas, 10, 10) === :closed_hand
            @test find_pointer_shape(canvas, 100, 80) === :closed_hand
            # Among the regions of a drag, the last one wins.
            push!(canvas.elements, GraphicsPointerShape(0, 0, 50, 50, :crossed_circle; drag = true))
            @test find_pointer_shape(canvas, 10, 10) === :crossed_circle
            @test find_pointer_shape(canvas, 100, 80) === :closed_hand
        end

        @testset "a nested canvas moves its regions" begin
            inner = GraphicsCanvas([GraphicsPointerShape(0, 0, 10, 10, :pointing_hand)]; x = 30, y = 40)
            canvas = GraphicsCanvas([inner]; w = 200, h = 100)
            @test find_pointer_shape(canvas, 35, 45) === :pointing_hand
            @test find_pointer_shape(canvas, 5, 5) === :default
        end

        @testset "the root canvas is at the origin of the window" begin
            canvas = GraphicsCanvas([GraphicsPointerShape(0, 0, 10, 10, :ibeam)]; x = 50, y = 50)
            @test find_pointer_shape(canvas, 5, 5) === :ibeam
        end

        @testset "a viewport clips the regions inside it" begin
            content = GraphicsCanvas([GraphicsPointerShape(0, 0, 300, 300, :ibeam)])
            viewport = GraphicsViewport(10, 10, 50, 50, content)
            canvas = GraphicsCanvas([viewport]; w = 400, h = 400)
            @test find_pointer_shape(canvas, 20, 20) === :ibeam
            @test find_pointer_shape(canvas, 100, 100) === :default
        end

        @testset "a viewport moves its regions by its content and its transform" begin
            # The content scrolls up by 100: a region at y = 110 of the content
            # shows at y = 10 of the viewport.
            scrolled = GraphicsCanvas([GraphicsPointerShape(0, 110, 50, 10, :ibeam)]; y = -100)
            canvas = GraphicsCanvas([GraphicsViewport(0, 0, 200, 200, scrolled)]; w = 200, h = 200)
            @test find_pointer_shape(canvas, 5, 15) === :ibeam
            @test find_pointer_shape(canvas, 5, 115) === :default
            # Twice the size, moved by (20, 0): the region at (10, 10, 10, 10)
            # covers (40, 20) to (60, 40) of the viewport.
            zoomed = GraphicsCanvas([GraphicsPointerShape(10, 10, 10, 10, :ibeam)])
            transform = make_affine_translate(20, 0) ∘ make_affine_scale(2)
            canvas = GraphicsCanvas([GraphicsViewport(0, 0, 200, 200, zoomed; transform)];
                                    w = 200, h = 200)
            @test find_pointer_shape(canvas, 45, 25) === :ibeam
            @test find_pointer_shape(canvas, 59, 39) === :ibeam
            @test find_pointer_shape(canvas, 35, 25) === :default
            @test find_pointer_shape(canvas, 15, 15) === :default
        end

        @testset "a list walks only the rows at the point" begin
            reads = Ref(0)
            rows = CellVector(Cell[Cell(_make_pointer_shape_row(index, reads)) for index in 1:50])
            list = GraphicsCanvas(rows; layout = layout_vertical, overlapping = false, w = 100, h = 1000)
            canvas = GraphicsCanvas([GraphicsViewport(0, 0, 100, 100, list)]; w = 100, h = 100)
            @test find_pointer_shape(canvas, 10, 45) === :ibeam
            @test reads[] == 1
            # A point outside the viewport walks no row.
            @test find_pointer_shape(canvas, 10, 150) === :default
            @test reads[] == 1
        end

        @testset "a list of nodes walks only the rows at the point" begin
            reads = Ref(0)
            head = ListNode(_make_pointer_shape_row(1, reads))
            for index in 2:50
                push!(head, _make_pointer_shape_row(index, reads))
            end
            list = GraphicsCanvas(head; layout = layout_vertical, overlapping = false)
            canvas = GraphicsCanvas([list]; w = 100, h = 100)
            @test find_pointer_shape(canvas, 10, 65) === :ibeam
            @test reads[] == 1
        end

        @testset "a live shape follows its cell" begin
            shape = Cell(:arrow)
            canvas = GraphicsCanvas([GraphicsPointerShape(0, 0, 10, 10, () -> shape[])]; w = 10, h = 10)
            @test find_pointer_shape(canvas, 5, 5) === :arrow
            shape[] = :hourglass
            @test find_pointer_shape(canvas, 5, 5) === :hourglass
        end

        @testset "a region draws nothing and takes no hit" begin
            region = GraphicsPointerShape(0, 0, 10, 10, :ibeam)
            canvas = GraphicsCanvas([region]; w = 100, h = 100)
            @test hit_element_at(canvas, 5, 5) === nothing
            @test get_graphics_size(region) == (0, 0)
        end
    end
end
