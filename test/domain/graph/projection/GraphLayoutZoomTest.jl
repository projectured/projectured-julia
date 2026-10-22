# The zoom of the layout of a graph: Ctrl and the wheel move the centre of each
# box and keep its size, the engine does not run again, the edges still end at the
# rims, and a drop at a zoom stays where the person put it. The helpers of the
# drag tests find the drawing and apply the answers.

_glz_notch(x, y, notches = 1) = MouseScroll(0, notches, x, y, ModifierKeys(ctrl = true); time = 0.0)

# The drawing of the graph of the example, printed without an editor, and a way to
# apply the answers of its readers.
function _glz_print()
    graph = make_graph_document_example()
    projection = make_graph_projection_example(measure = _gvd_measure())
    iomap = print_document(projection, graph)
    drawing = _gvd_find_drawing(iomap)
    editor = _GraphVertexDragTestEditor(graph)
    apply!(operation) = operation === nothing || evaluate_operation(editor, operation)
    read!(event) = apply!(read_intent(projection, iomap, event))
    (graph, drawing, read!)
end

_glz_get_box(drawing, i) =
    (rect = _gvd_force(drawing.output.elements)[drawing.node_elements[i]];
     (Int(rect.x), Int(rect.y), Int(rect.w), Int(rect.h)))

_glz_get_centre(box) = (box[1] + box[3] / 2, box[2] + box[4] / 2)

function test_graph_layout_zoom()
@testset "the zoom of the layout" begin

@testset "Ctrl and the wheel move the centres, and the boxes keep their size" begin
    graph, drawing, read! = _glz_print()
    layout = drawing.input
    count = length(layout.vertex_layouts)
    placed = collect(layout.vertex_layouts)
    before = [_glz_get_box(drawing, i) for i in 1:count]
    distance = hypot((_glz_get_centre(before[2]) .- _glz_get_centre(before[1]))...)
    top_left = (minimum(first, before), minimum(box -> box[2], before))
    @test layout.zoom === nothing

    # A notch over the content of the second box. The content takes no wheel, so
    # the layout zooms.
    x, y = before[2][1] + 4, before[2][2] + 4
    read!(_glz_notch(x, y))
    @test layout.zoom.scale == 1.15
    after = [_glz_get_box(drawing, i) for i in 1:count]
    @test isapprox(hypot((_glz_get_centre(after[2]) .- _glz_get_centre(after[1]))...),
                   1.15 * distance; atol = 1.5)
    @test [box[3:4] for box in after] == [box[3:4] for box in before]
    # The top-left corner of the drawing stays where it is.
    @test (minimum(first, after), minimum(box -> box[2], after)) == top_left
    # The engine did not run: the layout holds the same vertex layouts.
    @test all(layout.vertex_layouts[i] === placed[i] for i in 1:count)
    # The canvas grows with the drawing.
    @test Int(drawing.output.w) >= maximum(box -> box[1] + box[3], after)

    # A turn without Ctrl does not zoom.
    read!(MouseScroll(0, 1, x, y, ModifierKeys(); time = 0.0))
    @test layout.zoom.scale == 1.15

    # A turn toward the person zooms out, and the zoom stops at its limits.
    for _ in 1:40
        read!(_glz_notch(x, y, -1))
    end
    @test layout.zoom.scale == 0.25
    @test read_intent(drawing.projection, drawing, _glz_notch(x, y, -1)) === nothing
    for _ in 1:40
        read!(_glz_notch(x, y))
    end
    @test layout.zoom.scale == 4.0
    @test read_intent(drawing.projection, drawing, _glz_notch(x, y)) === nothing
end

@testset "a zoomed edge ends at the rim of its target box" begin
    graph, drawing, read! = _glz_print()
    box = _glz_get_box(drawing, 1)
    for _ in 1:5
        read!(_glz_notch(box[1] + 4, box[2] + 4))
    end
    # The first edge goes from the first vertex to the second, with an arrowhead.
    line = first(filter(e -> e isa GraphicsPolyline, collect(_gvd_force(drawing.output.elements))))
    @test line.end_arrow
    rect(i) = _gvd_force(drawing.output.elements)[drawing.node_elements[i]]
    @test _gpt_is_on_rim(rect(1), first(collect(line.points)))
    @test _gpt_is_on_rim(rect(2), last(collect(line.points)))
end

@testset "a drop at a zoom pins the vertex where the release put it" begin
    graph, drawing, read! = _glz_print()
    layout = drawing.input
    box = _glz_get_box(drawing, 1)
    for _ in 1:5
        read!(_glz_notch(box[1] + 4, box[2] + 4))
    end
    scale = layout.zoom.scale
    before = [_glz_get_box(drawing, i) for i in 1:3]
    # A press on the frame of the third box, beside its content, and a drag.
    x, y = before[3][1] + 1, before[3][2] + 10
    read!(MouseDown(:left, x, y, ModifierKeys(); time = 0.0))
    read!(MouseMove(x + 70, y + 30, MouseButtons(:left), ModifierKeys(); time = 0.0))
    @test layout.drag.started
    @test _glz_get_box(drawing, 3)[1:2] == before[3][1:2] .+ (70, 30)
    read!(DragEnd(x + 70, y + 30; time = 0.0))
    @test layout.drag === nothing
    @test layout.zoom.scale == scale
    # The engine placed the vertex at its pin, and the zoom draws it where the
    # release put it, up to the rounding of a corner of the layout. The other
    # vertices stay.
    dropped = _glz_get_box(drawing, 3)
    @test all(abs.(dropped[1:2] .- (before[3][1:2] .+ (70, 30))) .<= ceil(Int, scale / 2))
    @test [_glz_get_box(drawing, i) for i in 1:2] == before[1:2]
end

@testset "Ctrl and the wheel in a window zoom the graph" begin
    editor, backend, graph = _gvd_editor()
    drawing = _gvd_find_drawing(editor.iomap)
    layout = drawing.input
    origin = _gvd_place_of(editor, drawing.output)
    box = _glz_get_box(drawing, 2)
    x, y = origin[1] + box[1] + 4, origin[2] + box[2] + 4
    _gvd_send!(editor, backend, MouseScroll(0, 1, x, y, ModifierKeys(ctrl = true); time = 1.0))
    @test layout.zoom !== nothing && layout.zoom.scale == 1.15
end

end
end
