
const _gctx = PrinterContext

function test_graph()

@testset "edge graphics primitives" begin
    # Polyline construct + hit-test.
    pl = GraphicsPolyline([(0, 0), (10, 0), (10, 10)], color_black;
                          width=2, end_arrow=true, arrow_size=8)
    @test length(pl.points) == 3
    @test pl.end_arrow == true
    @test point_near_polyline(pl.points, 5, 0, 3)       # on the first segment
    @test point_near_polyline(pl.points, 10, 5, 3)      # on the second segment
    @test !point_near_polyline(pl.points, 50, 50, 3)    # far away

    # Spline tessellation passes through the input points (catmull-rom) and is a
    # superset polyline.
    tess = tessellate_spline([(0, 0), (5, 5), (10, 0)], :catmullrom, 4)
    @test length(tess) > 3
    @test tess[1] == (0.0, 0.0)
    @test tess[end] == (10.0, 0.0)

    # Bezier tessellation: one cubic span (p0,c1,c2,p1).
    bez = tessellate_spline([(0, 0), (0, 10), (10, 10), (10, 0)], :bezier, 6)
    @test bez[1] == (0.0, 0.0)
    @test bez[end] == (10.0, 0.0)

    # Arrowhead geometry: tip is the last point, three vertices returned.
    head = polyline_arrowhead([(0, 0), (10, 0)], 8)
    @test length(head) == 3
    @test head[1] == (10.0, 0.0)                        # tip at the end point
    # Base vertices straddle the line, `size` back from the tip.
    @test all(v -> v[1] < 10.0, head[2:3])

    # No-segment cases return empty.
    @test isempty(polyline_arrowhead([(0, 0)], 8))
end

@testset "FallbackLayoutEngine" begin
    v1 = GraphVertex(JsonString("a"))
    v2 = GraphVertex(JsonString("b"))
    v3 = GraphVertex(JsonString("c"))
    g = GraphGraph([v1, v2, v3], [GraphEdge(v1, v2), GraphEdge(v2, v3)])
    sizes = Dict(objectid(v1) => (40, 20),
                 objectid(v2) => (60, 30),
                 objectid(v3) => (50, 25))
    engine = FallbackLayoutEngine(; node_sep=10, rank_sep=10)
    positions, routes = layout_graph(engine, g, sizes, [])

    @test length(positions) == 3
    @test haskey(positions, objectid(v1))
    # Sizes are honoured.
    @test positions[objectid(v1)][3] == 40
    @test positions[objectid(v2)][4] == 30

    # Placed rectangles are pairwise disjoint.
    boxes = collect(values(positions))
    for i in 1:length(boxes), j in (i+1):length(boxes)
        a = boxes[i]; b = boxes[j]
        disjoint = a[1] + a[3] <= b[1] || b[1] + b[3] <= a[1] ||
                   a[2] + a[4] <= b[2] || b[2] + b[4] <= a[2]
        @test disjoint
    end

    # Routes connect the right boxes: each route endpoint lies on its box border.
    @test length(routes) == 2
    for (i, edge) in enumerate(g.edges)
        r = routes[objectid(edge)]
        @test length(r) == 2
    end
end

@testset "GraphToGraphLayout sizing + reactivity" begin
    # A JsonString vertex whose projected size we can measure.
    v = GraphVertex(JsonString("hello"))
    g = GraphGraph([v], GraphEdge[])

    # Content recursion: Json → Syntax → Text → Graphics (the mixed pipeline).
    content = make_mixed_projection_example(measure=(t, f) -> (length(t) * 10, 20))
    stage = GraphGraphToGraphLayout(FallbackLayoutEngine())
    iomap = print_document(stage, content, g, _gctx())
    layout = iomap.output
    @test layout isa GraphLayout
    @test length(layout.vertex_layouts) == 1
    vl = layout.vertex_layouts[1]
    @test vl isa VertexLayout
    # The size came from the projected content (non-zero).
    @test vl.w > 0
    @test vl.h > 0
    w_before = vl.w

    # A content edit that grows the string grows the vertex size reactively.
    getfield(v, :content)[].value = "hello world!!!"
    vl2 = layout.vertex_layouts[1]
    @test vl2.w > w_before
end

@testset "GraphLayoutToGraphics printer" begin
    v1 = GraphVertex(JsonString("a"))
    v2 = GraphVertex(JsonString("b"))
    g = GraphGraph([v1, v2], [GraphEdge(v1, v2; directed=true)])

    content = make_mixed_projection_example(measure=(t, f) -> (length(t) * 10, 20))
    graph_stages = ChainingProjection(
        GraphGraphToGraphLayout(FallbackLayoutEngine()),
        GraphLayoutToGraphicsCanvas(),
    )
    proj = NestingProjection(graph_stages; recursion=content)
    iomap = print_document(proj, g)
    canvas = iomap.output
    @test canvas isa GraphicsCanvas

    elems = collect(canvas.elements)
    # At least one directed edge polyline with an end arrow.
    edges = filter(e -> e isa GraphicsPolyline, elems)
    @test !isempty(edges)
    @test any(e -> e.end_arrow, edges)
    # Node boxes are rounded rects.
    @test count(e -> e isa GraphicsRect, elems) >= 2
    # Content canvases are nested inside.
    @test count(e -> e isa GraphicsCanvas, elems) >= 2
end

@testset "selection descends into vertex content" begin
    g = make_graph_document_example()
    proj = make_graph_projection_example(measure=(t, f) -> (length(t) * 10, 20))
    iomap = print_document(proj, g)
    @test iomap.output isa GraphicsCanvas

    # A selection into the first vertex's content maps forward to a non-nothing
    # output selection (the cursor reaches the graphics layer).
    set_selection!(g, @reference(g, vertices[1]))
    # Forward mapping of the stage-1 projection: vertices[i] ↔ vertex_layouts[i].vertex.
    stage = GraphGraphToGraphLayout(FallbackLayoutEngine())
    content = make_mixed_projection_example(measure=(t, f) -> (length(t) * 10, 20))
    s1 = print_document(stage, content, g, _gctx())
    fwd = map_reference_forward(stage, s1, @reference(g, vertices[1]))
    @test fwd !== nothing
    back = map_reference_backward(stage, s1, fwd)
    @test back !== nothing
    # `back` is now typed; compare navigation shape.
    @test is_reference_equal(strip_reference_types(back), strip_reference_types(@reference(g, vertices[1])))
end

end # test_graph
