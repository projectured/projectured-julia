function test_process_diagram()
@testset "ProcessDiagram" begin

_count(canvas, T) = count(e -> e isa T, canvas.elements)

# The label of the node a vertex draws, for readable assertions about shape.
_content(vertex) = vertex.content
_edge_between(graph, from, to) =
    findfirst(e -> e.source === from && e.target === to, [e for e in graph.edges])
_label_of(graph, from, to) = begin
    index = _edge_between(graph, from, to)
    index === nothing ? nothing : (l = graph.edges[index].label; l === nothing ? "" : l.text)
end
_vertex_of(graph, node) = begin
    index = findfirst(v -> v.content === node, [v for v in graph.vertices])
    index === nothing ? nothing : graph.vertices[index]
end

# ── the pipeline ─────────────────────────────────────────────────────────
@testset "a process draws as a flowchart" begin
    model = make_process_diagram_document_example()
    iomap = print_document(make_process_diagram_projection_example(), model)
    @test iomap.output isa GraphicsCanvas

    diagram = iomap.step_iomaps[1][].output
    @test diagram isa ProcessDiagram
    @test diagram.model === model

    graph = iomap.step_iomaps[2][].output
    # One box per node that does something, plus the two terminals. Sequences
    # are structure — they are drawn as edges, not as boxes.
    nodes = process_nodes(model)
    drawn = count(n -> !(n isa ProcessSequence) && !(n isa ProcessModel), nodes)
    @test length(graph.vertices) == drawn + 2
    @test !any(v -> v.content isa ProcessSequence, graph.vertices)

    # Terminals bracket the picture.
    @test graph.vertices[1].content isa ProcessTerminal
    @test graph.vertices[1].content.kind === :start
    @test graph.vertices[end].content.kind === :stop

    # Each box holds the real node by identity, so a click reaches the document
    # the notation edits.
    step = model.body.steps[1]
    @test _vertex_of(graph, step) !== nothing
end

# ── control flow ─────────────────────────────────────────────────────────
# The picture *is* the control flow, so this is the load-bearing assertion of
# the whole stage: the arrows, not the boxes.
@testset "arrows follow the structure" begin
    model = make_process_diagram_document_example()   # the drain procedure
    graph = print_document(ChainingProjection(ProcessToProcessDiagram(),
                                              ProcessDiagramToGraph()), model).output

    seed = model.body.steps[1]                        # sent = 0
    loop = model.body.steps[2]                        # for item in queue
    guard = loop.body.steps[1]                        # if item === nothing
    skip = guard.then_branch.steps[1]                 # continue
    hand = loop.body.steps[2]                         # step "hand it to the medium"
    tally = loop.body.steps[3]                        # sent = sent + 1
    done = model.body.steps[3]                        # return sent

    start = graph.vertices[1]
    stop = graph.vertices[end]
    v(node) = _vertex_of(graph, node)

    # The straight-line spine.
    @test _edge_between(graph, start, v(seed)) !== nothing
    @test _edge_between(graph, v(seed), v(loop)) !== nothing
    @test _edge_between(graph, v(done), stop) !== nothing

    # The loop: one exit into the body, one past it, and the body's tail
    # closing back on the header. That back edge is the loop.
    @test _label_of(graph, v(loop), v(guard)) == "next"
    @test _label_of(graph, v(loop), v(done)) == "done"
    @test _edge_between(graph, v(tally), v(loop)) !== nothing

    # The decision: two labelled exits, and no merge vertex — the `no` branch
    # goes straight to the node that follows the decision.
    @test _label_of(graph, v(guard), v(skip)) == "yes"
    @test _label_of(graph, v(guard), v(hand)) == "no"

    # `continue` jumps to the loop header, not to the next node.
    @test _edge_between(graph, v(skip), v(loop)) !== nothing
    @test _edge_between(graph, v(skip), v(hand)) === nothing

    # `break` leaves the loop, and `return` leaves the process.
    transmit = make_process_transmit_document_example()
    tgraph = print_document(ChainingProjection(ProcessToProcessDiagram(),
                                              ProcessDiagramToGraph()), transmit).output
    tv(node) = _vertex_of(tgraph, node)
    attempt_loop = transmit.body.steps[3]
    give_up = attempt_loop.body.steps[2]
    brk = give_up.then_branch.steps[1]
    failed = transmit.body.steps[4]
    sent = attempt_loop.body.steps[1].then_branch.steps[2]
    @test _edge_between(tgraph, tv(brk), tv(failed)) !== nothing      # loop exit
    @test _edge_between(tgraph, tv(sent), tgraph.vertices[end]) !== nothing
