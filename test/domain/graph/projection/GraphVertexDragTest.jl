# The drag of a vertex: a press on a vertex and a small move start it, each move
# moves the vertex in the drawing only, and the release writes one edit of the
# constraints of the graph: a pin for the dragged vertex and a start for each
# other vertex. The editor tests run the real editor with the drag tracking
# screen, so the parts of the drag reach the graph by its path, as in the app.

_gvd_measure() = FixedMeasure(10, 18, 6, 0)

_gvd_force(value) = value isa AbstractCell ? _gvd_force(value[]) : value

# The graph of the example in the window `W` of a drag tracking screen, and the
# editor that shows it.
function _gvd_editor()
    graph = make_graph_document_example()
    scene = make_window_scene(graph, "W"; width = 900, height = 700)
    opened = make_opened_window_projections(; measure = _gvd_measure())
    composed = make_window_scene_projection(make_graph_projection_example(measure = _gvd_measure());
                                            opened_window_projections = opened)
    document, projection = make_tracking_screen(scene, composed)
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend = backend,
                    devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend, graph)
end

_gvd_send!(editor, backend, event) =
    (push_event!(backend, WindowInput(:W, event)); run_frame!(editor))
_gvd_down!(editor, backend, x, y, time) =
    _gvd_send!(editor, backend, MouseDown(:left, x, y, ModifierKeys(); time))
_gvd_held!(editor, backend, x, y, time) =
    _gvd_send!(editor, backend, MouseMove(x, y, MouseButtons(:left), ModifierKeys(); time))
_gvd_up!(editor, backend, x, y, time) =
    _gvd_send!(editor, backend, MouseUp(:left, x, y, ModifierKeys(); time))

# The IO map of the drawing of the graph, found in the IO map tree of the editor.
function _gvd_find_drawing(root)
    seen = Set{UInt}()
    stack = Any[root]
    while !isempty(stack)
        value = _gvd_force(pop!(stack))
        value isa GraphLayoutToGraphicsCanvasIoMap && return value
        if value isa IoMap
            objectid(value) in seen && continue
            push!(seen, objectid(value))
            for name in fieldnames(typeof(value))
                name in (:projection, :input, :output) || push!(stack, getfield(value, name))
            end
        elseif value isa Union{AbstractVector,Tuple}
            append!(stack, value)
        end
    end
    nothing
end

# The point of the window `W` where `canvas` is drawn, or `nothing`.
_gvd_place_of(editor, canvas) =
    _gvd_find_canvas(_gvd_force(_gvd_force(_gvd_force(get_iomap_output(editor.iomap)).windows)[1].content),
                     canvas)

function _gvd_find_canvas(node, canvas, ox = 0, oy = 0)
    node = _gvd_force(node)
    node === nothing && return nothing
    x = hasproperty(node, :x) ? ox + Int(_gvd_force(node.x)) : ox
    y = hasproperty(node, :y) ? oy + Int(_gvd_force(node.y)) : oy
    node === canvas && return (x, y)
    for field in (:elements, :content)
        hasproperty(node, field) || continue
        children = _gvd_force(getproperty(node, field))
        for child in (children isa AbstractVector ? children : (children,))
            found = _gvd_find_canvas(child, canvas, x, y)
            found === nothing || return found
        end
    end
    nothing
end

_gvd_corners(layout) = [(Int(vl.x), Int(vl.y)) for vl in layout.vertex_layouts]

# The editor that an operation of the chain is applied against: a path of the
# chain starts at the graph.
mutable struct _GraphVertexDragTestEditor
    document::Any
end

function test_graph_vertex_drag()
@testset "the drag of a vertex" begin

@testset "a press and a move drag a vertex, and the release pins it there" begin
    editor, backend, graph = _gvd_editor()
    drawing = _gvd_find_drawing(editor.iomap)
    @test drawing !== nothing
    layout = drawing.input
    origin = _gvd_place_of(editor, drawing.output)
    @test origin !== nothing
    before = _gvd_corners(layout)
    pad = unwrap_cell(drawing.projection.style).node_padding

    # A press on the frame of the second box, beside its content.
    vl = layout.vertex_layouts[2]
    x, y = origin[1] + Int(vl.x) - pad + 1, origin[2] + Int(vl.y) + 2
    _gvd_down!(editor, backend, x, y, 1.0)
    @test layout.drag !== nothing && !layout.drag.started
    _gvd_held!(editor, backend, x + 30, y + 20, 1.1)
    @test layout.drag.started
    @test editor.document.content.drag_path !== nothing
    _gvd_held!(editor, backend, x + 60, y + 40, 1.2)
    @test layout.drag.offset == (60, 40)

    # The moves change the drawing only: the box is drawn at the moved corner,
    # and the layout and the graph keep what they had.
    rect = _gvd_force(drawing.output.elements)[drawing.node_elements[2]]
    @test (Int(rect.x), Int(rect.y)) == (before[2][1] + 60 - pad, before[2][2] + 40 - pad)
    @test _gvd_corners(layout) == before
    @test isempty(graph.constraints)

    _gvd_up!(editor, backend, x + 60, y + 40, 1.3)
    @test layout.drag === nothing
    @test editor.document.content.drag_path === nothing
    vertex = graph.vertices[2]
    @test get_constraint_pins(graph.constraints) ==
          Dict(objectid(vertex) => Float64.(before[2] .+ (60, 40)))
    @test get_constraint_starts(graph.constraints) ==
          Dict(objectid(graph.vertices[i]) => Float64.(before[i]) for i in (1, 3))
    @test _gvd_corners(layout)[2] == before[2] .+ (60, 40)
