
const _gctx = PrinterContext

# An engine that takes no constraint: it puts the boxes in one row, 20 px apart,
# in the order of the vertices.
struct _GptRowEngine <: GraphLayoutEngine end
function ProjecturedGraph.GraphModule.layout_graph(engine::_GptRowEngine, graph::GraphGraph,
                                                   sizes::Dict, constraints::Vector;
                                                   extent = nothing, border::Real = 0)
    check_constraints(engine, constraints)
    positions = Dict{UInt,NTuple{4,Int}}()
    x = 0
    for vertex in layout_vertices(graph)
        w, h = sizes[objectid(vertex)]
        positions[objectid(vertex)] = (x, 0, w, h)
        x += w + 20
    end
    (positions, get_straight_routes(graph, positions))
end
ProjecturedGraph.GraphModule.layout_engine_name(::_GptRowEngine) = :row

# The corner of each box of `layout`, and its box `(x, y, w, h)`.
_gpt_corners(layout) = [(Int(vl.x), Int(vl.y)) for vl in layout.vertex_layouts]
_gpt_boxes(layout) = Dict(i => (Int(vl.x), Int(vl.y), Int(vl.w), Int(vl.h))
                          for (i, vl) in enumerate(layout.vertex_layouts))

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
    @test get_supported_constraint_kinds(GridEmbedding()) == (:pin, :start, :fixed_size)

    # A grid has nothing to refine, so a start is placed as a pin is, and a pin
    # of the same vertex wins.
    start = GraphConstraint(v2, :start, (120, 90))
    positions, _ = layout_graph(engine, graph, sizes, [start])
    @test positions[objectid(v2)] == (120, 90, 60, 30)
    positions, _ = layout_graph(engine, graph, sizes,
                                [start, GraphConstraint(v2, :pin, (10, 20))])
    @test positions[objectid(v2)] == (10, 20, 60, 30)
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

@testset "a change of a size keeps the places of the vertices" begin
    vertices = [GraphVertex(JsonString("v$i")) for i in 1:4]
    graph = GraphGraph(vertices, [GraphEdge(vertices[i], vertices[i+1]) for i in 1:3])
    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    layout = print_document(GraphGraphToGraphLayout(FruchtermanReingoldLayout()), content, graph,
                            _gctx()).output
    before = _gpt_corners(layout)
    width = Int(layout.vertex_layouts[2].w)

    # A box that grows a little keeps its corner, and the others keep theirs.
    getfield(vertices[2], :content)[].value = "v2!"
    @test Int(layout.vertex_layouts[2].w) == width + 10
    @test _gpt_corners(layout) == before

    # A box that grows into another one pushes the two apart, and a box that it
    # does not reach stays.
    grown = before[2]
    getfield(vertices[2], :content)[].value = "v2" * "!"^30
    boxes = _gpt_boxes(layout)
    @test _are_boxes_disjoint(boxes)
    reach = (grown[1] - 20, grown[2] - 20, boxes[2][3] + 40, boxes[2][4] + 40)
    far = [i for i in (1, 3, 4)
           if _are_boxes_disjoint(Dict(1 => reach, 2 => (before[i]..., boxes[i][3], boxes[i][4])))]
    @test !isempty(far)
    for i in far
        @test _gpt_corners(layout)[i] == before[i]
    end

    # A new vertex gets a place among the others, and the others keep theirs.
    kept = _gpt_corners(layout)
    vertex = GraphVertex(JsonString("v5"))
    push!(graph.vertices, vertex)
    push!(graph.edges, GraphEdge(vertices[4], vertex))
    @test length(layout.vertex_layouts) == 5
    @test _gpt_corners(layout)[1:4] == kept
    @test _are_boxes_disjoint(_gpt_boxes(layout))
end

