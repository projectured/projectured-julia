# The graph drawing follows the scales of the appearance: the box of a node, the
# line of an edge and the border of a highlight take the values of the scaled
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
    highlighted, box = plain.rects[1], plain.rects[2]
    # The box is the vertex and the padding of 8 on each side. The drawing moves
    # the layout right and down by the padding, 8. The highlight paints the border
    # of its box, 3 wide, and the box keeps its size: no ring.
    @test length(plain.rects) == 2
    @test (box.x, box.y, box.w, box.h) == (10, 100, 96, 46)
    @test (highlighted.x, highlighted.y, highlighted.w, highlighted.h) == (10, 10, 96, 46)
    @test box.border_width == 2
    @test highlighted.border_width == 3
    @test is_color_equal(box.color, get_theme_value(GraphTheme(), :node_fill))
    @test is_color_equal(highlighted.border_color, get_theme_value(GraphTheme(), :highlight))
    @test plain.lines[1].width == 2
    @test plain.lines[1].arrow_size == 10
    # The line and the arrowhead of an edge are almost black, the color of a
    # quiet text. The border of a box is the strong line of a card.
    @test is_color_equal(plain.lines[1].color, resolve_theme_color(ColorRole(:text_muted), Appearance()))
    @test is_color_equal(box.border_color, resolve_theme_color(ColorRole(:border_strong), Appearance()))

    theme = get_scaled_theme!(Appearance(spacing_scale = 2.0, line_scale = 2.0,
                                         control_scale = 1.5), GraphTheme)
    scaled = draw(theme)
    highlighted, box = scaled.rects[1], scaled.rects[2]
    # Scaled, the margin is the padding, 16.
    @test (box.x, box.y, box.w, box.h) == (10, 100, 112, 62)
    @test box.border_width == 4
    @test highlighted.border_width == 6
    @test scaled.lines[1].width == 4
    @test scaled.lines[1].arrow_size == 15
    # The extent reaches the box of the lower vertex: its bottom, 130, moved by the
    # margin, and the padding.
    @test Int(plain.canvas.h[]) == 8 + 130 + 8
    @test Int(scaled.canvas.h[]) == 16 + 130 + 16
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
