# The graph drawing follows the scales of the appearance: the box of a node, the
# line of an edge and the ring of a highlight take the values of the scaled
# `GraphTheme`, and a drawing with no theme has the default values.

function test_graph_theme()
@testset "the graph drawing follows the scales of the appearance" begin
    # The vertices hold no content, so the drawing prints no child.
    a, b = GraphVertex(nothing), GraphVertex(nothing)
    edge = GraphEdge(a, b; directed = true)
    function draw(theme)
        layout = GraphLayout(; vertex_layouts = CellVector(Any[VertexLayout(a, 10, 10, 80, 30),
                                                              VertexLayout(b, 10, 100, 80, 30)]),
                               edge_layouts = CellVector(Any[EdgeLayout(edge, [(50, 40), (50, 100)])]),
                               highlight_vertex = a)
        canvas = print_document(GraphLayoutToGraphicsCanvas(; theme), layout).output
        elements = [canvas.elements[i] for i in 1:length(canvas.elements)]
        (rects = filter(e -> e isa GraphicsRect, elements),
         lines = filter(e -> e isa GraphicsPolyline, elements), canvas)
    end

    plain = draw(nothing)
    ring, box = plain.rects[1], plain.rects[2]
    # The box is the vertex and the padding of 8 on each side; the ring is 3
    # outside it and 3 wide.
    @test (box.x, box.y, box.w, box.h) == (2, 2, 96, 46)
    @test box.border_width == 2
    @test is_color_equal(box.color, get_theme_value(GraphTheme(), :node_fill))
    @test (ring.x, ring.w) == (-4, 108)
    @test is_color_equal(ring.color, get_theme_value(GraphTheme(), :highlight))
    @test plain.lines[1].width == 2
    @test plain.lines[1].arrow_size == 10

    theme = get_scaled_theme!(Appearance(spacing_scale = 2.0, line_scale = 2.0,
                                         control_scale = 1.5), GraphTheme)
    scaled = draw(theme)
    ring, box = scaled.rects[1], scaled.rects[2]
    @test (box.x, box.y, box.w, box.h) == (-6, -6, 112, 62)
    @test box.border_width == 4
    @test (ring.x, ring.w) == (-6 - 12, 112 + 24)
    @test scaled.lines[1].width == 4
    @test scaled.lines[1].arrow_size == 15
    # The extent reaches the ring of the lower box: its bottom, 130, and the
    # padding, the gap and the width of the ring.
    @test Int(plain.canvas.h[]) == 130 + 8 + 3 + 3
    @test Int(scaled.canvas.h[]) == 130 + 16 + 6 + 6
end

@testset "a theme color reaches the drawing" begin
    a = GraphVertex(nothing)
    layout = GraphLayout(; vertex_layouts = CellVector(Any[VertexLayout(a, 0, 0, 10, 10)]),
                           edge_layouts = CellVector(Any[]))
    theme = GraphTheme(node_fill = color_black)
    canvas = print_document(GraphLayoutToGraphicsCanvas(; theme), layout).output
    @test is_color_equal(canvas.elements[1].color, color_black)
end
end