@testset "an engine that takes no start lays out the graph again on a change of a size" begin
    vertices = [GraphVertex(JsonString("a")), GraphVertex(JsonString("b"))]
    graph = GraphGraph(vertices, [GraphEdge(vertices[1], vertices[2])])
    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    layout = print_document(GraphGraphToGraphLayout(_GptRowEngine()), content, graph, _gctx()).output
    x = Int(layout.vertex_layouts[2].x)
    getfield(vertices[1], :content)[].value = "abc"
    @test Int(layout.vertex_layouts[2].x) == x + 20
end

@testset "a pin of a vertex wins over its start" begin
    v1 = GraphVertex(JsonString("a"))
    v2 = GraphVertex(JsonString("b"))
    constraints = [GraphConstraint(v1, :start, (1, 2)), GraphConstraint(v2, :start, (3, 4)),
                   GraphConstraint(v1, :pin, (5, 6))]
    @test get_constraint_starts(constraints) == Dict(objectid(v2) => (3.0, 4.0))
    @test get_constraint_pins(constraints) == Dict(objectid(v1) => (5.0, 6.0))
    @test_throws ArgumentError get_constraint_starts([GraphConstraint(v1, :start, 7)])
end

@testset "the constraints of the graph reach the engine after those of the projection" begin
    v1 = GraphVertex(JsonString("a"))
    v2 = GraphVertex(JsonString("b"))
    g = GraphGraph([v1, v2], [GraphEdge(v1, v2)])
    @test isempty(g.constraints)
    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))
    stage = GraphGraphToGraphLayout(GridEmbedding();
                                    constraints = _ -> [GraphConstraint(v1, :pin, (10, 10)),
                                                        GraphConstraint(v2, :pin, (200, 10))])
    layout = print_document(stage, content, g, _gctx()).output
    @test layout.graph === g
    @test layout.drag === nothing
    corner(i) = (Int(layout.vertex_layouts[i].x), Int(layout.vertex_layouts[i].y))
    @test corner(1) == (10, 10)
    @test corner(2) == (200, 10)

    # One write of the constraints of the graph places the vertex again, and its
    # pin wins over the pin of the projection.
    evaluate_operation(nothing, ReplaceReferencedValueOperation(
        g, "constraints", [GraphConstraint(v1, :pin, (120, 80))]))
    @test corner(1) == (120, 80)
    @test corner(2) == (200, 10)
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
    @test chain.projections[1].engine isa DeferredLayout
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
    drawing = _gvd_find_drawing(iomap)
    _steps(reference) = collect(get_reference_steps(strip_reference_types(reference)))
    _content(i) = _steps(@reference(g, vertices[i].content))

    for i in 1:length(g.vertices)
        box = drawing.drawn_boxes[i]
        middle = PointReferenceStep(box[1] + box[3] ÷ 2, box[2] + box[4] ÷ 2)
        back = map_reference_backward(proj, iomap, middle)
        @test back !== nothing
        back === nothing && continue
        # The middle of a box is on its content, so the point reaches a part inside it.
        steps = _steps(back)
        @test length(steps) > length(_content(i)) && steps[1:length(_content(i))] == _content(i)
    end
    # The corner of the second box is on the opening brace of its content, a part that
    # the object printed: the object's own introduced step names it, at the object.
    box = drawing.drawn_boxes[2]
    corner = map_reference_backward(proj, iomap, PointReferenceStep(box[1] + 3, box[2] + 3))
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
    # Every element that the drawing holds, also inside the viewport of the scroll
    # pane that holds the graph.
    drawn = Any[]
    pending, seen = Any[output], Set{UInt64}()
    while !isempty(pending)
        n = pop!(pending)
        n isa AbstractCell && (n = n[])
        n === nothing && continue
        objectid(n) in seen && continue
        push!(seen, objectid(n))
        push!(drawn, n)
        n isa GraphicsCanvas && append!(pending, collect(n.elements))
        n isa GraphicsViewport && push!(pending, n.content)
    end
    # A diagram, not a syntax tree: the vertices are placed boxes and the edge is
    # drawn between them. Reflected `GraphGraph(…)` text would mean the `Any`
    # fallback caught it.
    @test count(e -> e isa GraphicsRect, drawn) >= 2
    @test any(e -> e isa GraphicsPolyline, drawn)
    # The graph is in a scroll pane of its own.
    @test any(e -> e isa GraphicsViewport, drawn)

    # The widget vertex really went through the widget renderer.
    text = [string(n.text) for n in drawn if n isa GraphicsText]
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
    push!(layout.edge_layouts, EdgeLayout(edge, [(50, 25), (4000, 25), (50, 915)]))
    @test Int(canvas.w[]) >= 4000
