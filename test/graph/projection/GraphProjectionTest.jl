
const _gctx = PrinterContext

function test_graph_projection()

@testset "the layouters' own random generator is OMNeT++'s" begin
    # A ported layouter draws the picture OMNeT++ draws only if it draws the same
    # random numbers. This is OMNeT++'s own self test, from LCGRandom::selfTest:
    # ten thousand draws from seed 1 must leave the seed at this exact value.
    @test run_lcg_self_test() == 1043618065

    # A seed is a picture: the same seed answers the same sequence, and a
    # different one does not.
    first = [draw_uniform01!(LcgRandom(7)) for _ in 1:1]
    @test first == [draw_uniform01!(LcgRandom(7))]
    @test first != [draw_uniform01!(LcgRandom(8))]

    # The range is [0, 1), and a seed outside 1:2^31-2 is refused rather than
    # silently repaired — seed 0 is a fixed point of this generator.
    random = LcgRandom(12345)
    values = [draw_uniform01!(random) for _ in 1:1000]
    @test all(0.0 .<= values .< 1.0)
    @test_throws ArgumentError LcgRandom(0)
    @test_throws ArgumentError LcgRandom(-3)
    @test all(0 .<= [draw!(random, 5) for _ in 1:100] .< 5)
    @test all(2.0 .<= [draw_uniform!(random, 2, 3) for _ in 1:100] .< 3.0)
end

@testset "the ported geometry" begin
    @test is_nil(pt_nil())
    @test !is_fully_specified(Pt(1, NaN, 0))
    @test pt_length(Pt(3, 4, 0)) == 5
    @test pt_distance(Pt(0, 0, 0), Pt(0, 3, 4)) == 5
    @test get_base_plane_length(Pt(3, 4, 100)) == 5
    @test convert_nan_to_zero(Pt(NaN, 2, NaN)) == Pt(0, 2, 0)
    @test Pt(1, 2, 3) + Pt(1, 1, 1) == Pt(2, 3, 4)
    @test Pt(1, 2, 3) * 2 == Pt(2, 4, 6)
    @test pt_multiply(Pt(2, 3, 4), Pt(10, 100, 1000)) == Pt(20, 300, 4000)
    @test get_diagonal_length(Rs(3, 4)) == 5
    @test get_area(Rs(3, 4)) == 12
    @test rc_center(Rc(10, 20, 0, 40, 60)) == Pt(30, 50, 0)
    @test rc_right(Rc(10, 20, 0, 40, 60)) == 50

    # Two rectangles apart on one axis and overlapping on the other: the distance
    # is measured on that one axis, and the segment carries NaN on the axis that
    # does not constrain it.
    left = Rc(0, 0, 0, 10, 100)
    right = Rc(30, 20, 0, 10, 100)
    segment, distance = rc_base_plane_distance(left, right)
    @test distance == 20                       # 30 - 10
    @test isnan(segment.begin_pt.y)
    # Overlapping rectangles are at distance zero.
    _, overlap = rc_base_plane_distance(left, Rc(5, 5, 0, 10, 10))
    @test overlap == 0
    # Diagonally apart: the distance joins the two nearest corners.
    _, corner = rc_base_plane_distance(Rc(0, 0, 0, 10, 10), Rc(13, 14, 0, 10, 10))
    @test corner == 5                          # (3, 4)
end

@testset "the ported graph component" begin
    # Two triangles that share nothing: one graph, two connected parts.
    made = [LayoutVertex(Pt(0, 0, 0), Rs(10, 10), i) for i in 1:6]
    component = GraphComponent()
    for vertex in made
        add_vertex!(component, vertex)
    end
    for (a, b) in ((1, 2), (2, 3), (3, 1), (4, 5), (5, 6), (6, 4))
        add_edge!(component, LayoutEdge(made[a], made[b]))
    end
    @test get_vertex_count(component) == 6
    @test get_edge_count(component) == 6
    @test find_vertex(component, 3) === made[3]
    @test index_of_vertex(component, made[4]) == 4

    calculate_connected_sub_components!(component)
    @test length(component.connected_sub_components) == 2
    @test all(part -> get_vertex_count(part) == 3 && get_edge_count(part) == 3,
              component.connected_sub_components)
    @test made[1].connected_sub_component !== made[4].connected_sub_component

    # The spanning tree starts at the busiest vertex and reaches everything in
    # its own part.
    part = component.connected_sub_components[1]
    calculate_spanning_tree!(part)
    @test length(part.spanning_tree_vertices) == 3
    @test part.spanning_tree_root !== nothing
    @test part.spanning_tree_root.spanning_tree_parent === nothing
    @test all(v -> v === part.spanning_tree_root || v.spanning_tree_parent !== nothing,
              part.spanning_tree_vertices)

    # A star: the centre has the most neighbours, so the tree roots there.
    centre = LayoutVertex(Pt(0, 0, 0), Rs(10, 10), :centre)
    leaves = [LayoutVertex(Pt(0, 0, 0), Rs(10, 10), i) for i in 1:4]
    star = GraphComponent()
    add_vertex!(star, centre)
    for leaf in leaves
        add_vertex!(star, leaf)
        add_edge!(star, LayoutEdge(centre, leaf))
    end
    calculate_spanning_tree!(star)
    @test star.spanning_tree_root === centre
    @test length(centre.spanning_tree_children) == 4
