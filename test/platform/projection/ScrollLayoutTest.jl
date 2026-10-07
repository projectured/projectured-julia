"""
Tests for `ScrollLayout` in a place that does not scroll it: the parts in three
columns and three rows, the range that the center gets, and the references and
the clicks that reach a part.
"""

using Test
using ProjecturedKernel.GestureModule: MouseClick
using ProjecturedKernel.ProjectionModule: with_exact_size, Projection
import ProjecturedKernel.ProjectionModule: print_document, read_intent
using ProjecturedKernel.IoMapModule: SimpleIoMap
using ProjecturedPlatform.LayoutModule: ScrollLayout, SCROLL_LAYOUT_PARTS,
    compute_scroll_layout_extents, get_scroll_layout_place, find_scroll_layout_part_at,
    LayoutToGraphics
using ProjecturedPlatform.GraphicsModule: GraphicsCanvas, GraphicsRect, layout_none
using ProjecturedPlatform.StyleModule: color_black
using ProjecturedPlatform.ProjectionAlgebraModule: RecursiveProjection, TypeDispatchingProjection

# A part: a canvas of the size `(w, h)` filled by one rectangle, so a point
# anywhere in it hits it.
_sl_part(w, h) = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(w)), Cell(Int32(h)),
                                CellVector(Cell[Cell(GraphicsRect(0, 0, w, h; color = color_black))]),
                                layout_none, true, Cell(nothing))

# The projection of a part. It keeps the context that each part is printed with,
# and the point at which a click reaches it, in its own frame.
struct _SlProbe <: Projection
    contexts::Dict{UInt, Any}
    clicks::Vector{Any}
end
_SlProbe() = _SlProbe(Dict{UInt, Any}(), Any[])

function print_document(p::_SlProbe, recursion, input::GraphicsCanvas, ctx)
    p.contexts[objectid(input)] = ctx
    SimpleIoMap(p, input, input)
end

function read_intent(p::_SlProbe, iomap, evt::MouseClick)
    push!(p.clicks, (iomap.input, evt.x, evt.y))
    ReplaceSelectionOperation(EmptyReference())
end
read_intent(::_SlProbe, iomap, payload) = nothing

_sl_renderer(probe) = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch, Pair{Type, Any}[GraphicsCanvas => probe])))

_sl_index(part) = findfirst(==(part), SCROLL_LAYOUT_PARTS)

# The (x, y) of each element of a rendered scroll layout.
function _sl_positions(output)
    positions = Tuple{Int,Int}[]
    for element in output.elements
        node = element isa AbstractCell ? element[] : element
        push!(positions, (Int(node.x[]), Int(node.y[])))
    end
    positions
end