end

# ── the live overlay ─────────────────────────────────────────────────────
# Writing the session's position must repaint the overlay WITHOUT re-running
# the layout and without a reprint.
@testset "the session repaints the overlay reactively" begin
    model = make_process_diagram_document_example()
    iomap = print_document(make_process_diagram_projection_example(), model)
    canvas = iomap.output
    diagram = iomap.step_iomaps[1][].output

    boxes = _count(canvas, GraphicsRect)
    lines = _count(canvas, GraphicsPolyline)

    # Nothing attached: no overlay, and nothing throws.
    @test diagram.session === nothing
    @test _count(canvas, GraphicsRect) == boxes

    # A bare stand-in for the debug session — the diagram reads `node` and
    # `previous` and nothing else, which is what the debug slice fills in.
    session = ProcessDebugSession()
    diagram.session = session

    at(node, from = 0) = set_process_position!(session, model;
                                               node = get_node_index(model, node),
                                               previous = from == 0 ? 0 : get_node_index(model, from))

    loop = model.body.steps[2]
    at(loop)
    @test _count(canvas, GraphicsRect) == boxes + 1        # the ring

    # A position naming a node with no box (a sequence), and an index out of
    # range, both mean no ring rather than a wrong one.
    at(model.body)
    @test _count(canvas, GraphicsRect) == boxes
    set_process_position!(session, model; node = 9999, previous = 0)
    @test _count(canvas, GraphicsRect) == boxes
    set_process_position!(session, model; node = 0, previous = 0)
    @test _count(canvas, GraphicsRect) == boxes

    # The arrow just taken is derived from the (previous, current) pair.
    guard = loop.body.steps[1]
    at(guard, loop)
    @test _count(canvas, GraphicsPolyline) == lines + 1
    # A pair with no arrow between them re-strokes nothing, and does not throw.
    at(loop.body.steps[3], guard)
    @test _count(canvas, GraphicsPolyline) == lines

    # The layout is untouched by any of it: the boxes stay where they were.
    # Captured with nothing highlighted, so the ring is not part of `before`.
    set_process_position!(session, model; node = 0, previous = 0)
    before = Set((r.x, r.y) for r in canvas.elements if r isa GraphicsRect)
    at(guard)
    session.step_count = 17
    after = Set((r.x, r.y) for r in canvas.elements if r isa GraphicsRect)
    @test issubset(before, after)
end

# ── selection round-trip ─────────────────────────────────────────────────
@testset "clicking a box selects its node" begin
    model = make_process_diagram_document_example()
    step = model.body.steps[1]

    stage1 = ProcessToProcessDiagram()
    io1 = print_document(stage1, model)
    forward1 = map_reference_forward(stage1, io1, @reference(model, body.steps[1]))
    @test forward1 !== nothing
    @test is_reference_equal(strip_reference_types(map_reference_backward(stage1, io1, forward1)),
                             strip_reference_types(@reference(model, body.steps[1])))

    stage2 = ProcessDiagramToGraph()
    io2 = print_document(stage2, io1.output)
    forward2 = map_reference_forward(stage2, io2, forward1)
    @test forward2 !== nothing
    back2 = map_reference_backward(stage2, io2, forward2)
    @test back2 !== nothing
    @test is_reference_equal(strip_reference_types(back2), strip_reference_types(forward1))

    # A terminal has no node behind it, so it selects nothing rather than
    # something arbitrary.
    @test map_reference_backward(stage2, io2,
              @reference(io2.output, vertices[1].content)) === nothing
end

end # @testset "ProcessDiagram"
end # test_process_diagram
