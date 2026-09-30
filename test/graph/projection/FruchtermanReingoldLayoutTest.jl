# Tests for `FruchtermanReingoldLayout`, the force-directed engine of this
# package: what it promises about the boxes it places, and what it does with each
# constraint.

# Every two boxes of a placement are disjoint.
function _are_boxes_disjoint(positions)
    boxes = collect(values(positions))
    for i in 1:length(boxes), j in (i+1):length(boxes)
        a = boxes[i]; b = boxes[j]
        (a[1] + a[3] <= b[1] || b[1] + b[3] <= a[1] ||
         a[2] + a[4] <= b[2] || b[2] + b[4] <= a[2]) || return false
    end
    true
end

# An engine that decides by the size of the graph, as an engine that a package
# registers can: the grid from ten vertices up, the force-directed engine below.
struct _SizeChoosingTestEngine <: GraphLayoutEngine end
ProjecturedGraph.GraphModule.resolve_layout_engine(::_SizeChoosingTestEngine,
                                                   vertex_count::Integer = 0) =
    vertex_count >= 10 ? GridEmbedding() : FruchtermanReingoldLayout()

_box_centre(box) = (box[1] + box[3]/2, box[2] + box[4]/2)
_box_distance(a, b) = hypot((_box_centre(a) .- _box_centre(b))...)

