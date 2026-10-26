# A graph view holds itself in a scroll pane: a small graph draws where the plain
# chain draws it and does not scroll, the pane paints no fill, a zoomed graph
# scrolls by a plain turn of the wheel while Ctrl and the wheel still zoom it, and
# a click and a reference still reach a vertex. The helpers of the drag and zoom
# tests run the editor and read the drawing.

# Three cards in one column, joined by two edges: small enough for the window of
# the drag tests, 900 × 700 px, and taller than it at a zoom of 4.
function _gsp_make_graph()
    vertices = [GraphVertex(JsonString(name)) for name in ("alpha", "beta", "gamma")]
    GraphGraph(vertices, [GraphEdge(vertices[1], vertices[2]), GraphEdge(vertices[2], vertices[3])])
end

# The graph view, with the content dispatcher of the graph example: in a scroll
# pane, or as the plain chain.
function _gsp_make_projection(; scrolling::Bool = true)
    measure = _gvd_measure()
    content = TypeDispatchingProjection(WidgetTable => make_table_projection_example(; measure),
                                        Any         => make_mixed_projection_example(; measure))
    stages = GraphToGraphics(GridEmbedding(columns = 1, rank_sep = 120))
    NestingProjection(scrolling ? make_scrolling_graph_projection(stages; measure) : stages;
                      recursion = content)
end

# The IO map of the scroll pane that holds `graph`, found in the IO map tree.
function _gsp_find_pane(root, graph)
    seen = Set{UInt}()
    stack = Any[root]
    while !isempty(stack)
        value = _gvd_force(pop!(stack))
        if value isa WidgetScrollPaneToGraphicsCanvasIoMap
            _gvd_force(getfield(value.input, :content)) === graph && return value
        end
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

function test_graph_scroll_pane()
@testset "the scroll pane of a graph view" begin

@testset "a small graph in a pane draws where the plain chain draws it, and does not scroll" begin
    plain_editor, _, _ = _gvd_editor(_gsp_make_graph(); projection = _gsp_make_projection(scrolling = false))
    plain = _gvd_find_drawing(plain_editor.iomap)
    plain_place = _gvd_place_of(plain_editor, plain.output)
    plain_boxes = [_glz_get_box(plain, i) for i in 1:3]

    graph = _gsp_make_graph()
    editor, backend, _ = _gvd_editor(graph; projection = _gsp_make_projection())
    drawing = _gvd_find_drawing(editor.iomap)
    @test Int(drawing.output.w) <= 900 && Int(drawing.output.h) <= 700
    @test _gvd_place_of(editor, drawing.output) == plain_place
    @test [_glz_get_box(drawing, i) for i in 1:3] == plain_boxes

    # The pane paints no fill, so the graph stays transparent.
    pane = _gsp_find_pane(editor.iomap, graph)
    @test pane !== nothing
    @test !any(e -> e isa GraphicsRect && !is_color_transparent(_gvd_force(e.color)),
               collect(_gvd_force(pane.output.elements)))

    # A plain turn of the wheel moves nothing.
    box = _glz_get_box(drawing, 2)
    x, y = plain_place .+ (box[1] + 4, box[2] + 4)
    _gvd_send!(editor, backend, MouseScroll(0, -1, x, y, ModifierKeys(); time = 1.0))
    @test _gvd_place_of(editor, drawing.output) == plain_place
end

@testset "a zoomed graph scrolls by a plain turn, and Ctrl and the wheel zoom it" begin
    graph = _gsp_make_graph()
    editor, backend, _ = _gvd_editor(graph; projection = _gsp_make_projection())
    drawing = _gvd_find_drawing(editor.iomap)
    layout = drawing.input
    origin = _gvd_place_of(editor, drawing.output)
    box = _glz_get_box(drawing, 1)
    x, y = origin .+ (box[1] + 4, box[2] + 4)
    for _ in 1:12
        _gvd_send!(editor, backend, MouseScroll(0, 1, x, y, ModifierKeys(ctrl = true); time = 1.0))
    end
    @test layout.zoom.scale == 4.0
    # The window is 900 × 700 px, and the zoomed graph is larger.
    @test Int(drawing.output.h) > 700

    before = _gvd_place_of(editor, drawing.output)
    _gvd_send!(editor, backend, MouseScroll(0, -1, 300, 300, ModifierKeys(); time = 2.0))
    after = _gvd_place_of(editor, drawing.output)
    @test after[1] == before[1]
    @test after[2] < before[2]
    @test layout.zoom.scale == 4.0
end

@testset "a click selects in the content of a vertex through the pane" begin
    graph = _gsp_make_graph()
    editor, backend, _ = _gvd_editor(graph; projection = _gsp_make_projection())
    drawing = _gvd_find_drawing(editor.iomap)
    origin = _gvd_place_of(editor, drawing.output)
    box = _gvd_drawn_box(drawing, 2)
    x, y = origin[1] + box[1] + box[3] ÷ 2, origin[2] + box[2] + box[4] ÷ 2
    _gvd_down!(editor, backend, x, y, 1.0)
    _gvd_up!(editor, backend, x, y, 1.05)
    selection = strip_reference_types(something(get_selection(graph), EmptyReference()))
    steps = collect(get_reference_steps(selection))
    @test length(steps) >= 3 && steps[1:3] == collect(get_reference_steps(
        strip_reference_types(@reference(graph, vertices[2].content))))
end

