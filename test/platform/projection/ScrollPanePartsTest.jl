"""
Tests for a `WidgetScrollPane` whose content prints to a `ScrollLayout`: the pane
takes the parts apart, puts each in a viewport of its own, moves the center on
both axes and each edge on one, offers the content the view of the center, and
gives the content a point in the frame in which the parts are put together.
"""

using Test
using ProjecturedKernel.EventModule: MouseScroll
using ProjecturedKernel.GestureModule: MouseClick
using ProjecturedKernel.OperationModule: ReplaceViewStateOperation, get_wrapped_operation,
    CompoundOperation
using ProjecturedKernel.ProjectionModule: Projection
using ProjecturedKernel.IoMapModule: SimpleIoMap
import ProjecturedKernel.ProjectionModule: print_document, read_intent, map_reference_forward
using ProjecturedPlatform.LayoutModule: ScrollLayout
using ProjecturedPlatform.WidgetModule: WidgetScrollPane, Point2D, WidgetToGraphics
using ProjecturedPlatform.GraphicsModule: GraphicsCanvas, GraphicsRect, GraphicsViewport, layout_none
using ProjecturedPlatform.StyleModule: StyleFont, color_black
using ProjecturedPlatform.ProjectionAlgebraModule: RecursiveProjection, TypeDispatchingProjection

# A part: a canvas of the size `(w, h)` filled by one rectangle.
_spp_part(w, h) = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(w)), Cell(Int32(h)),
                                 CellVector(Cell[Cell(GraphicsRect(0, 0, w, h; color = color_black))]),
                                 layout_none, true, Cell(nothing))

# The content: a `ScrollLayout` that prints as itself, as a projection that makes
# parts gives them. It keeps the context it prints with and the points of the
# clicks that reach it.
struct _SppContent <: Projection
    contexts::Vector{Any}
    clicks::Vector{Any}
end
_SppContent() = _SppContent(Any[], Any[])

function print_document(p::_SppContent, recursion, input::ScrollLayout, ctx)
    push!(p.contexts, ctx)
    SimpleIoMap(p, input, input)
end

function read_intent(p::_SppContent, iomap, evt::MouseClick)
    push!(p.clicks, (evt.x, evt.y))
    ReplaceSelectionOperation(EmptyReference())
end
read_intent(::_SppContent, iomap, payload) = nothing

# The output is the input, so a reference into a part names the same part.
map_reference_forward(::_SppContent, iomap, reference) = reference

# A content that makes its parts as a text with a gutter does: a center as wide
# as the width it is offered, which wraps a fixed area into that width, and a
# left edge as high as the center. The marker type says which content it is.
struct _SppWrapping <: Document end

struct _SppWrappingContent <: Projection end

function print_document(p::_SppWrappingContent, recursion, input::_SppWrapping, ctx)
    edge = ctx.maximum_width
    center = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(@computation Int32(edge[])),
                            Cell(@computation Int32(cld(8000, max(1, Int(edge[]))))),
                            CellVector(Cell[Cell(GraphicsRect(0, 0, 10, 10; color = color_black))]),
                            layout_none, true, Cell(nothing))
    left = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(20)), getfield(center, :h),
                          CellVector(Cell[Cell(GraphicsRect(0, 0, 20, 10; color = color_black))]),
                          layout_none, true, Cell(nothing))
    SimpleIoMap(p, input, ScrollLayout(; center, left))
end

_spp_renderer(content) = RecursiveProjection(TypeDispatchingProjection(vcat(
    Pair{Type, Any}[_SppWrapping => _SppWrappingContent()],
    Pair{Type, Any}[ScrollLayout => content],
    WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FixedMeasure(10, 15, 5, 0)).dispatch)))

# The viewports of a printed pane, in order.
_spp_viewports(output) =
    [node for node in (element isa AbstractCell ? element[] : element for element in output.elements)
     if node isa GraphicsViewport]

_spp_box(viewport) = (Int(viewport.x[]), Int(viewport.y[]), Int(viewport.w[]), Int(viewport.h[]))

function _spp_offset(viewport)
    held = viewport.content isa AbstractCell ? viewport.content[] : viewport.content
    (Int(held.x[]), Int(held.y[]))
end