function test_fruchterman_reingold_layout()
@testset "FruchtermanReingoldLayout" begin
    engine = FruchtermanReingoldLayout()

    @testset "it names itself and the constraints it implements" begin
        @test layout_engine_name(engine) === :fruchterman_reingold
        @test get_supported_constraint_kinds(engine) == (:pin, :fixed_size, :cluster)
        v = GraphVertex(JsonString("a"))
        graph = GraphGraph([v], GraphEdge[])
        for kind in (:align, :same_rank, :min_separation)
            @test_throws ArgumentError layout_graph(engine, graph,
                                                    Dict(objectid(v) => (40, 20)),
                                                    [GraphConstraint(v, kind, nothing)])
        end
    end

    @testset "an empty graph and a lone vertex" begin
        positions, routes = layout_graph(engine, GraphGraph(GraphVertex[], GraphEdge[]),
                                         Dict(), [])
        @test isempty(positions) && isempty(routes)
        v = GraphVertex(JsonString("a"))
        positions, _ = layout_graph(engine, GraphGraph([v], GraphEdge[]),
                                    Dict(objectid(v) => (40, 20)), []; border = 5)
        @test positions[objectid(v)] == (5, 5, 40, 20)
    end

    @testset "a mesh: every box placed, none overlapping, edges short" begin
        vertices = [GraphVertex(JsonString("v$i")) for i in 1:16]
        at(r, c) = vertices[(r - 1) * 4 + c]
        edges = GraphEdge[]
        for r in 1:4, c in 1:4
            c < 4 && push!(edges, GraphEdge(at(r, c), at(r, c + 1)))
            r < 4 && push!(edges, GraphEdge(at(r, c), at(r + 1, c)))
        end
        graph = GraphGraph(vertices, edges)
        sizes = Dict(objectid(v) => (60, 30) for v in vertices)
        positions, routes = layout_graph(engine, graph, sizes, [])
        @test length(positions) == 16
        @test all(box -> box[3] == 60 && box[4] == 30, values(positions))
        @test _are_boxes_disjoint(positions)
        @test length(routes) == length(edges)
        # An edge joins two boxes that are nearer than two boxes with none.
        adjacent = Set((objectid(getfield(e, :source)[]),
                        objectid(getfield(e, :target)[]))
                       for e in edges)
        joined = Float64[]; apart = Float64[]
        for i in 1:16, j in (i+1):16
            a, b = objectid(vertices[i]), objectid(vertices[j])
            d = _box_distance(positions[a], positions[b])
            ((a, b) in adjacent || (b, a) in adjacent) ?
                push!(joined, d) : push!(apart, d)
        end
        @test sum(joined) / length(joined) < sum(apart) / length(apart)
    end

    @testset "boxes of very different sizes do not overlap" begin
        vertices = [GraphVertex(JsonString("v$i")) for i in 1:8]
        graph = GraphGraph(vertices, [GraphEdge(vertices[1], vertices[i]) for i in 2:8])
        sizes = Dict(objectid(v) => (i == 1 ? (300, 200) : (40, 20))
                     for (i, v) in enumerate(vertices))
        positions, _ = layout_graph(engine, graph, sizes, [])
        @test _are_boxes_disjoint(positions)
    end

    @testset "parts that are not connected stay near each other" begin
        vertices = [GraphVertex(JsonString("v$i")) for i in 1:6]
        graph = GraphGraph(vertices, [GraphEdge(vertices[1], vertices[2]),
                                      GraphEdge(vertices[2], vertices[3]),
                                      GraphEdge(vertices[3], vertices[1]),
                                      GraphEdge(vertices[4], vertices[5]),
                                      GraphEdge(vertices[5], vertices[6]),
                                      GraphEdge(vertices[6], vertices[4])])
        sizes = Dict(objectid(v) => (60, 30) for v in vertices)
        positions, _ = layout_graph(engine, graph, sizes, [])
        @test _are_boxes_disjoint(positions)
        span = maximum(_box_distance(positions[objectid(a)], positions[objectid(b)])
                       for a in vertices, b in vertices)
        @test span < 20 * 60
    end

    @testset "a placement is deterministic" begin
        vertices = [GraphVertex(JsonString("v$i")) for i in 1:12]
        graph = GraphGraph(vertices, [GraphEdge(vertices[i], vertices[i+1])
                                      for i in 1:11])
        sizes = Dict(objectid(v) => (60, 30) for v in vertices)
        @test layout_graph(engine, graph, sizes, []) ==
              layout_graph(engine, graph, sizes, [])
        @test layout_graph(engine, graph, sizes, []; extent = (500, 400)) ==
              layout_graph(engine, graph, sizes, []; extent = (500, 400))
    end

    @testset "an extent bounds the placement" begin
        vertices = [GraphVertex(JsonString("v$i")) for i in 1:30]
        graph = GraphGraph(vertices, [GraphEdge(vertices[i], vertices[i+1])
                                      for i in 1:29])
        sizes = Dict(objectid(v) => (80, 30) for v in vertices)
        positions, _ = layout_graph(engine, graph, sizes, []; extent = (800, 600),
                                    border = 10)
        for box in values(positions)
            @test box[1] >= 10 && box[2] >= 10
            @test box[1] + box[3] <= 790 && box[2] + box[4] <= 590
        end
        @test all(box -> box[3] == 80 && box[4] == 30, values(positions))
    end

    @testset "a pin holds exactly, with and without an extent" begin
        vertices = [GraphVertex(JsonString("v$i")) for i in 1:5]
        graph = GraphGraph(vertices, [GraphEdge(vertices[i], vertices[i+1])
                                      for i in 1:4])
        sizes = Dict(objectid(v) => (40, 20) for v in vertices)
        pin = GraphConstraint(vertices[1], :pin, (300, 200))
        positions, _ = layout_graph(engine, graph, sizes, [pin])
        @test positions[objectid(vertices[1])] == (300, 200, 40, 20)
        @test _are_boxes_disjoint(positions)
        positions, _ = layout_graph(engine, graph, sizes, [pin]; extent = (500, 400),
                                    border = 10)
        @test positions[objectid(vertices[1])] == (300, 200, 40, 20)
        for box in values(positions)
            @test box[1] >= 10 && box[2] >= 10
            @test box[1] + box[3] <= 490 && box[2] + box[4] <= 390
        end
    end

    @testset "a cluster moves as one body and keeps its offsets" begin
        vertices = [GraphVertex(JsonString("v$i")) for i in 1:6]
        graph = GraphGraph(vertices, [GraphEdge(vertices[5], vertices[1]),
                                      GraphEdge(vertices[6], vertices[4])])
        sizes = Dict(objectid(v) => (40, 20) for v in vertices)
        row = [GraphConstraint(vertices[i], :cluster, (:row, 50.0 * (i - 1), 0.0))
               for i in 1:4]
        positions, _ = layout_graph(engine, graph, sizes, row)
        first_centre = _box_centre(positions[objectid(vertices[1])])
        for i in 2:4
            centre = _box_centre(positions[objectid(vertices[i])])
            @test centre[1] - first_centre[1] ≈ 50.0 * (i - 1) atol = 1
            @test centre[2] ≈ first_centre[2] atol = 1
        end
        @test _are_boxes_disjoint(positions)
    end

    @testset "a registered engine is resolved for the size of the graph" begin
        register_layout_engine!((; orthogonal = false) -> _SizeChoosingTestEngine())
        try
            @test resolve_layout_engine(DeferredLayout(), 5) isa FruchtermanReingoldLayout
            @test resolve_layout_engine(DeferredLayout(), 20) isa GridEmbedding
            # A factory that answers a deferred engine does not recurse.
            register_layout_engine!((; orthogonal = false) -> DeferredLayout())
            @test resolve_layout_engine(DeferredLayout(), 20) isa
                  FruchtermanReingoldLayout
        finally
            register_layout_engine!(nothing)
        end
    end

    @testset "a fixed size wins over the measured one" begin
        v1 = GraphVertex(JsonString("a")); v2 = GraphVertex(JsonString("b"))
        graph = GraphGraph([v1, v2], [GraphEdge(v1, v2)])
        sizes = Dict(objectid(v1) => (40, 20), objectid(v2) => (60, 30))
        positions, _ = layout_graph(engine, graph, sizes,
                                    [GraphConstraint(v2, :fixed_size, (25, 15))])
        @test positions[objectid(v2)][3:4] == (25, 15)
    end
end
end