end

@testset "the engine a caller gets when it names none" begin
    # Qtenv picks by size and so does DeferredLayout: twenty vertices or more go
    # to the fast layouter, fewer go to the advanced one. Both thresholds are the
    # same number for the same reason — the advanced one is already slow at
    # thirty or forty modules.
    @test ADVANCED_LAYOUT_LIMIT == 20
    @test resolve_layout_engine(DeferredLayout(), 19) isa ForceDirectedLayout
    @test resolve_layout_engine(DeferredLayout(), 20) isa SpringEmbedderLayout
    @test resolve_layout_engine(DeferredLayout(), 500) isa SpringEmbedderLayout
    @test resolve_layout_engine(GridEmbedding(), 500) isa GridEmbedding

    @test layout_engine_name(GridEmbedding()) === :grid
    @test layout_engine_name(SpringEmbedderLayout()) === :spring_embedder
    @test layout_engine_name(ForceDirectedLayout()) === :force_directed

    # And the choice really is made per layout, from the graph it is given.
    small = [GraphVertex(JsonString("v$i")) for i in 1:5]
    large = [GraphVertex(JsonString("v$i")) for i in 1:25]
    small_graph = GraphGraph(small, [GraphEdge(small[i], small[i+1]) for i in 1:4])
    large_graph = GraphGraph(large, [GraphEdge(large[i], large[i+1]) for i in 1:24])
    small_sizes = Dict(objectid(v) => (40, 20) for v in small)
    large_sizes = Dict(objectid(v) => (40, 20) for v in large)

    advanced, _ = layout_graph(ForceDirectedLayout(), small_graph, small_sizes, [])
    deferred, _ = layout_graph(DeferredLayout(), small_graph, small_sizes, [])
    @test deferred == advanced

    fast, _ = layout_graph(SpringEmbedderLayout(), large_graph, large_sizes, [])
    deferred_large, _ = layout_graph(DeferredLayout(), large_graph, large_sizes, [])
    @test deferred_large == fast
end

@testset "a layout says which engine drew it" begin
    # A view cannot tell a reader what it is looking at, and a test cannot assert
    # that the choice went the way it should have, unless the layout carries the
    # answer. It matters most for the engine that decides late.
    made = [GraphVertex(JsonString("v$i")) for i in 1:3]
    graph = GraphGraph(made, [GraphEdge(made[1], made[2])])
    content = make_mixed_projection_example(measure=FixedMeasure(10, 15, 5, 0))

    for (engine, name) in ((GridEmbedding(), :grid),
                           (SpringEmbedderLayout(), :spring_embedder),
                           (ForceDirectedLayout(), :force_directed),
                           (DeferredLayout(), :force_directed))
        layout = print_document(GraphGraphToGraphLayout(engine), content, graph, _gctx()).output
        @test layout.engine === name
    end

    # Twenty-five vertices and the deferred engine reports the fast one, because
    # that is what ran.
    many = [GraphVertex(JsonString("v$i")) for i in 1:25]
    big = GraphGraph(many, [GraphEdge(many[i], many[i+1]) for i in 1:24])
    layout = print_document(GraphGraphToGraphLayout(DeferredLayout()), content, big, _gctx()).output
    @test layout.engine === :spring_embedder
end