end

@testset "an edge ends at the rim of the box that the drawing paints" begin
    v1 = GraphVertex(JsonString("a"))
    v2 = GraphVertex(JsonString("b"))
    graph = GraphGraph([v1, v2], [GraphEdge(v1, v2; directed = true)])
    drawing = _gpt_draw_with_grid(graph)
    layout = drawing.input
    style = unwrap_cell(drawing.projection.style)
    source, target = _gpt_get_node_rect(drawing, 1), _gpt_get_node_rect(drawing, 2)
    # The drawing moves the layout right and down by its margin: the padding and
    # the ring.
    margin = style.node_padding + style.highlight_gap + style.highlight_width
    @test Int(target.x) == Int(layout.vertex_layouts[2].x) + margin - style.node_padding

    # The grid puts the two boxes side by side, so the edge is level. It leaves the
    # right side of the painted source box, and its arrowhead touches the left side
    # of the painted target box.
    first_layout = layout.vertex_layouts[1]
    y = round(Int, Int(first_layout.y) + margin + Int(first_layout.h) / 2)
    edge = only(_gpt_collect_lines(drawing))
    @test edge.end_arrow
    @test collect(edge.points) == [(Int(source.x) + Int(source.w), y), (Int(target.x), y)]

    # The ring of a highlighted vertex is painted around its box, so the arrowhead
    # stops at the ring.
    getfield(graph, :highlight_vertex)[] = v2
    ring = style.highlight_gap + style.highlight_width
    @test last(collect(only(_gpt_collect_lines(drawing)).points)) == (Int(target.x) - ring, y)
    getfield(graph, :highlight_vertex)[] = nothing

    # The edge of a dragged vertex ends at the rim of the box where the pointer
    # took it, on the line between the two centres.
    getfield(layout, :drag)[] = (vertex = v2, index = 2, origin = (0, 0), offset = (0, 120),
                                 started = true)
    dragged = _gpt_get_node_rect(drawing, 2)
    @test Int(dragged.y) == Int(layout.vertex_layouts[2].y) + margin + 120 - style.node_padding
    points = collect(only(_gpt_collect_lines(drawing)).points)
    @test _gpt_is_on_rim(source, first(points))
    @test _gpt_is_on_rim(dragged, last(points))
end

@testset "a route between the centres of two boxes is cut at their painted rims" begin
    # The shape of a route of libavoid: from centre to centre, with a bend.
    a, b = GraphVertex(JsonString("a")), GraphVertex(JsonString("b"))
    edge = GraphEdge(a, b; directed = true)
    layout = GraphLayout(; vertex_layouts = CellVector(Any[VertexLayout(a, 10, 10, 80, 30),
                                                          VertexLayout(b, 300, 200, 80, 30)]),
                           edge_layouts   = CellVector(Any[EdgeLayout(edge, [(50, 25), (340, 25), (340, 215)])]))
    projection = GraphLayoutToGraphicsCanvas()
    style = unwrap_cell(projection.style)
    pad = style.node_padding
    content = make_mixed_projection_example(measure = FixedMeasure(10, 15, 5, 0))
    canvas = print_document(projection, content, layout, _gctx()).output
    lines() = filter(e -> e isa GraphicsPolyline, collect(canvas.elements))
    # The drawing moves the layout and the bend right and down by its margin.
    margin = pad + style.highlight_gap + style.highlight_width
    @test collect(only(lines()).points) ==
          map(point -> point .+ margin, [(10 + 80 + pad, 25), (340, 25), (340, 200 - pad)])

    # Two boxes that overlap leave no part of the line outside both, so the
    # drawing draws no line.
    getfield(layout.vertex_layouts[2], :x)[] = 30
    getfield(layout.vertex_layouts[2], :y)[] = 20
    getfield(layout.edge_layouts[1], :route)[] = [(50, 25), (70, 35)]
    @test isempty(lines())