# The scroll position that an answer writes into `pane`, or `nothing`.
function _spp_written_scroll(op, pane)
    for o in (op isa CompoundOperation ? op.operations : Any[op])
        o isa ReplaceViewStateOperation && (o = get_wrapped_operation(o))
        (o isa ReplaceReferencedValueOperation && o.document === pane &&
         o.reference.head == FieldReferenceStep("scroll_position")) && return o.value
    end
    nothing
end

function test_scroll_pane_parts()
@testset "a scroll pane takes a ScrollLayout apart" begin
    content = _SppContent()
    layout = ScrollLayout(; center = _spp_part(300, 200), left = _spp_part(20, 200),
                          top = _spp_part(300, 10), top_left = _spp_part(20, 10))
    pane = WidgetScrollPane(layout; size = Point2D(100, 50))
    renderer = _spp_renderer(content)
    iomap = print_document(renderer, pane)
    output = iomap.output
    viewports = _spp_viewports(output)
    corner, top, left, center = viewports
    cox, coy = _spp_box(corner)[1:2]

    @testset "each part has a viewport at its band of the view" begin
        @test length(viewports) == 4
        @test _spp_box(corner) == (cox, coy, 20, 10)
        @test _spp_box(top) == (cox + 20, coy, 80, 10)
        @test _spp_box(left) == (cox, coy + 10, 20, 40)
        @test _spp_box(center) == (cox + 20, coy + 10, 80, 40)
    end

    @testset "the pane offers the content the view of its center" begin
        context = content.contexts[end]
        @test Int(context.maximum_width[]) == 80
        @test Int(context.maximum_height[]) == 40
    end

    @testset "the center moves on both axes, an edge on one, a corner not at all" begin
        getfield(pane, :scroll_position)[] = Point2D(50, 30)
        @test _spp_offset(corner) == (0, 0)
        @test _spp_offset(top) == (-50, 0)
        @test _spp_offset(left) == (0, -30)
        @test _spp_offset(center) == (-50, -30)
        # The offset stops at the end of the center, which the view of the center
        # measures: 200 - 40 down.
        getfield(pane, :scroll_position)[] = Point2D(50, 500)
        @test _spp_offset(center) == (-50, -160)
        @test _spp_offset(left) == (0, -160)
        getfield(pane, :scroll_position)[] = Point2D(50, 30)
    end

    @testset "a click reaches the content in the frame of the parts put together" begin
        click(x, y) = read_intent(renderer, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
        op = click(cox + 5, coy + 17)        # on the left edge
        @test content.clicks[end] == (5, 47)
        @test strip_reference_types(op.path) ==
              ConcreteReference(FieldReferenceStep("content"), EmptyReference())
        click(cox + 23, coy + 14)            # on the center
        @test content.clicks[end] == (73, 44)
        click(cox + 25, coy + 5)             # on the top edge
        @test content.clicks[end] == (75, 5)
        click(cox + 5, coy + 5)              # on the corner
        @test content.clicks[end] == (5, 5)
    end

    @testset "a wheel over an edge scrolls the pane" begin
        op = read_intent(renderer, iomap,
                         MouseScroll(0, -1, cox + 5, coy + 17, ModifierKeys(); time = 0.0))
        written = _spp_written_scroll(op, pane)
        @test written !== nothing
        @test Int(written.x[]) == 50
        @test Int(written.y[]) > 30
    end

    @testset "a left edge as high as a center that wraps makes no cycle" begin
        wrapping = WidgetScrollPane(_SppWrapping(); size = Point2D(100, 50))
        wrapped = print_document(renderer, wrapping)
        boxes = [_spp_box(v) for v in _spp_viewports(wrapped.output)]
        # The center gets 100 - 20, and 8000 / 80 = 100 rows of height.
        @test boxes[2][3:4] == (80, 50)
        @test Int(wrapped.parts.canvases[5].h[]) == 100
        @test Int(wrapped.parts.canvases[4].h[]) == 100
    end

    @testset "a reference into a part maps to the canvas in its viewport" begin
        reference = ConcreteReference(FieldReferenceStep("content"),
                                      ConcreteReference(FieldReferenceStep("center"), EmptyReference()))
        forward = map_reference_forward(iomap.projection, iomap, reference)
        @test forward !== nothing
        node = evaluate_reference(output, forward)
        @test node isa GraphicsCanvas
        @test getfield(node, :elements) === getfield(layout.center, :elements)
    end
end
end
