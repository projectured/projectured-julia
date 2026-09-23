"""
Tests for `AnchoredLayout` — children positioned relative to something already
placed, and composited over it.

The property the type exists for is the one asserted first and hardest:
**annotating something must not move it.** A count beside a diagram node, a
rate along a link — none of it may enter the content's own layout, or a diagram
whose annotations change every frame would re-lay-out every frame and its nodes
would wander.
"""

using Test
using ProjecturedKernel.CellModule: Cell, AbstractCell, set_cell_value!
using ProjecturedLayout.LayoutModule: AnchoredLayout, AnchoredEntry, VerticalLayout,
    compute_anchored_positions
using ProjecturedLayout.LayoutModule: LayoutToGraphics
using ProjecturedWidget.WidgetModule: WidgetLabel, Point2D
using ProjecturedWidget.WidgetModule: WidgetToGraphics
using ProjecturedGraphics.GraphicsModule: GraphicsCanvas, GraphicsRect, layout_none
using ProjecturedStyle.StyleModule: color_black
using ProjecturedCollection.CollectionModule: CellVector
using ProjecturedStyle.StyleModule: font_ubuntu_monospace_regular_20
import ProjecturedKernel.ProjectionModule: print_document, map_reference_forward
using ProjecturedKernel.ProjectionModule: Projection
using ProjecturedKernel.IoMapModule: SimpleIoMap
using ProjecturedKernel.ReferenceModule: var"@reference"
using ProjecturedKernel.ReferenceModule: var"@reference_case"
using ProjecturedProjection.ProjectionAlgebraModule: RecursiveProjection
using ProjecturedProjection.ProjectionAlgebraModule: TypeDispatchingProjection

_al_measure(text, _font) = (length(text) * 10, 20)

_al_renderer() = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(font_ubuntu_monospace_regular_20; measure = _al_measure).dispatch)))

_al_label(text) = VerticalLayout(Any[WidgetLabel(Point2D(0, 0), text)]; gap = 0)

# A content projection that draws a box per child and can say *where* it drew
# each one. That second half is the contract a reference-named target rests on:
# an anchor asks the content's own projection where something it holds ended up.
struct _AlBoxes <: Projection end

function print_document(p::_AlBoxes, recursion, doc::VerticalLayout, ctx)
    boxes = Any[GraphicsRect(0, (i - 1) * 30, 40, 20, color_black)
                for i in 1:length(doc.children)]
    canvas = GraphicsCanvas(CellVector(Cell[Cell(b) for b in boxes]), layout_none)
    SimpleIoMap(p, doc, canvas)
end

map_reference_forward(p::_AlBoxes, iomap, reference) =
    @reference_case reference begin
        ::VerticalLayout.children[i] => (@reference iomap.output elements[i])
        __ => nothing
    end

# The (x, y) of each element of a rendered anchored layout.
function _al_positions(output)
    positions = Tuple{Int,Int}[]
    for element in output.elements
        node = element isa AbstractCell ? element[] : element
        node isa GraphicsCanvas || continue
        push!(positions, (Int(node.x[]), Int(node.y[])))
    end
    positions
end