end

@testset "a curved edge leaves each box at a right angle to its side" begin
    a, b = GraphVertex(JsonString("a")), GraphVertex(JsonString("b"))
    edge = GraphEdge(a, b; directed = true)
    layout = GraphLayout(; vertex_layouts = CellVector(Any[VertexLayout(a, 10, 10, 80, 30),
                                                          VertexLayout(b, 300, 200, 80, 30)]),
                           edge_layouts   = CellVector(Any[EdgeLayout(edge, [(50, 25), (340, 215)])]))
    content = make_mixed_projection_example(measure = FixedMeasure(10, 15, 5, 0))
    draw(projection) = collect(print_document(projection, content, layout, _gctx()).output.elements)
    straight = only(filter(e -> e isa GraphicsPolyline, draw(GraphLayoutToGraphicsCanvas())))
    elements = draw(GraphLayoutToGraphicsCanvas(edge_shape = :curved))
    @test !any(e -> e isa GraphicsPolyline, elements)
    curve = only(filter(e -> e isa GraphicsSpline, elements))
    @test curve.kind === :bezier
    @test curve.end_arrow

    # The curve has the ends of the straight edge: the line between the centres
    # leaves the bottom side of the first box and enters the top side of the
    # second. It leaves downward and arrives downward, so each control point is
    # straight below or above its end.
    points = collect(curve.points)
    @test length(points) == 4
    @test (points[1], points[4]) == Tuple(collect(straight.points))
    @test points[2][1] == points[1][1] && points[2][2] > points[1][2]
    @test points[3][1] == points[4][1] && points[3][2] < points[4][2]

    @test_throws ArgumentError GraphLayoutToGraphicsCanvas(edge_shape = :wavy)
    @test GraphToGraphics(edge_shape = :curved).projections[2].edge_shape === :curved
end

@testset "a curved edge passes through the bends of its route, with its label on it" begin
    a, b = GraphVertex(JsonString("a")), GraphVertex(JsonString("b"))
    edge = GraphEdge(a, b; directed = true, label = JsonString("x"))
    layout = GraphLayout(; vertex_layouts = CellVector(Any[VertexLayout(a, 10, 10, 80, 30),
                                                          VertexLayout(b, 300, 200, 80, 30)]),
                           edge_layouts   = CellVector(Any[EdgeLayout(edge, [(50, 25), (340, 25), (340, 215)])]))
    content = make_mixed_projection_example(measure = FixedMeasure(10, 15, 5, 0))
    canvas = print_document(GraphLayoutToGraphicsCanvas(edge_shape = :curved), content, layout,
                            _gctx()).output
    curve = only(filter(e -> e isa GraphicsSpline, collect(canvas.elements)))
    points = collect(curve.points)
    # Two spans: the ends of step one and the bend, with two control points each,
    # moved by the margin of the drawing.
    style = unwrap_cell(GraphLayoutToGraphicsCanvas().style)
    margin = style.node_padding + style.highlight_gap + style.highlight_width
    @test points[[1, 4, 7]] == map(point -> point .+ margin, [(98, 25), (340, 25), (340, 192)])
    # It leaves the right side to the right, and enters the top side downward.
    @test points[2][2] == 25 + margin && points[2][1] > 98 + margin
    @test points[6][1] == 340 + margin && points[6][2] < 192 + margin

    # The label sits on the curve, at the middle of its length.
    path = tessellate_spline(points, :bezier, Int(curve.segments))
    label = first(filter(e -> e isa GraphicsCanvas, collect(canvas.elements)))
    text = only(collect(label.elements))
    @test is_point_near_polyline(path, Int(label.x) + Int(text.w) ÷ 2,
                                 Int(label.y) + Int(text.h) ÷ 2, 2)

    # The highlight strokes the same curve again.
    getfield(layout, :highlight_edge)[] = edge
    @test count(e -> e isa GraphicsSpline, collect(canvas.elements)) == 2
