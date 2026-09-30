
const _gctx = PrinterContext

function test_graph_projection()

@testset "the engine a caller gets when it names none" begin
    # With nothing registered, the deferred engine is the force-directed engine
    # of this package, for a graph of any size.
    @test resolve_layout_engine(DeferredLayout(), 5) isa FruchtermanReingoldLayout
    @test resolve_layout_engine(DeferredLayout(), 500) isa FruchtermanReingoldLayout
    @test resolve_layout_engine(GridEmbedding(), 500) isa GridEmbedding
    @test layout_engine_name(GridEmbedding()) === :grid
    @test layout_engine_name(FruchtermanReingoldLayout()) === :fruchterman_reingold

    # And the choice is made per layout, so a registered engine takes over.
    small = [GraphVertex(JsonString("v$i")) for i in 1:5]
    small_graph = GraphGraph(small, [GraphEdge(small[i], small[i+1]) for i in 1:4])
    small_sizes = Dict(objectid(v) => (40, 20) for v in small)
    direct, _ = layout_graph(FruchtermanReingoldLayout(), small_graph, small_sizes, [])
    deferred, _ = layout_graph(DeferredLayout(), small_graph, small_sizes, [])
    @test deferred == direct
    register_layout_engine!((; orthogonal = false) -> GridEmbedding())
    try
        @test resolve_layout_engine(DeferredLayout(), 5) isa GridEmbedding
    finally
        register_layout_engine!(nothing)
    end
    @test resolve_layout_engine(DeferredLayout(), 5) isa FruchtermanReingoldLayout
end

@testset "a layout says which engine drew it" begin
    # A view cannot tell a reader what it is looking at, and a test cannot assert
    # that the choice went the way it should have, unless the layout carries the
    # answer. It matters most for the engine that decides late.
    made = [GraphVertex(JsonString("v$i")) for i in 1:3]
    graph = GraphGraph(made, [GraphEdge(made[1], made[2])])
    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))

    for (engine, name) in ((GridEmbedding(), :grid),
                           (FruchtermanReingoldLayout(), :fruchterman_reingold),
                           (DeferredLayout(), :fruchterman_reingold))
        layout = print_document(GraphGraphToGraphLayout(engine), content, graph, _gctx()).output
        @test layout.engine === name
    end
end

@testset "edge graphics primitives" begin
    # Polyline construct + hit-test.
    pl = GraphicsPolyline([(0, 0), (10, 0), (10, 10)]; color = color_black,
                          width=2, end_arrow=true, arrow_size=8)
    @test length(pl.points) == 3
    @test pl.end_arrow == true
    @test is_point_near_polyline(pl.points, 5, 0, 3)       # on the first segment
    @test is_point_near_polyline(pl.points, 10, 5, 3)      # on the second segment
    @test !is_point_near_polyline(pl.points, 50, 50, 3)    # far away

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
    head = build_polyline_arrowhead([(0, 0), (10, 0)], 8)
    @test length(head) == 3
    @test head[1] == (10.0, 0.0)                        # tip at the end point
    # Base vertices straddle the line, `size` back from the tip.
    @test all(v -> v[1] < 10.0, head[2:3])

    # No-segment cases return empty.
    @test isempty(build_polyline_arrowhead([(0, 0)], 8))
end

@testset "GridEmbedding" begin
    v1 = GraphVertex(JsonString("a"))
    v2 = GraphVertex(JsonString("b"))
    v3 = GraphVertex(JsonString("c"))
    g = GraphGraph([v1, v2, v3], [GraphEdge(v1, v2), GraphEdge(v2, v3)])
    sizes = Dict(objectid(v1) => (40, 20),
                 objectid(v2) => (60, 30),
                 objectid(v3) => (50, 25))
    engine = GridEmbedding(; node_sep=10, rank_sep=10)
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

