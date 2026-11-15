# The drag of a vertex: a press on a vertex and a small move start it, each move
# moves the vertex in the drawing only, and the release writes one edit of the
# constraints of the graph: a pin for the dragged vertex and a start for each
# other vertex. The editor tests run the real editor with the drag tracking
# screen, so the parts of the drag reach the graph by its path, as in the app.

_gvd_measure() = FixedMeasure(10, 18, 6, 0)

_gvd_force(value) = value isa AbstractCell ? _gvd_force(value[]) : value

# A graph in the window `W` of a drag tracking screen, and the editor that shows
# it: the graph of the example, unless the caller gives one and its projection.
function _gvd_editor(graph = make_graph_document_example();
                     projection = make_graph_projection_example(measure = _gvd_measure()),
                     width = 900, height = 700)
    scene = make_window_scene(graph, "W"; width, height)
    opened = make_opened_window_projections(; measure = _gvd_measure())
    composed = make_window_scene_projection(projection; opened_window_projections = opened)
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

# The box `(x, y, w, h)` of the content of vertex `i` where the drawing draws it,
# and the margin by which the drawing moves the layout right and down.
_gvd_drawn_box(drawing, i) = drawing.drawn_boxes[i]
_gvd_margin(drawing) = (style = unwrap_cell(drawing.projection.style);
                        style.node_padding)

# The operations in an answer, with each compound opened.
_gvd_operations(operation) = operation isa CompoundOperation ?
    reduce(vcat, (_gvd_operations(member) for member in operation.operations); init = Any[]) :
    operation === nothing ? Any[] : Any[operation]

# The point of the graph where a press on the box of vertex `i` starts a drag of a
# part of its content, such as the edge of a column of a table, found by reading
# presses at the drawing and applying none; or `nothing`.
function _gvd_find_content_drag_point(drawing, i)
    bx, by, bw, _ = _gvd_drawn_box(drawing, i)
    for y in by:2:(by + 40), x in bx:(bx + bw - 1)
        answer = read_intent(drawing.projection, drawing, MouseDown(:left, x, y, ModifierKeys(); time = 0.0))
        any(op -> op isa StartDragOperation &&
                  !isempty(get_reference_steps(strip_reference_types(op.path))),
            _gvd_operations(answer)) && return (x, y)
    end
    nothing
end

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
    margin = _gvd_margin(drawing)

    # A press on the frame of the second box, beside its content.
    box = _gvd_drawn_box(drawing, 2)
    x, y = origin[1] + box[1] - pad + 1, origin[2] + box[2] + 2
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
    @test (Int(rect.x), Int(rect.y)) == (before[2][1] + margin + 60 - pad, before[2][2] + margin + 40 - pad)
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
    box = _gvd_drawn_box(drawing, 2)
    x, y = origin[1] + box[1] + box[3] ÷ 2, origin[2] + box[2] + box[4] ÷ 2
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
    box = _gvd_drawn_box(drawing, 2)
    x, y = origin[1] + box[1] + box[3] ÷ 2, origin[2] + box[2] + box[4] ÷ 2
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
    margin = _gvd_margin(drawing)
    box = _gvd_drawn_box(drawing, 1)
    x, y = origin[1] + box[1] - pad + 1, origin[2] + box[2] + 2
    _gvd_down!(editor, backend, x, y, 1.0)
    _gvd_held!(editor, backend, x + 50, y + 50, 1.1)
    _gvd_held!(editor, backend, x + 80, y + 70, 1.2)
    @test layout.drag.started
    _gvd_send!(editor, backend, KeyDown(:escape, ModifierKeys(); time = 1.3))
    @test layout.drag === nothing
    @test isempty(graph.constraints)
    @test _gvd_corners(layout) == before
    rect = _gvd_force(drawing.output.elements)[drawing.node_elements[1]]
    @test (Int(rect.x), Int(rect.y)) == (before[1][1] + margin - pad, before[1][2] + margin - pad)
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
    margin = _gvd_margin(drawing)
    box = _gvd_drawn_box(drawing, 3)
    x, y = box[1] - pad + 1, box[2] + 2
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
    # The other vertices stay where they were drawn.
    @test _gvd_corners(layout)[1:2] == before[1:2]
    @test layout.drag === nothing
    apply!(inverse)
    @test isempty(graph.constraints)
    @test _gvd_corners(layout) == before
    # The way back takes back the edit and leaves the drag ended, so the box is
    # drawn where the layout places it.
    @test layout.drag === nothing
    rect = _gvd_force(drawing.output.elements)[drawing.node_elements[3]]
    @test (Int(rect.x), Int(rect.y)) == before[3] .+ (margin - pad, margin - pad)
end