end

@testset "a press on the content of a vertex drags the vertex too" begin
    editor, backend, graph = _gvd_editor()
    drawing = _gvd_find_drawing(editor.iomap)
    layout = drawing.input
    origin = _gvd_place_of(editor, drawing.output)
    before = _gvd_corners(layout)
    vl = layout.vertex_layouts[2]
    x, y = origin[1] + Int(vl.x) + Int(vl.w) ÷ 2, origin[2] + Int(vl.y) + Int(vl.h) ÷ 2
    _gvd_down!(editor, backend, x, y, 1.0)
    _gvd_held!(editor, backend, x + 10, y, 1.1)
    _gvd_held!(editor, backend, x + 40, y + 10, 1.2)
    _gvd_up!(editor, backend, x + 40, y + 10, 1.3)
    @test _gvd_corners(layout)[2] == before[2] .+ (40, 10)
end

@testset "a click with no move selects in the content and moves nothing" begin
    editor, backend, graph = _gvd_editor()
    drawing = _gvd_find_drawing(editor.iomap)
    layout = drawing.input
    origin = _gvd_place_of(editor, drawing.output)
    before = _gvd_corners(layout)
    vl = layout.vertex_layouts[2]
    x, y = origin[1] + Int(vl.x) + Int(vl.w) ÷ 2, origin[2] + Int(vl.y) + Int(vl.h) ÷ 2
    _gvd_down!(editor, backend, x, y, 1.0)
    _gvd_up!(editor, backend, x, y, 1.05)
    @test layout.drag === nothing
    @test isempty(graph.constraints)
    @test _gvd_corners(layout) == before
    selection = strip_reference_types(something(get_selection(graph), EmptyReference()))
    steps = collect(get_reference_steps(selection))
    @test length(steps) >= 3 && steps[1:3] == collect(get_reference_steps(
        strip_reference_types(@reference(graph, vertices[2].content))))
end

@testset "Escape puts the dragged vertex back" begin
    editor, backend, graph = _gvd_editor()
    drawing = _gvd_find_drawing(editor.iomap)
    layout = drawing.input
    origin = _gvd_place_of(editor, drawing.output)
    before = _gvd_corners(layout)
    pad = unwrap_cell(drawing.projection.style).node_padding
    vl = layout.vertex_layouts[1]
    x, y = origin[1] + Int(vl.x) - pad + 1, origin[2] + Int(vl.y) + 2
    _gvd_down!(editor, backend, x, y, 1.0)
    _gvd_held!(editor, backend, x + 50, y + 50, 1.1)
    _gvd_held!(editor, backend, x + 80, y + 70, 1.2)
    @test layout.drag.started
    _gvd_send!(editor, backend, KeyDown(:escape, ModifierKeys(); time = 1.3))
    @test layout.drag === nothing
    @test isempty(graph.constraints)
    @test _gvd_corners(layout) == before
    rect = _gvd_force(drawing.output.elements)[drawing.node_elements[1]]
    @test (Int(rect.x), Int(rect.y)) == (before[1][1] - pad, before[1][2] - pad)
end

@testset "the inverse of a drop puts the vertex back" begin
    graph = make_graph_document_example()
    projection = make_graph_projection_example(measure = _gvd_measure())
    iomap = print_document(projection, graph)
    drawing = _gvd_find_drawing(iomap)
    layout = drawing.input
    before = _gvd_corners(layout)
    pad = unwrap_cell(drawing.projection.style).node_padding
    editor = _GraphVertexDragTestEditor(graph)
    apply!(operation) = operation === nothing || evaluate_operation(editor, operation)
    vl = layout.vertex_layouts[3]
    x, y = Int(vl.x) - pad + 1, Int(vl.y) + 2
    apply!(read_intent(projection, iomap, MouseDown(:left, x, y, ModifierKeys(); time = 0.0)))
    apply!(read_intent(projection, iomap,
                       MouseMove(x + 70, y, MouseButtons(:left), ModifierKeys(); time = 0.0)))
    @test layout.drag.started
    drop = read_intent(projection, iomap, DragEnd(x + 70, y; time = 0.0))
    @test drop !== nothing
    # The undo buffer applies an operation this way, and keeps the way back.
    inverse = evaluate_invertible_operation!(editor, drop)
    @test inverse !== nothing
    @test _gvd_corners(layout)[3] == before[3] .+ (70, 0)
    apply!(inverse)
    @test isempty(graph.constraints)
    @test _gvd_corners(layout) == before
end

end
end