@testset "an extent bounds the placement instead of letting it grow" begin
    # The grid used to grow with the graph: 17 columns of full-width nodes for a
    # network, several thousand pixels across, running off whatever pane it was
    # given. A caller that knows how much room it has says so, and the placement
    # is scaled into that room rather than clipped by it.
    vertices = [GraphVertex(JsonString("v$i")) for i in 1:40]
    graph = GraphGraph(vertices, GraphEdge[])
    sizes = Dict(objectid(v) => (120, 40) for v in vertices)
    engine = GridEmbedding()

    unbounded, _ = layout_graph(engine, graph, sizes, [])
    right = maximum(box[1] + box[3] for box in values(unbounded))
    @test right > 800                       # this is the problem being fixed

    bounded, _ = layout_graph(engine, graph, sizes, []; extent = (800, 600), border = 10)
    for box in values(bounded)
        @test box[1] >= 10
        @test box[2] >= 10
        @test box[1] + box[3] <= 790
        @test box[2] + box[4] <= 590
    end
    # Scaled, not shrunk: a box keeps the size it was measured at, exactly as
    # OMNeT++'s own rescale moves centres and never sizes.
    @test all(box[3] == 120 && box[4] == 40 for box in values(bounded))

    # A handful of vertices goes on a ring rather than a grid, and the ring is
    # spread over the extent too.
    few = [GraphVertex(JsonString("v$i")) for i in 1:6]
    ring_graph = GraphGraph(few, GraphEdge[])
    ring_sizes = Dict(objectid(v) => (60, 30) for v in few)
    ring, _ = layout_graph(engine, ring_graph, ring_sizes, []; extent = (400, 400))
    ys = [box[2] for box in values(ring)]
    xs = [box[1] for box in values(ring)]
    @test length(unique(ys)) > 2            # not rows: a ring has many distinct y
    @test maximum(xs) + 60 <= 400
    @test maximum(ys) + 30 <= 400

    # Naming a column count asks for a grid, and it is answered with one even
    # when the graph is small enough for a ring. Answering with a ring would
    # drop the request without saying so.
    columned, _ = layout_graph(GridEmbedding(columns = 2), ring_graph, ring_sizes, [];
                               extent = (400, 400))
    @test length(unique(box[1] for box in values(columned))) == 2
end

@testset "a placement is deterministic" begin
    vertices = [GraphVertex(JsonString("v$i")) for i in 1:12]
    graph = GraphGraph(vertices, [GraphEdge(vertices[i], vertices[i+1]) for i in 1:11])
    sizes = Dict(objectid(v) => (60, 30) for v in vertices)
    engine = GridEmbedding()
    first_run, first_routes = layout_graph(engine, graph, sizes, []; extent = (500, 400))
    second_run, second_routes = layout_graph(engine, graph, sizes, []; extent = (500, 400))
    @test first_run == second_run
    @test first_routes == second_routes
end

@testset "a constraint is honoured or refused, never dropped" begin
    v1 = GraphVertex(JsonString("a"))
    v2 = GraphVertex(JsonString("b"))
    graph = GraphGraph([v1, v2], [GraphEdge(v1, v2)])
    sizes = Dict(objectid(v1) => (40, 20), objectid(v2) => (60, 30))
    engine = GridEmbedding()

    # A pin is where the caller put it, and the extent does not move it.
    pin = GraphConstraint(v1, :pin, (300, 200))
    positions, _ = layout_graph(engine, graph, sizes, [pin]; extent = (500, 400))
    @test positions[objectid(v1)] == (300, 200, 40, 20)

    # A fixed size overrides what was measured.
    fixed = GraphConstraint(v2, :fixed_size, (25, 15))
    positions, _ = layout_graph(engine, graph, sizes, [fixed])
    @test positions[objectid(v2)][3] == 25
    @test positions[objectid(v2)][4] == 15

    # A kind the engine does not implement is refused by name, and the message
    # says what it does implement. Accepting and dropping it would draw a picture
    # a caller cannot tell from one that was never constrained.
    for kind in (:cluster, :align, :same_rank, :min_separation)
        err = try
            layout_graph(engine, graph, sizes, [GraphConstraint(v1, kind, nothing)])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin(string(kind), err.msg)
        @test occursin(":pin", err.msg)
    end

    # And so is a kind nothing knows about.
    @test_throws ArgumentError layout_graph(engine, graph, sizes,
                                            [GraphConstraint(v1, :handstand, nothing)])
    @test get_supported_constraint_kinds(GridEmbedding()) == (:pin, :fixed_size)
end

