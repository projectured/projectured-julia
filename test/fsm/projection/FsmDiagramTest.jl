function test_fsm_diagram()
@testset "FsmDiagram" begin

_count(canvas, T) = count(e -> e isa T, canvas.elements)

# ── the pipeline ─────────────────────────────────────────────────────────
@testset "a machine draws as a graph" begin
    machine = make_fsm_diagram_document_example()
    iomap = print_document(make_fsm_diagram_projection_example(), machine)
    canvas = iomap.output
    @test canvas isa GraphicsCanvas

    # The toggle machine: two states, two transitions with a target (the stay
    # has none), so two node boxes and two edges.
    diagram = iomap.step_iomaps[1][].output
    @test diagram isa FsmDiagram
    @test diagram.machine === machine
    graph = iomap.step_iomaps[2][].output
    @test length(graph.vertices) == 2
    @test length(graph.edges) == 2
    # A stay contributes no edge — it is visible in the notation, not here.
    @test length(get_fsm_transitions(machine)) == 3

    # Each vertex holds the real state by identity, so a click on a node
    # reaches the document the notation edits.
    @test graph.vertices[1].content === machine.states[1]
    # An edge's label is the transition itself, likewise by identity.
    @test graph.edges[1].label === machine.states[1].transitions[1]
end

# ── the live overlay ─────────────────────────────────────────────────────
# This is the load-bearing property of the whole diagram design: writing the
# live fields must repaint the overlay WITHOUT re-running the layout, and
# without a reprint.
@testset "live fields repaint the overlay reactively" begin
    machine = make_fsm_diagram_document_example()
    iomap = print_document(make_fsm_diagram_projection_example(), machine)
    canvas = iomap.output
    diagram = iomap.step_iomaps[1][].output

    boxes = _count(canvas, GraphicsRect)
    lines = _count(canvas, GraphicsPolyline)

    # The current state adds a ring behind its box.
    diagram.live_state = 2
    @test _count(canvas, GraphicsRect) == boxes + 1
    diagram.live_state = 1
    @test _count(canvas, GraphicsRect) == boxes + 1
    # Out-of-range (and 0, "not running") means no ring.
    diagram.live_state = 0
    @test _count(canvas, GraphicsRect) == boxes
    diagram.live_state = 99
    @test _count(canvas, GraphicsRect) == boxes

    # The last transition re-strokes its edge.
    diagram.live_transition = 1
    @test _count(canvas, GraphicsPolyline) == lines + 1
    diagram.live_transition = 0
    @test _count(canvas, GraphicsPolyline) == lines
    # A stay has no edge, so highlighting it draws nothing — and does not throw.
    diagram.live_transition = 2
    @test _count(canvas, GraphicsPolyline) == lines

    # The layout is untouched by any of it: the node boxes stay exactly where
    # they were. (A highlight that moved the picture would mean the highlight
    # had reached the engine's inputs.)
    rects_before = [(r.x, r.y) for r in canvas.elements if r isa GraphicsRect]
    diagram.live_state = 2
    diagram.transition_count = 17
    rects_after = [(r.x, r.y) for r in canvas.elements if r isa GraphicsRect]
    @test issubset(Set(rects_before), Set(rects_after))
end

# ── selection round-trip ─────────────────────────────────────────────────
@testset "selection descends into a state" begin
    machine = make_fsm_diagram_document_example()
    stage1 = FsmToFsmDiagram()
    io1 = print_document(stage1, machine)
    forward1 = map_reference_forward(stage1, io1, @reference(machine, states[1]))
    @test forward1 !== nothing
    @test is_reference_equal(strip_reference_types(map_reference_backward(stage1, io1, forward1)),
                             strip_reference_types(@reference(machine, states[1])))

    stage2 = FsmDiagramToGraph()
    io2 = print_document(stage2, io1.output)
    forward2 = map_reference_forward(stage2, io2, forward1)
    @test forward2 !== nothing
    back2 = map_reference_backward(stage2, io2, forward2)
    @test back2 !== nothing
    @test is_reference_equal(strip_reference_types(back2), strip_reference_types(forward1))
end

# ── the graph slice's highlight fields ───────────────────────────────────
@testset "graph highlights are presentation-only" begin
    a = GraphVertex(JsonString("a"))
    b = GraphVertex(JsonString("b"))
    edge = GraphEdge(a, b)
    graph = GraphGraph([a, b], [edge])
    @test graph.highlight_vertex === nothing
    @test graph.highlight_edge === nothing

    layout = print_document(GraphGraphToGraphLayout(GridEmbedding()),
                            make_mixed_projection_example(measure=(t, f) -> (length(t) * 10, 20)),
                            graph, PrinterContext()).output
    @test layout.highlight_vertex === nothing
    # The layout reads the graph's field reactively, so a producer can wire it
    # after the layout was built.
    graph.highlight_vertex = a
    @test layout.highlight_vertex === a
end

end # @testset "FsmDiagram"
end # test_fsm_diagram