function test_anchored_layout()
@testset "AnchoredLayout: placed beside, drawn over, changing nothing" begin

    @testset "placement picks a side, and flips rather than overflow" begin
        # A 20×10 child to the right of a 60×30 box at (100, 50): past the box,
        # centred on the other axis.
        entry = [(20, 10, :right, 0, 0)]
        @test compute_anchored_positions(entry, [(100, 50, 60, 30)]; bounding_w = 0,
                                         bounding_h = 0, stacking_gap = 4) == [(160, 60)]

        # The same request in a region too narrow for the right side takes the
        # left one instead — the preferred side is a preference.
        @test compute_anchored_positions(entry, [(100, 50, 60, 30)]; bounding_w = 150,
                                         bounding_h = 200, stacking_gap = 4) == [(80, 60)]

        # Offsets are applied after the side is chosen, not before it.
        offset = [(20, 10, :right, 6, -2)]
        @test compute_anchored_positions(offset, [(100, 50, 60, 30)]; bounding_w = 0,
                                         bounding_h = 0, stacking_gap = 4) == [(166, 58)]

        # Every side is expressible.
        for (side, expected) in ((:left, (80, 60)), (:above, (120, 40)), (:below, (120, 80)))
            @test compute_anchored_positions([(20, 10, side, 0, 0)], [(100, 50, 60, 30)];
                                             bounding_w = 0, bounding_h = 0,
                                             stacking_gap = 4) == [expected]
        end
    end

    @testset "a target that could not be resolved is not a failure" begin
        # An annotation whose target is hidden or gone goes to the origin and
        # takes no part in stacking — it is anchored to nothing, so it can
        # crowd nothing.
        @test compute_anchored_positions([(20, 10, :right, 0, 0)], [nothing];
                                         bounding_w = 0, bounding_h = 0, stacking_gap = 4) ==
              [(0, 0)]
    end

    @testset "entries that would overlap are stacked, in the order given" begin
        two = [(20, 10, :right, 0, 0), (20, 10, :right, 0, 0)]
        one_box = [(0, 0, 10, 10), (0, 0, 10, 10)]
        # The first keeps its place; the second drops below it by its height
        # plus the gap.
        @test compute_anchored_positions(two, one_box; bounding_w = 0, bounding_h = 0,
                                         stacking_gap = 4) == [(10, 0), (10, 14)]
    end

    @testset "an annotation does not move or grow what it annotates" begin
        content = _al_label("the diagram")
        renderer = _al_renderer()
        alone = print_document(renderer, content).output
        @test (Int(alone.w[]), Int(alone.h[])) == (110, 20)

        note = AnchoredEntry(WidgetLabel(Point2D(0, 0), "12 waiting");
                             target = alone, placement = :right, offset_x = 6)
        annotated = print_document(renderer, AnchoredLayout(content, Any[note])).output

        # Same extent as the content on its own: the annotation is over it, not
        # in it. This is the property the whole type exists for.
        @test (Int(annotated.w[]), Int(annotated.h[])) == (110, 20)
        # Content first, annotation after — so the annotation draws on top.
        positions = _al_positions(annotated)
        @test length(positions) == 2
        @test positions[1] == (0, 0)
        @test positions[2] == (116, 0)      # past the content's right edge, plus the offset
    end

    @testset "a target named by reference is resolved through the content" begin
        # The other way to name a target, and the one a live diagram uses: the
        # annotation names *what it annotates* in the content's own terms and the
        # content's projection says where that ended up. Nothing here reads a
        # graphics document directly.
        content = VerticalLayout(Any[WidgetLabel(Point2D(0, 0), "a"),
                                     WidgetLabel(Point2D(0, 0), "b")]; gap = 0)
        note = AnchoredEntry(WidgetLabel(Point2D(0, 0), "note");
                             reference = @reference(content, children[2]),
                             placement = :right)
        renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
            Pair{Type,Any}[VerticalLayout => _AlBoxes()],
            LayoutToGraphics().dispatch,
            WidgetToGraphics(font_ubuntu_monospace_regular_20;
                             measure = _al_measure).dispatch)))
        output = print_document(renderer, AnchoredLayout(content, Any[note])).output

        # Beside the *second* box — at the origin is what an unresolved target
        # looks like, and it is indistinguishable from a real placement unless
        # the assertion says which box.
        positions = _al_positions(output)
        @test length(positions) == 2
        @test positions[2] == (40, 30)

        # A reference the content cannot place is still not an error.
        stray = AnchoredEntry(WidgetLabel(Point2D(0, 0), "note");
                              reference = @reference(content, children[9]),
                              placement = :right)
        strayed = print_document(renderer, AnchoredLayout(content, Any[stray])).output
        @test _al_positions(strayed)[2] == (0, 0)
    end

    @testset "a bounded region is what placement respects" begin
        content = _al_label("x")
        renderer = _al_renderer()
        target = print_document(renderer, content).output
        note = AnchoredEntry(WidgetLabel(Point2D(0, 0), "long annotation");
                             target = target, placement = :right)
        # 200 wide leaves no room on the right for a 150-wide annotation past a
        # 10-wide box, so it goes to the left and is clamped into the region.
        layout = AnchoredLayout(content, Any[note]; bounding_width = 200, bounding_height = 40)
        output = print_document(renderer, layout).output
        @test (Int(output.w[]), Int(output.h[])) == (200, 40)
        x, _ = _al_positions(output)[2]
        @test 0 <= x <= 200
    end

end
end