@testset "GraphToGraphLayout sizing + reactivity" begin
    # A JsonString vertex whose projected size we can measure.
    v = GraphVertex(JsonString("hello"))
    g = GraphGraph([v], GraphEdge[])

    # Content recursion: Json → Syntax → Text → Graphics (the mixed pipeline).
    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    stage = GraphGraphToGraphLayout(GridEmbedding())
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

    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    graph_stages = ChainingProjection(
        GraphGraphToGraphLayout(GridEmbedding()),
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

@testset "GraphToGraphics is the chain of the two stages" begin
    @test :GraphLayoutToGraphics ∉ names(ProjecturedGraph.GraphModule)
    v1 = GraphVertex(JsonString("a"))
    v2 = GraphVertex(JsonString("b"))
    g = GraphGraph([v1, v2], [GraphEdge(v1, v2; directed=true)])
    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))

    chain = GraphToGraphics()
    @test chain isa ChainingProjection
    @test chain.projections[1] isa GraphGraphToGraphLayout
    @test chain.projections[1].engine isa GridEmbedding
    @test chain.projections[2] isa GraphLayoutToGraphicsCanvas
    canvas = print_document(NestingProjection(chain; recursion=content), g).output
    @test canvas isa GraphicsCanvas
    elems = collect(canvas.elements)
    @test any(e -> e isa GraphicsPolyline && e.end_arrow, elems)
    @test count(e -> e isa GraphicsRect, elems) >= 2

    # The engine and the keywords of the first stage pass through.
    chain = GraphToGraphics(FruchtermanReingoldLayout(); extent = (400, 300), border = 5)
    @test chain.projections[1].engine isa FruchtermanReingoldLayout
    @test chain.projections[1].extent == (400, 300)
    @test chain.projections[1].border == 5
end

@testset "selection descends into vertex content" begin
    g = make_graph_document_example()
    proj = make_graph_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    iomap = print_document(proj, g)
    @test iomap.output isa GraphicsCanvas

    # A selection into the first vertex's content maps forward to a non-nothing
    # output selection (the cursor reaches the graphics layer).
    set_selection!(g, @reference(g, vertices[1]))
    # Forward mapping of the stage-1 projection: vertices[i] ↔ vertex_layouts[i].vertex.
    stage = GraphGraphToGraphLayout(GridEmbedding())
    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    s1 = print_document(stage, content, g, _gctx())
    fwd = map_reference_forward(stage, s1, @reference(g, vertices[1]))
    @test fwd !== nothing
    back = map_reference_backward(stage, s1, fwd)
    @test back !== nothing
    # `back` is now typed; compare navigation shape.
    @test is_reference_equal(strip_reference_types(back), strip_reference_types(@reference(g, vertices[1])))
end

@testset "a whole vertex maps forward to the box it was drawn as" begin
    # Nothing *selects* a vertex — the cursor lives in its content — but
    # something has to be able to point at one, because that is what an
    # annotation anchored beside a node asks for.
    g = make_graph_document_example()
    proj = make_graph_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    iomap = print_document(proj, g)

    for i in 1:length(g.vertices)
        fwd = map_reference_forward(iomap.projection, iomap, @reference(g, vertices[i]))
        @test fwd !== nothing
        # The reference is into the drawing's own elements, so it evaluates
        # against the output — a reference relative to anything else would be
        # unusable by whoever asked.
        node = evaluate_reference(iomap.output, fwd)
        @test node isa GraphicsRect
    end

    # Distinct vertices are distinct boxes: the index really is per vertex.
    boxes = [evaluate_reference(iomap.output,
                                map_reference_forward(iomap.projection, iomap,
                                                      @reference(g, vertices[i])))
             for i in 1:length(g.vertices)]
    @test length(unique(objectid.(boxes))) == length(boxes)
end