@testset "the graph of the example fits a window, with each vertex at its natural size" begin
    # A content that fills the room it gets, such as the table of the example,
    # takes no room from the window: it has the size that it has with no room.
    graph = make_graph_document_example()
    alone = _gvd_find_drawing(print_document(make_graph_projection_example(measure = _gvd_measure()), graph))
    sizes = [box[3:4] for box in alone.drawn_boxes]
    editor, backend, _ = _gvd_editor(graph)
    drawing = _gvd_find_drawing(editor.iomap)
    @test [box[3:4] for box in drawing.drawn_boxes] == sizes
    @test all(box -> box[1] + box[3] <= 900 && box[2] + box[4] <= 700, drawing.drawn_boxes)

    # The pointer, Tab and a click map points and paths back through the pane, and
    # none of them makes a fault.
    for (k, (x, y)) in enumerate(((5, 5), (60, 40), (300, 200), (450, 300), (700, 500)))
        _gvd_send!(editor, backend, MouseMove(x, y, MouseButtons(), ModifierKeys(); time = 1.0 + k / 10))
    end
    _gvd_send!(editor, backend, KeyDown(:tab, ModifierKeys(); time = 2.0))
    box = drawing.drawn_boxes[2]
    _gvd_down!(editor, backend, box[1] + 5, box[2] + 5, 3.0)
    _gvd_up!(editor, backend, box[1] + 5, box[2] + 5, 3.05)
    @test isempty(get_fault_records(get_fault_store(editor)))
end

@testset "a vertex maps forward to its box through the pane" begin
    graph = _gsp_make_graph()
    projection = _gsp_make_projection()
    iomap = print_document(projection, graph)
    for i in 1:length(graph.vertices)
        forward = map_reference_forward(projection, iomap, @reference(graph, vertices[i]))
        @test forward !== nothing
        forward === nothing || @test evaluate_reference(iomap.output, forward) isa GraphicsRect
    end
end

@testset "a zoom, a scroll, a click and an edit keep the view of the graph" begin
    # A window smaller than the drawing, so the pane scrolls from the start.
    editor, backend, graph = _gvd_editor(; width = 360, height = 300)
    drawing = _gvd_find_drawing(editor.iomap)
    pane = _gsp_find_pane(editor.iomap, graph)
    scroll() = (p = getfield(pane.input, :scroll_position)[]; (Int(p.x[]), Int(p.y[])))
    place(i) = _gvd_place_of(editor, drawing.output) .+ drawing.drawn_boxes[i][1:2]
    centre(i) = place(i) .+ drawing.drawn_boxes[i][3:4] .÷ 2
    clock = Ref(1.0)
    send!(event) = _gvd_send!(editor, backend, event)
    tick() = (clock[] += 1.0)
    near(a, b) = all(abs.(a .- b) .<= 1)
    # The zoom maps the centre of a box, so a box that grows by `growth` at the
    # zoom `scale` moves its corner by `(scale - 1) * growth / 2` to the side.
    grown(corner, growth) = corner .+ ((drawing.input.zoom.scale - 1) * growth / 2, 0)

    # A turn of the wheel down moves the JSON box up by the scroll.
    start = place(2)
    send!(MouseScroll(0, -1, 180, 150, ModifierKeys(); time = tick()))
    @test scroll()[2] > 0
    @test place(2) == start .- scroll()

    # Four notches of the zoom over the JSON box: it stays under the pointer.
    shown = place(2)
    x, y = centre(2)
    for _ in 1:4
        send!(MouseScroll(0, 1, x, y, ModifierKeys(ctrl = true); time = tick()))
        @test near(place(2), shown)
    end

    # A click into the key "active", and the text 42: the box grows, and it and
    # the view stay where they are.
    x, y = centre(2)
    send!(MouseDown(:left, x, y, ModifierKeys(); time = tick()))
    send!(MouseUp(:left, x, y, ModifierKeys(); time = tick()))
    @test string(strip_reference_types(get_selection(graph))) == ".vertices[2].content.entries[2].key{5}"
    view, width, others = scroll(), drawing.drawn_boxes[2][3], (place(1), place(3))
    for ch in "42"
        send!(KeyPress(ch; time = tick()))
    end
    @test string(strip_reference_types(get_selection(graph))) == ".vertices[2].content.entries[2].key{7}"
    @test drawing.drawn_boxes[2][3] > width
    @test scroll() == view
    @test near(place(2), grown(shown, drawing.drawn_boxes[2][3] - width))
    @test (place(1), place(3)) == others

    # One more notch over the box keeps it under the pointer.
    x, y = centre(2)
    shown = place(2)
    send!(MouseScroll(0, 1, x, y, ModifierKeys(ctrl = true); time = tick()))
    @test near(place(2), shown)

    # Turns down to the end of the drawing do not pin the view there: one more
    # letter makes the box wider, and the view stays.
    for _ in 1:20
        send!(MouseScroll(0, -1, 180, 150, ModifierKeys(); time = tick()))
    end
    @test getfield(pane.input, :follow_end)[] === nothing
    view, kept, width = scroll(), place(2), drawing.drawn_boxes[2][3]
    send!(KeyPress('x'; time = tick()))
    @test string(strip_reference_types(get_selection(graph))) == ".vertices[2].content.entries[2].key{8}"
    @test scroll() == view
    @test near(place(2), grown(kept, drawing.drawn_boxes[2][3] - width))
    @test isempty(get_fault_records(get_fault_store(editor)))
end

end
end