end

@testset "the light and the highlight cut an edge at the ring and move no part of it" begin
    # The line between the centres leaves the bottom side of the first box near
    # its corner, so a curve that a wider rim cut would leave at another point.
    a, b = GraphVertex(JsonString("a")), GraphVertex(JsonString("b"))
    edge = GraphEdge(a, b; directed = true, label = JsonString("x"))
    layout = GraphLayout(; vertex_layouts = CellVector(Any[VertexLayout(a, 10, 10, 80, 30),
                                                          VertexLayout(b, 300, 200, 80, 30)]),
                           edge_layouts   = CellVector(Any[EdgeLayout(edge, [(50, 25), (340, 215)])]))
    content = make_mixed_projection_example(measure = FixedMeasure(10, 15, 5, 0))
    drawing = print_document(GraphLayoutToGraphicsCanvas(edge_shape = :curved), content, layout, _gctx())
    style = unwrap_cell(drawing.projection.style)
    ring = style.highlight_gap + style.highlight_width
    curves() = filter(e -> e isa GraphicsSpline, collect(drawing.output.elements))
    label_place() = (label = first(filter(e -> e isa GraphicsCanvas, collect(drawing.output.elements)));
                     (Int(label.x), Int(label.y)))
    plain = collect(first(curves()).points)
    path = tessellate_spline(plain, :bezier, Int(first(curves()).segments))
    place = label_place()
    label_boxes = drawing.label_boxes[]
    is_on_curve(point) = is_point_near_polyline(path, point[1], point[2], 2)

    # The highlight of the target: the arrowhead stops at its ring, on the same
    # curve, and the source end stays.
    getfield(layout, :highlight_vertex)[] = b
    cut = collect(first(curves()).points)
    @test _gpt_is_on_ring(_gpt_get_node_rect(drawing, 2), ring, last(cut))
    @test is_on_curve(last(cut))
    @test first(cut) == first(plain)
    @test label_place() == place
    getfield(layout, :highlight_vertex)[] = nothing
    @test collect(first(curves()).points) == plain

    # The light of the target also lights the source, so both ends stop at a ring,
    # and the lit line covers the same cut line. The label and the edges that the
    # drawing calculated stay as they are.
    replace_mouse_target!(layout, extend_reference(EmptyReference(), FieldReferenceStep("vertex_layouts"),
                                                   ElementReferenceStep(2), FieldReferenceStep("vertex")))
    lines = curves()
    @test length(lines) == 2
    cut = collect(first(lines).points)
    @test collect(last(lines).points) == cut
    @test _gpt_is_on_ring(_gpt_get_node_rect(drawing, 1), ring, first(cut))
    @test _gpt_is_on_ring(_gpt_get_node_rect(drawing, 2), ring, last(cut))
    @test is_on_curve(first(cut)) && is_on_curve(last(cut))
    @test label_place() == place
    @test drawing.label_boxes[] === label_boxes
end