@testset "a point maps to the vertex drawn at it, and on into its content" begin
    # The hit test is the one a click takes, so a point maps to the part that a
    # click there reaches, and the chain carries it back to the graph.
    g = make_graph_document_example()
    proj = make_graph_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    iomap = print_document(proj, g)
    layout = iomap.child_iomap.step_iomaps[1][].output
    _steps(reference) = collect(get_reference_steps(strip_reference_types(reference)))
    _content(i) = _steps(@reference(g, vertices[i].content))

    for i in 1:length(g.vertices)
        vl = layout.vertex_layouts[i]
        middle = PointReferenceStep(Int(vl.x) + Int(vl.w) ÷ 2, Int(vl.y) + Int(vl.h) ÷ 2)
        back = map_reference_backward(proj, iomap, middle)
        @test back !== nothing
        back === nothing && continue
        # The middle of a box is on its content, so the point reaches a part inside it.
        steps = _steps(back)
        @test length(steps) > length(_content(i)) && steps[1:length(_content(i))] == _content(i)
    end
    # The corner of the second box is on the opening brace of its content, a part that
    # the object printed: the object's own introduced step names it, at the object.
    vl = layout.vertex_layouts[2]
    corner = map_reference_backward(proj, iomap, PointReferenceStep(Int(vl.x) + 3, Int(vl.y) + 3))
    corner_steps = _steps(corner)
    @test corner_steps[1:length(_content(2))] == _content(2)
    brace = corner_steps[length(_content(2)) + 1]
    @test brace isa ProjectionReferenceStep
    @test get_reference_head(strip_reference_types(brace.output_path)) == FieldReferenceStep("open")
    @test map_reference_backward(proj, iomap, PointReferenceStep(5000, 5000)) === nothing
end

@testset "the natural renderer draws a graph as a diagram" begin
    # A diagram is one of the things "almost any document" has to cover, and the
    # vertex content is where it matters: the graph stages take the natural
    # renderer as their recursion, so a node may be anything the renderer knows —
    # here a widget column of an icon-less label pair, which is what a module in a
    # network diagram is.
    renderer = NaturalToGraphics(measure = FixedMeasure(10, 15, 5, 0))
    node(name) = GraphVertex(VerticalLayout(Any[WidgetLabel(name)]; gap = 2))
    a, b = node("source"), node("sink")
    graph = GraphGraph(Any[a, b], Any[GraphEdge(a, b)])

    output = print_document(renderer, graph).output
    @test output isa GraphicsCanvas
    # A diagram, not a syntax tree: the vertices are placed boxes and the edge is
    # drawn between them. Reflected `GraphGraph(…)` text would mean the `Any`
    # fallback caught it.
    elements = collect(output.elements)
    @test count(e -> e isa GraphicsRect, elements) >= 2
    @test any(e -> e isa GraphicsPolyline, elements)

    # The widget vertex really went through the widget renderer.
    text = String[]
    pending, seen = Any[output], Set{UInt64}()
    while !isempty(pending)
        n = pop!(pending)
        n isa AbstractCell && (n = n[])
        n === nothing && continue
        objectid(n) in seen && continue
        push!(seen, objectid(n))
        n isa GraphicsCanvas ? append!(pending, collect(n.elements)) :
            n isa GraphicsText && push!(text, string(n.text))
    end
    @test "source" in text
    @test "sink" in text
end

@testset "a graph canvas declares the extent of its layout" begin
    # A graph used to report 0x0 no matter how big it was, so every container
    # that asked how much room it needed reserved none and the graph drew over
    # whatever followed it. Callers worked around it by ESTIMATING a height from
    # the node count — a guess that cannot tell a tall thin chain from a wide
    # flat mesh, and the tall chain overlapped the prose under it.
    a, b = GraphVertex("a"), GraphVertex("b")
    edge = GraphEdge(a, b)
    layout = GraphLayout(; vertex_layouts = CellVector(Any[VertexLayout(a, 10, 10, 80, 30),
                                                          VertexLayout(b, 10, 500, 80, 30)]),
                           edge_layouts   = CellVector(Any[EdgeLayout(edge, [(50, 40), (50, 500)])]))
    canvas = print_document(GraphLayoutToGraphicsCanvas(), layout).output
    # Tall enough for the lower box (y 500 + h 30) plus the box padding and ring.
    @test Int(canvas.h[]) >= 530
    @test Int(canvas.w[]) >= 90

    # And it FOLLOWS the layout rather than being computed once: a topology
    # exists only after a run has built the network, so a graph is routinely
    # empty when first drawn and gets its nodes afterwards.
    getfield(layout.vertex_layouts[2], :y)[] = 900
    @test Int(canvas.h[]) >= 930

    # A route that bows outside every box it connects still counts.
    push!(layout.edge_layouts, EdgeLayout(edge, [(50, 40), (4000, 40)]))
    @test Int(canvas.w[]) >= 4000
end

end # test_graph_projection