@testset "ForceDirectedLayout draws what OMNeT++ draws" begin
    # As for the spring embedder: these are the positions OMNeT++'s own
    # ForceDirectedGraphLayouter answers, read out of a program linked against
    # libopplayout.so. See test/reference/forcedirected.cc.
    #
    # The reference pins `mct` so the run never stops on the clock. OMNeT++ draws
    # a random wall-clock limit there, and ForceDirectedLayout leaves it at
    # infinity, because a drawing must not depend on how fast the machine is.
    corners(centres, w, h) = [(round(Int, x - w/2), round(Int, y - h/2), w, h)
                              for (x, y) in centres]
    placed(positions, made) = [positions[objectid(v)] for v in made]
    make(count) = [GraphVertex(JsonString("v$i")) for i in 1:count]
    sized(made) = Dict(objectid(v) => (40, 20) for v in made)
    chain_of(made) = GraphGraph(made, [GraphEdge(made[i], made[i+1])
                                       for i in 1:length(made)-1])

    @testset "a chain of eight" begin
        omnetpp = [(245.862584, 10.000000), (224.180666, 128.762796), (199.053136, 248.641699),
                   (169.866408, 368.365953), (136.512386, 487.227347), (100.061794, 604.940874),
                   (61.238353, 721.110217), (20.000000, 834.570196)]
        made = make(8)
        positions, _ = layout_graph(ForceDirectedLayout(), chain_of(made), sized(made), [])
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end

    @testset "a three by three mesh in a box" begin
        omnetpp = [(287.352144, 118.256917), (217.532970, 227.518283), (104.722487, 196.950098),
                   (408.458845, 113.467789), (332.402472, 200.038725), (218.320834, 169.912867),
                   (486.990495, 202.033049), (406.126298, 288.455970), (285.144964, 281.024176)]
        side = 3
        made = make(side*side)
        edges = GraphEdge[]
        for r in 1:side, c in 1:side
            i = (r - 1) * side + c
            c < side && push!(edges, GraphEdge(made[i], made[i+1]))
            r < side && push!(edges, GraphEdge(made[i], made[i+side]))
        end
        positions, _ = layout_graph(ForceDirectedLayout(), GraphGraph(made, edges),
                                    sized(made), []; extent = (600, 400), border = 20)
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end

    @testset "a chain with one pinned end" begin
        # A pinned node becomes a point-constrained variable: it cannot move in
        # the plane, and the walls that a pin brings into existence shape
        # everything around it.
        omnetpp = [(120.000000, 70.000000), (153.787701, 184.838746), (159.057120, 304.940926),
                   (203.107987, 416.759813), (316.453094, 456.497630), (428.221781, 412.757196),
                   (467.015990, 299.222005), (463.333529, 180.029607)]
        made = make(8)
        pin = GraphConstraint(made[1], :pin, (100, 60))
        positions, _ = layout_graph(ForceDirectedLayout(), chain_of(made), sized(made), [pin])
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end

    @testset "a chain with four nodes anchored into one row" begin
        omnetpp = [(20.000000, 28.913223), (141.441933, 31.146755), (267.034863, 32.041976),
                   (317.034863, 32.041976), (367.034863, 32.041976), (417.034863, 32.041976),
                   (542.286404, 23.081856), (663.070986, 10.000000)]
        made = make(8)
        family = [GraphConstraint(made[i], :cluster, (:rte, 50.0 * (i - 3), 0.0))
                  for i in 3:6]
        positions, _ = layout_graph(ForceDirectedLayout(), chain_of(made), sized(made), family)
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end

    @testset "seed 3, which turns the pre-embedding on" begin
        # Whether to pre-embed is a coin toss on the seed, and seed 1 says no.
        # Only this path runs StarTreeEmbedding and HeapEmbedding at all.
        omnetpp = [(20.000000, 64.607097), (153.286393, 68.658803), (290.369531, 70.552925),
                   (429.170798, 67.749032), (568.104461, 59.316981), (706.085700, 45.744874),
                   (842.295817, 28.641928), (974.081052, 10.000000)]
        made = make(8)
        positions, _ = layout_graph(ForceDirectedLayout(seed = 3), chain_of(made),
                                    sized(made), [])
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end

    @testset "two separate triangles, pre-embedded part by part" begin
        omnetpp = [(147.170394, 560.484383), (122.308889, 429.232602), (20.000000, 518.627144),
                   (178.509813, 144.962529), (178.509813, 10.000000), (295.390792, 77.481264)]
        made = make(6)
        edges = [GraphEdge(made[a], made[b])
                 for (a, b) in ((1, 2), (2, 3), (3, 1), (4, 5), (5, 6), (6, 4))]
        positions, _ = layout_graph(ForceDirectedLayout(seed = 3), GraphGraph(made, edges),
                                    sized(made), [])
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end
end