@testset "a drag that a part of a content starts reaches that part" begin
    slider = WidgetSlider(0.0; width = 200)
    v_slider = GraphVertex(slider)
    v_text = GraphVertex(JsonString("x"))
    graph = GraphGraph([v_slider, v_text], [GraphEdge(v_slider, v_text)])
    projection = make_graph_projection_example(measure = _gvd_measure(),
                                               content = NaturalToGraphics(measure = _gvd_measure()))
    editor, backend, _ = _gvd_editor(graph; projection)
    drawing = _gvd_find_drawing(editor.iomap)
    layout = drawing.input
    origin = _gvd_place_of(editor, drawing.output)
    before = _gvd_corners(layout)
    knob = _gvd_find_content_drag_point(drawing, 1)
    @test knob !== nothing
    knob === nothing && return
    x, y = origin .+ knob
    _gvd_down!(editor, backend, x, y, 1.0)
    @test layout.drag === nothing
    pressed = Float64(slider.value)
    _gvd_held!(editor, backend, x + 30, y, 1.1)
    _gvd_held!(editor, backend, x + 60, y, 1.2)
    # The moves reach the slider by its path, so its value follows the pointer.
    @test Float64(slider.value) > pressed
    _gvd_up!(editor, backend, x + 60, y, 1.3)
    @test !slider.dragging
    @test layout.drag === nothing
    @test isempty(graph.constraints)
    @test _gvd_corners(layout) == before
end

@testset "a press ends only by a left release or by a new press" begin
    graph = make_graph_document_example()
    projection = make_graph_projection_example(measure = _gvd_measure())
    iomap = print_document(projection, graph)
    drawing = _gvd_find_drawing(iomap)
    layout = drawing.input
    pad = unwrap_cell(drawing.projection.style).node_padding
    editor = _GraphVertexDragTestEditor(graph)
    apply!(operation) = operation === nothing || evaluate_operation(editor, operation)
    read!(event) = apply!(read_intent(projection, iomap, event))
    box = _gvd_drawn_box(drawing, 2)
    x, y = box[1] - pad + 1, box[2] + 2
    left = MouseButtons(:left)

    # A release of the right button keeps the press of the left one.
    read!(MouseDown(:left, x, y, ModifierKeys(); time = 0.0))
    read!(MouseUp(:right, x, y, ModifierKeys(); time = 0.0))
    @test layout.drag !== nothing && !layout.drag.started
    # A move shorter than a click allows on each axis is no drag.
    read!(MouseMove(x + 4, y + 4, left, ModifierKeys(); time = 0.0))
    @test !layout.drag.started
    read!(MouseMove(x + 5, y, left, ModifierKeys(); time = 0.0))
    @test layout.drag.started

    # A press whose release came to no part of the graph ends at the next press.
    read!(DragCancel(; time = 0.0))
    read!(MouseDown(:left, x, y, ModifierKeys(); time = 0.0))
    @test layout.drag !== nothing
    # The corner of the drawing is on no box.
    read!(MouseDown(:left, 1, 1, ModifierKeys(); time = 0.0))
    @test layout.drag === nothing
end

@testset "where two boxes overlap, the box on top takes the press and the point" begin
    v1 = GraphVertex(JsonString("aaaaaaaa"))
    v2 = GraphVertex(JsonString("bbbbbbbb"))
    graph = GraphGraph([v1, v2], GraphEdge[])
    chain = GraphToGraphics(GridEmbedding();
                            constraints = _ -> [GraphConstraint(v1, :pin, (0, 0)),
                                                GraphConstraint(v2, :pin, (20, 10))])
    projection = NestingProjection(chain; recursion = make_mixed_projection_example(measure = _gvd_measure()))
    iomap = print_document(projection, graph)
    drawing = _gvd_find_drawing(iomap)
    layout = drawing.input
    # The point is on the content of both boxes, where the drawing draws them.
    first_box = _gvd_drawn_box(drawing, 1)
    x, y = (30, 12) .+ _gvd_margin(drawing)
    @test first_box[1] <= x < first_box[1] + first_box[3]
    @test first_box[2] <= y < first_box[2] + first_box[4]
    editor = _GraphVertexDragTestEditor(graph)
    operation = read_intent(projection, iomap, MouseDown(:left, x, y, ModifierKeys(); time = 0.0))
    evaluate_operation(editor, operation)
    @test layout.drag !== nothing && layout.drag.index == 2
    back = map_reference_backward(projection, iomap, PointReferenceStep(x, y))
    steps = collect(get_reference_steps(strip_reference_types(back)))
    @test steps[1:2] == collect(get_reference_steps(strip_reference_types(@reference(graph, vertices[2]))))
end

end
end
