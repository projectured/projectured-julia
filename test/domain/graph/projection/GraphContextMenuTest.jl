# The menu of a graph: a right click on a graph opens a menu that switches its
# edges between straight lines and curves. The first test runs a real editor with
# the context menu window, as a person does; the helpers of the drag tests find
# the drawing and its place.

_gcm_force(value) = value isa AbstractCell ? _gcm_force(value[]) : value

# The graph of the example in the window `W` of an editor that has the context
# menu window.
function _gcm_editor()
    graph = make_graph_document_example()
    scene = make_window_scene(graph, "W"; width = 900, height = 700)
    opened = make_opened_window_projections(; measure = _gvd_measure())
    composed = make_window_scene_projection(make_graph_projection_example(measure = _gvd_measure());
                                            opened_window_projections = opened)
    document, projection = make_tracking_screen(scene, composed;
                                                inner_wrappers = [wrap_context_menu_window])
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend, scene, graph)
end

_gcm_send!(editor, backend, event; window = :W) =
    (push_event!(backend, WindowInput(window, event)); run_frame!(editor))

# A press and a release of `button` in place, which the gesture tracker makes a
# click of.
function _gcm_click!(editor, backend, button::Symbol, x, y, time; window = :W)
    _gcm_send!(editor, backend, MouseDown(button, x, y, ModifierKeys(); time); window)
    _gcm_send!(editor, backend, MouseUp(button, x, y, ModifierKeys(); time = time + 0.05); window)
end

_gcm_menus(scene) = [window for window in scene.windows if window.style === :popup]

# The drawn content of the window `id`, as the editor printed it.
function _gcm_drawn_window(editor, scene, id::Symbol)
    windows = _gcm_force(_gcm_force(get_iomap_output(editor.iomap)).windows)
    index = findfirst(window -> window.id === id, collect(scene.windows))
    _gcm_force(windows[index].content)
end

# Where `text` is drawn in `node`, in the frame of `node`, or `nothing`.
function _gcm_place_of(node, text, ox = 0, oy = 0)
    node = _gcm_force(node)
    node === nothing && return nothing
    x = hasproperty(node, :x) ? ox + Int(_gcm_force(node.x)) : ox
    y = hasproperty(node, :y) ? oy + Int(_gcm_force(node.y)) : oy
    hasproperty(node, :text) && _gcm_force(node.text) == text && return (x, y)
    for field in (:elements, :content)
        hasproperty(node, field) || continue
        children = _gcm_force(getproperty(node, field))
        for child in (children isa AbstractVector ? children : (children,))
            found = _gcm_place_of(child, text, x, y)
            found === nothing || return found
        end
    end
    nothing
end

# The elements that draw the edges.
_gcm_collect_lines(drawing) = filter(e -> e isa Union{GraphicsPolyline,GraphicsSpline},
                                     collect(_gcm_force(drawing.output.elements)))

function test_graph_context_menu()
@testset "the menu of a graph" begin

@testset "the menu of a graph switches its edges between lines and curves" begin
    editor, backend, scene, graph = _gcm_editor()
    drawing = _gvd_find_drawing(editor.iomap)
    @test !isempty(_gcm_collect_lines(drawing))
    @test all(e -> e isa GraphicsPolyline, _gcm_collect_lines(drawing))
    # A right click on the graph, at its top-left corner, beside every box.
    x, y = _gvd_place_of(editor, drawing.output) .+ (2, 2)
    time = 1.0
    for (label, kind) in (("Curved edges", GraphicsSpline), ("Straight edges", GraphicsPolyline))
        _gcm_click!(editor, backend, :right, x, y, time)
        window = only(_gcm_menus(scene))
        place = _gcm_place_of(_gcm_drawn_window(editor, scene, window.id), label)
        @test place !== nothing
        place === nothing && continue
        _gcm_click!(editor, backend, :left, place[1] + 2, place[2] + 2, time + 1; window = window.id)
        @test isempty(_gcm_menus(scene))
        lines = _gcm_collect_lines(drawing)
        @test !isempty(lines) && all(e -> e isa kind, lines)
        time += 2
    end
    @test drawing.input.edge_shape === :straight
end

@testset "a right click on the content of a vertex gives the menu of the graph too" begin
    graph = make_graph_document_example()
    projection = make_graph_projection_example(measure = _gvd_measure())
    iomap = print_document(projection, graph)
    drawing = _gvd_find_drawing(iomap)
    box = drawing.drawn_boxes[2]
    answer = read_intent(projection, iomap,
                         MouseClick(:right, box[1] + 5, box[2] + 5, 1, ModifierKeys(); time = 0.0))
    menu = answer isa WrappingOperation ? get_wrapped_operation(answer) : answer
    @test menu isa OpenContextMenuOperation
    menu isa OpenContextMenuOperation || return
    labels = [string(item.action.label) for (_, layer, _) in menu.layers
              for item in _gcm_force(layer.elements) if item isa WidgetMenuItem]
    @test "Straight edges" in labels
    @test "Curved edges" in labels
end

end
end