@testset "SpringEmbedderLayout draws what OMNeT++ draws" begin
    # The point of a port is that it answers what the original answers. These are
    # the positions OMNeT++'s own BasicSpringEmbedderLayout produces, read out of
    # a program linked against libopplayout.so from omnet-cpp and given the
    # same graph, the same node sizes and seed 1.
    #
    # They are centres, which is what GraphLayouter::getNodePosition answers; the
    # engine reports corners, so each is the centre less half the size.
    #
    # To regenerate, build a program against `omnet-cpp/src/layout` that calls
    # addMovableNode / addFixedNode / addAnchoredNode / addEdge in this order,
    # then setSeed(1), setSize(...) and execute().
    corners(centres, w, h) = [(round(Int, x - w/2), round(Int, y - h/2), w, h)
                              for (x, y) in centres]
    placed(positions, made) = [positions[objectid(v)] for v in made]

    @testset "a four by four mesh" begin
        omnetpp = [(20.000000, 66.600524), (77.812742, 46.125950), (139.534567, 26.559605),
                   (198.587325, 10.000000), (36.419738, 125.692940), (95.832624, 106.050806),
                   (159.041757, 86.015787), (218.924606, 67.860555), (55.827039, 187.464957),
                   (115.709888, 169.309725), (178.919021, 149.274706), (238.331907, 129.632572),
                   (76.164318, 245.325512), (135.217076, 228.765907), (196.938901, 209.199563),
                   (254.751643, 188.724988)]
        side = 4
        made = [GraphVertex(JsonString("v$i")) for i in 1:side*side]
        edges = GraphEdge[]
        for r in 1:side, c in 1:side
            i = (r - 1) * side + c
            c < side && push!(edges, GraphEdge(made[i], made[i+1]))
            r < side && push!(edges, GraphEdge(made[i], made[i+side]))
        end
        graph = GraphGraph(made, edges)
        sizes = Dict(objectid(v) => (40, 20) for v in made)
        positions, _ = layout_graph(SpringEmbedderLayout(), graph, sizes, [])
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end

    @testset "a chain with one pinned end" begin
        omnetpp = [(120.000000, 70.000000), (169.284850, 99.223049), (221.463412, 130.834805),
                   (275.067309, 163.785508), (329.006879, 197.333118), (382.291595, 230.800465),
                   (433.836629, 263.440710), (482.157706, 294.239248)]
        made = [GraphVertex(JsonString("v$i")) for i in 1:8]
        graph = GraphGraph(made, [GraphEdge(made[i], made[i+1]) for i in 1:7])
        sizes = Dict(objectid(v) => (40, 20) for v in made)
        # addFixedNode names a centre; a :pin names the corner, so (100, 60) here
        # is the (120, 70) the reference was given.
        pin = GraphConstraint(made[1], :pin, (100, 60))
        positions, _ = layout_graph(SpringEmbedderLayout(), graph, sizes, [pin])
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end

    @testset "a chain with four nodes anchored into one row" begin
        omnetpp = [(20.000000, 10.000000), (77.583275, 10.369749), (139.389189, 10.676612),
                   (189.389189, 10.676612), (239.389189, 10.676612), (289.389189, 10.676612),
                   (351.195167, 10.970471), (408.778552, 11.322665)]
        made = [GraphVertex(JsonString("v$i")) for i in 1:8]
        graph = GraphGraph(made, [GraphEdge(made[i], made[i+1]) for i in 1:7])
        sizes = Dict(objectid(v) => (40, 20) for v in made)
        family = [GraphConstraint(made[i], :cluster, (:rte, 50.0 * (i - 3), 0.0))
                  for i in 3:6]
        positions, _ = layout_graph(SpringEmbedderLayout(), graph, sizes, family)
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end

    @testset "a chain inside a six hundred by four hundred box" begin
        omnetpp = [(553.584691, 37.628623), (486.395264, 84.120658), (414.520066, 132.743198),
                   (339.999007, 181.842265), (264.356616, 230.276215), (189.027365, 277.126671),
                   (115.632536, 321.521197), (46.415309, 362.371377)]
        made = [GraphVertex(JsonString("v$i")) for i in 1:8]
        graph = GraphGraph(made, [GraphEdge(made[i], made[i+1]) for i in 1:7])
        sizes = Dict(objectid(v) => (40, 20) for v in made)
        positions, _ = layout_graph(SpringEmbedderLayout(), graph, sizes, [];
                                    extent = (600, 400), border = 20)
        @test placed(positions, made) == corners(omnetpp, 40, 20)
    end
end