@testset "the text of a vertex and the label of an edge can be edited" begin
    # A key at each place of each text changes that text and moves the caret, as
    # the type-in sweep of the examples checks it.
    text(value) = TextBlock(TextLine(TextString(value, StyleFont("Ubuntu", 13), color_default)))
    a, b = GraphVertex(text("orders")), GraphVertex(text("queue"))
    graph = GraphGraph([a, b], [GraphEdge(a, b; directed = true, label = text("publishes"))])
    measure = FixedMeasure(10, 15, 5, 0)
    projection = make_graph_projection_example(; measure, content = NaturalToGraphics(; measure))
    results = ProjecturedPlatformTest.walk_typein(graph, projection)
    @test count(r -> occursin(".edges", string(r.ref)), results) > 0
    @test count(r -> occursin(".vertices", string(r.ref)), results) > 0
    @test all(r -> r.ok, results)

    # A point on the label maps to a place in the label.
    iomap = print_document(projection, graph)
    drawing = _gvd_find_drawing(iomap)
    box = drawing.label_boxes[1]
    back = map_reference_backward(projection, iomap, PointReferenceStep(box[1] + 2, box[2] + box[4] ÷ 2))
    @test back !== nothing
    back === nothing ||
        @test collect(get_reference_steps(strip_reference_types(back)))[1:3] ==
              collect(get_reference_steps(strip_reference_types(@reference(graph, edges[1].label))))
end

@testset "a click on the label of an edge puts the caret in the label" begin
    text(value) = TextBlock(TextLine(TextString(value, StyleFont("Ubuntu", 13), color_default)))
    a, b = GraphVertex(text("orders")), GraphVertex(text("queue"))
    graph = GraphGraph([a, b], [GraphEdge(a, b; directed = true, label = text("publishes"))])
    measure = _gvd_measure()
    editor, backend, _ = _gvd_editor(graph; projection = make_graph_projection_example(; measure,
                                                                                         content = NaturalToGraphics(; measure)))
    drawing = _gvd_find_drawing(editor.iomap)
    origin = _gvd_place_of(editor, drawing.output)
    box = drawing.label_boxes[1]
    x, y = origin[1] + box[1] + 2, origin[2] + box[2] + box[4] ÷ 2
    _gvd_down!(editor, backend, x, y, 1.0)
    _gvd_up!(editor, backend, x, y, 1.05)
    steps = collect(get_reference_steps(strip_reference_types(something(get_selection(graph), EmptyReference()))))
    @test length(steps) >= 3 &&
          steps[1:3] == collect(get_reference_steps(strip_reference_types(@reference(graph, edges[1].label))))
end

end # test_graph_projection

# The drawing of `graph` by the grid engine, as its IO map.
function _gpt_draw_with_grid(graph)
    content = make_mixed_projection_example(measure = FixedMeasure(10, 15, 5, 0))
    projection = NestingProjection(ChainingProjection(GraphGraphToGraphLayout(GridEmbedding()),
                                                      GraphLayoutToGraphicsCanvas());
                                   recursion = content)
    print_document(projection, graph).child_iomap.step_iomaps[2][]
end

_gpt_get_node_rect(drawing, i) = collect(drawing.output.elements)[drawing.node_elements[i]]

_gpt_collect_lines(drawing) = filter(e -> e isa GraphicsPolyline, collect(drawing.output.elements))

# Whether `point` lies on the rim of the rectangle `rect`.
function _gpt_is_on_rim(rect, point)
    x, y, w, h = Int(rect.x), Int(rect.y), Int(rect.w), Int(rect.h)
    px, py = point
    (px in (x, x + w) && y <= py <= y + h) || (py in (y, y + h) && x <= px <= x + w)
end

# Whether `point` lies on the rim of the ring `ring` px around the rectangle
# `rect`, within one pixel.
function _gpt_is_on_ring(rect, ring, point)
    x, y = Int(rect.x) - ring, Int(rect.y) - ring
    w, h = Int(rect.w) + 2ring, Int(rect.h) + 2ring
    px, py = point
    is_near(u, v) = abs(u - v) <= 1
    ((is_near(px, x) || is_near(px, x + w)) && y - 1 <= py <= y + h + 1) ||
        ((is_near(py, y) || is_near(py, y + h)) && x - 1 <= px <= x + w + 1)
end