function test_scroll_layout()
@testset "ScrollLayout: the parts in three columns and three rows" begin

    @testset "a column is as wide as its widest part, a row as high as its highest" begin
        sizes = Any[nothing for _ in SCROLL_LAYOUT_PARTS]
        sizes[_sl_index(:top_left)] = (30, 20)
        sizes[_sl_index(:top)] = (200, 18)
        sizes[_sl_index(:left)] = (25, 100)
        sizes[_sl_index(:center)] = (200, 100)
        sizes[_sl_index(:right)] = (10, 90)
        @test compute_scroll_layout_extents(sizes) == ((30, 200, 10), (20, 100, 0))
    end

    @testset "a part stands at the corner of its column and its row" begin
        widths, heights = (30, 200, 10), (20, 100, 5)
        @test get_scroll_layout_place(_sl_index(:top_left), widths, heights) == (0, 0)
        @test get_scroll_layout_place(_sl_index(:top), widths, heights) == (30, 0)
        @test get_scroll_layout_place(_sl_index(:left), widths, heights) == (0, 20)
        @test get_scroll_layout_place(_sl_index(:center), widths, heights) == (30, 20)
        @test get_scroll_layout_place(_sl_index(:right), widths, heights) == (230, 20)
        @test get_scroll_layout_place(_sl_index(:bottom_right), widths, heights) == (230, 120)
    end

    @testset "a point finds the cell that holds it" begin
        widths, heights = (30, 200, 0), (20, 100, 0)
        @test find_scroll_layout_part_at(10, 50, widths, heights) == _sl_index(:left)
        @test find_scroll_layout_part_at(30, 20, widths, heights) == _sl_index(:center)
        @test find_scroll_layout_part_at(229, 119, widths, heights) == _sl_index(:center)
        @test find_scroll_layout_part_at(40, 5, widths, heights) == _sl_index(:top)
        # A column or a row of no width holds no point, and nor does the outside.
        @test find_scroll_layout_part_at(230, 50, widths, heights) === nothing
        @test find_scroll_layout_part_at(40, 120, widths, heights) === nothing
        @test find_scroll_layout_part_at(-1, 50, widths, heights) === nothing
    end

    @testset "on its own the edges stand around the center" begin
        probe = _SlProbe()
        layout = ScrollLayout(; center = _sl_part(200, 100), left = _sl_part(30, 100),
                              top = _sl_part(200, 20))
        output = print_document(_sl_renderer(probe), layout).output
        @test (Int(output.w[]), Int(output.h[])) == (230, 120)
        # The order of SCROLL_LAYOUT_PARTS: the top, the left, the center.
        @test _sl_positions(output) == [(30, 0), (0, 20), (30, 20)]
    end

    @testset "the center gets the range less the edges, an edge a free range" begin
        probe = _SlProbe()
        center, left, right = _sl_part(200, 100), _sl_part(30, 100), _sl_part(20, 100)
        layout = ScrollLayout(; center, left, right, top = _sl_part(200, 15))
        renderer = _sl_renderer(probe)
        context = with_exact_size(PrinterContext(); width = Cell(Int32(300)),
                                  height = Cell(Int32(400)))
        # The build of a layout runs when its output is read.
        output = print_document(renderer, renderer, layout, context).output
        @test Int(output.w[]) == 250
        center_context = probe.contexts[objectid(center)]
        @test Int(center_context.maximum_width[]) == 250
        @test Int(center_context.maximum_height[]) == 385
        @test probe.contexts[objectid(left)].maximum_width === nothing
    end

    @testset "a reference into a part maps to the node that draws it, and back" begin
        probe = _SlProbe()
        layout = ScrollLayout(; center = _sl_part(200, 100), left = _sl_part(30, 100))
        renderer = _sl_renderer(probe)
        iomap = print_document(renderer, layout)
        center = ConcreteReference(FieldReferenceStep("center"), EmptyReference())
        forward = strip_reference_types(map_reference_forward(renderer, iomap, center))
        # The center is the second part that is present: the second wrapper.
        @test forward == ConcreteReference(FieldReferenceStep("elements"),
            ConcreteReference(RangeReferenceStep(1, 2),
                ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(RangeReferenceStep(0, 1), EmptyReference()))))
        back = strip_reference_types(map_reference_backward(renderer, iomap, forward))
        @test back == center
        # A point maps to the part drawn at it, and on into that part.
        at_point = strip_reference_types(map_reference_backward(renderer, iomap,
                                                                PointReferenceStep(10, 50)))
        @test at_point.head == FieldReferenceStep("left")
    end

    @testset "a click goes to the part at its point, in the frame of the part" begin
        probe = _SlProbe()
        center, left = _sl_part(200, 100), _sl_part(30, 100)
        layout = ScrollLayout(; center, left)
        renderer = _sl_renderer(probe)
        iomap = print_document(renderer, layout)
        click(x, y) = read_intent(renderer, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))

        op = click(40, 50)
        @test probe.clicks[end] == (center, 10, 50)
        @test strip_reference_types(op.path) ==
              ConcreteReference(FieldReferenceStep("center"), EmptyReference())

        op = click(5, 7)
        @test probe.clicks[end] == (left, 5, 7)
        @test strip_reference_types(op.path) ==
              ConcreteReference(FieldReferenceStep("left"), EmptyReference())
    end
end
end