@testset "SpringEmbedderLayout" begin
    # A ring of ten. The grid would draw a grid; a spring embedder should draw
    # something that spreads out and keeps connected nodes near each other.
    made = [GraphVertex(JsonString("v$i")) for i in 1:10]
    ring = GraphGraph(made, [GraphEdge(made[i], made[mod1(i+1, 10)]) for i in 1:10])
    sizes = Dict(objectid(v) => (40, 20) for v in made)
    engine = SpringEmbedderLayout()

    positions, routes = layout_graph(engine, ring, sizes, [])
    @test length(positions) == 10
    @test length(routes) == 10
    @test all(box -> box[3] == 40 && box[4] == 20, values(positions))

    # It spreads: ten nodes do not land on one spot.
    centres = [(box[1] + 20, box[2] + 10) for box in values(positions)]
    @test length(unique(centres)) == 10
    span_x = maximum(c[1] for c in centres) - minimum(c[1] for c in centres)
    @test span_x > 40

    # Connected nodes end up nearer than the graph is wide: that is the whole
    # claim of a spring embedder over a grid.
    neighbour_distance(i) = begin
        a = positions[objectid(made[i])]; b = positions[objectid(made[mod1(i+1, 10)])]
        hypot((a[1] - b[1]), (a[2] - b[2]))
    end
    diagonal = hypot(span_x, maximum(c[2] for c in centres) - minimum(c[2] for c in centres))
    @test maximum(neighbour_distance(i) for i in 1:10) < diagonal

    # A seed is a picture: the same seed twice is the same layout, a different
    # seed is a different one. Without this nothing downstream can cache or
    # compare a drawing.
    again, _ = layout_graph(SpringEmbedderLayout(), ring, sizes, [])
    @test again == positions
    other, _ = layout_graph(SpringEmbedderLayout(seed = 42), ring, sizes, [])
    @test other != positions
end

@testset "SpringEmbedderLayout honours a pin, an anchor and a box" begin
    made = [GraphVertex(JsonString("v$i")) for i in 1:8]
    chain = GraphGraph(made, [GraphEdge(made[i], made[i+1]) for i in 1:7])
    sizes = Dict(objectid(v) => (40, 20) for v in made)

    # A pin is where the caller put it, whatever the simulation does around it.
    pin = GraphConstraint(made[1], :pin, (100, 60))
    positions, _ = layout_graph(SpringEmbedderLayout(), chain, sizes, [pin])
    @test positions[objectid(made[1])] == (100, 60, 40, 20)

    # A cluster is one body: its members keep the offsets they were given, so a
    # module vector laid out as a row stays a row wherever the row lands.
    family = [GraphConstraint(made[i], :cluster, (:rte, 50.0 * (i - 3), 0.0))
              for i in 3:6]
    positions, _ = layout_graph(SpringEmbedderLayout(), chain, sizes, family)
    xs = [positions[objectid(made[i])][1] for i in 3:6]
    ys = [positions[objectid(made[i])][2] for i in 3:6]
    @test all(y -> y == ys[1], ys)                       # one row
    @test all(i -> xs[i+1] - xs[i] == 50, 1:3)           # 50 apart, in order

    # A box bounds the picture, and the two-node case still fits in it.
    bounded, _ = layout_graph(SpringEmbedderLayout(), chain, sizes, [];
                              extent = (600, 400), border = 20)
    for box in values(bounded)
        @test box[1] >= 0
        @test box[2] >= 0
        @test box[1] + box[3] <= 600
        @test box[2] + box[4] <= 400
    end

    # An extent smaller than twice the border is refused, not silently repaired.
    @test_throws ArgumentError layout_graph(SpringEmbedderLayout(), chain, sizes, [];
                                            extent = (30, 400), border = 20)

    # And the kinds it does not implement are refused by name.
    @test get_supported_constraint_kinds(SpringEmbedderLayout()) == (:pin, :fixed_size, :cluster)
    @test_throws ArgumentError layout_graph(SpringEmbedderLayout(), chain, sizes,
                                            [GraphConstraint(made[1], :align, :x)])
end

@testset "SpringEmbedderLayout keeps unconnected parts apart but not far" begin
    # Repulsion between different colours stops after 100 units, which is what
    # keeps a graph in several pieces from blowing itself apart. Three separate
    # pairs should end up in one readable picture, not scattered to infinity.
    made = [GraphVertex(JsonString("v$i")) for i in 1:6]
    pieces = GraphGraph(made, [GraphEdge(made[1], made[2]),
                               GraphEdge(made[3], made[4]),
                               GraphEdge(made[5], made[6])])
    sizes = Dict(objectid(v) => (40, 20) for v in made)
    positions, _ = layout_graph(SpringEmbedderLayout(), pieces, sizes, [])
    xs = [box[1] for box in values(positions)]
    ys = [box[2] for box in values(positions)]
    @test maximum(xs) - minimum(xs) < 4000
    @test maximum(ys) - minimum(ys) < 4000
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
    chain = GraphToGraphics(SpringEmbedderLayout(); extent = (400, 300), border = 5)
    @test chain.projections[1].engine isa SpringEmbedderLayout
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
