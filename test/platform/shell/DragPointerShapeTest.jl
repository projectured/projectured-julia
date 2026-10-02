# The shape of the pointer during a drag, through the loop of a real editor.
#
# A part says the shape of its drag with `ChangeScreenPointerShapeOperation` at the
# start of the drag, and gives it back with `nothing` at its end. The screen keeps
# it and draws a region of it over each window, so the pointer keeps the shape
# wherever it goes. The helpers `_dt_*` are those of `DragTrackingTest.jl`.

# The screen that the editor shows.
_dps_screen(editor) = get_wrapped_document(editor.document)

# The canvas of the window `index` that the editor drew last.
_dps_window(editor, index = 1) =
    _dt_force(_dt_force(_dt_force(get_iomap_output(editor.iomap)).windows)[index].content)

# The shape at `(x, y)` of the window `W`.
_dps_shape(editor, x, y) = find_pointer_shape(_dps_window(editor), x, y)

function test_drag_pointer_shape()
@testset "the pointer keeps the shape of a drag wherever it goes" begin

@testset "a divider keeps the double arrow, and the release gives the shape back" begin
    split = WidgetSplitPane(:horizontal, Any[WidgetButton("left"), WidgetLabel("right")];
                            sizes = [200, 199])
    editor, backend = _dt_editor(split)
    @test _dps_shape(editor, 200, 50) === :double_arrow_horizontal
    over_button = _dt_place_of(editor, "left")
    @test _dps_shape(editor, over_button...) === :pointing_hand
    _dt_down!(editor, backend, 200, 50, 1.0)
    @test _dps_screen(editor).pointer_shape === :double_arrow_horizontal
    # A move down keeps the divider where it is: the shape holds over the button,
    # and outside the window.
    _dt_held!(editor, backend, 200, 280, 1.1)
    @test _dps_shape(editor, over_button...) === :double_arrow_horizontal
    @test _dps_shape(editor, -40, 500) === :double_arrow_horizontal
    _dt_up!(editor, backend, 200, 280, 1.2)
    @test _dps_screen(editor).pointer_shape === nothing
    @test _dps_shape(editor, over_button...) === :pointing_hand
    # Escape gives the shape back too.
    _dt_down!(editor, backend, 200, 50, 2.0)
    _dt_held!(editor, backend, 250, 50, 2.1)
    @test _dps_screen(editor).pointer_shape === :double_arrow_horizontal
    _dt_send!(editor, backend, KeyDown(:escape, _DT_NONE; time = 2.2))
    @test _dps_screen(editor).pointer_shape === nothing
end

@testset "a slider keeps the arrow over a button, and a lost release gives the shape back" begin
    root, slider, button = _dt_slider_scene()
    editor, backend = _dt_editor(root)
    @test _dps_shape(editor, 30, 130) === :pointing_hand
    _dt_down!(editor, backend, 60, 28, 1.0)
    @test _dps_screen(editor).pointer_shape === :arrow
    _dt_held!(editor, backend, 30, 130, 1.1)
    @test _dps_shape(editor, 30, 130) === :arrow
    # A move with no button held: the release was lost.
    _dt_send!(editor, backend, MouseMove(30, 130; time = 1.2))
    @test _dps_screen(editor).pointer_shape === nothing
    @test _dps_shape(editor, 30, 130) === :pointing_hand
end

@testset "a tab shows the closed hand over a group and the crossed circle where none takes it" begin
    tree, left, right = _dt_pane_scene()
    editor, backend = _dt_pane_editor(tree)
    place = _dt_place_of(editor, "b")
    @test place !== nothing
    if place !== nothing
        x, y = place[1] + 3, place[2] + 4
        @test _dps_shape(editor, x, y) === :open_hand
        _dt_send!(editor, backend, MouseMove(x, y; time = 0.9))
        _dt_down!(editor, backend, x, y, 1.0)
        # No drag before the small move: the screen keeps no shape.
        @test _dps_screen(editor).pointer_shape === nothing
        _dt_held!(editor, backend, x + 12, y, 1.1)
        @test tree.drag.started
        @test _dps_screen(editor).pointer_shape ===
              (tree.drag.target === nothing ? :crossed_circle : :closed_hand)
        _dt_held!(editor, backend, 300, 150, 1.2)
        @test tree.drag.target === right
        @test _dps_shape(editor, 300, 150) === :closed_hand
        # Outside the view of the tree, no group takes the tab.
        _dt_held!(editor, backend, 600, 500, 1.3)
        @test tree.drag.target === nothing
        @test _dps_shape(editor, 600, 500) === :crossed_circle
        _dt_held!(editor, backend, 300, 150, 1.4)
        @test _dps_screen(editor).pointer_shape === :closed_hand
        _dt_up!(editor, backend, 300, 150, 1.5)
        @test _dps_screen(editor).pointer_shape === nothing
        @test tree.drag === nothing
    end
end

@testset "a shape that no part gives back ends at the next release" begin
    root, _, _ = _dt_slider_scene()
    editor, backend = _dt_editor(root)
    _dps_screen(editor).pointer_shape = :closed_hand
    run_frame!(editor)
    @test _dps_shape(editor, 200, 200) === :closed_hand
    _dt_up!(editor, backend, 200, 200, 1.0)
    @test _dps_screen(editor).pointer_shape === nothing
    @test _dps_shape(editor, 200, 200) === :default
end

@testset "the screen draws the shape it keeps over every window" begin
    window(id, x, label) = WindowDocument(; id, x, y = 0, width = 400, height = 200,
                                            content = WidgetLabel(label))
    screen = ScreenDocument([window(:one, 0, "one"), window(:two, 500, "two")])
    projection = make_widget_popup_projection_example(measure = _dt_measure())
    iomap = print_document(projection, screen)
    content(index) = _dt_force(_dt_force(_dt_force(get_iomap_output(iomap)).windows)[index].content)
    @test find_pointer_shape(content(2), 300, 150) === :default
    screen.pointer_shape = :closed_hand
    @test find_pointer_shape(content(1), 300, 150) === :closed_hand
    @test find_pointer_shape(content(2), 300, 150) === :closed_hand
    @test find_pointer_shape(content(2), -100, -100) === :closed_hand
    screen.pointer_shape = nothing
    @test find_pointer_shape(content(1), 300, 150) === :default
    # The content is the first element of the canvas of its window: a path into
    # it carries that step in the output, and the region maps to no part.
    screen_iomap = only(filter(m -> m isa ScreenToScreenIoMap, _dps_iomaps(iomap)))
    content_path = ConcreteReference(FieldReferenceStep("windows"),
        ConcreteReference(ElementReferenceStep(1),
            ConcreteReference(FieldReferenceStep("content"), EmptyReference())))
    image = map_reference_forward(screen_iomap.projection, screen_iomap, content_path)
    @test image == ConcreteReference(FieldReferenceStep("windows"),
        ConcreteReference(ElementReferenceStep(1),
            ConcreteReference(FieldReferenceStep("content"),
                ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(ElementReferenceStep(1), EmptyReference())))))
    # Back, the step goes again, and the content maps its own root.
    content_iomap = screen_iomap.window_iomaps[1].content_iomap
    root = map_reference_backward(content_iomap.projection, content_iomap, EmptyReference())
    @test map_reference_backward(screen_iomap.projection, screen_iomap, image) ==
          (root === nothing ? nothing : concat_references(content_path, root))
    region = ConcreteReference(FieldReferenceStep("windows"),
        ConcreteReference(ElementReferenceStep(1),
            ConcreteReference(FieldReferenceStep("content"),
                ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(ElementReferenceStep(2), EmptyReference())))))
    @test map_reference_backward(screen_iomap.projection, screen_iomap, region) === nothing
end

@testset "a shape that reaches the editor applies to the screen it shows" begin
    screen = ScreenDocument()
    evaluate_operation((; document = screen), ChangeScreenPointerShapeOperation(:ibeam))
    @test screen.pointer_shape === :ibeam
    evaluate_operation((; document = screen), ChangeScreenPointerShapeOperation(nothing))
    @test screen.pointer_shape === nothing
end

end # @testset
end # test_drag_pointer_shape

# The IO maps under `iomap`, through the fields that hold IO maps.
function _dps_iomaps(iomap, found = Any[], seen = IdDict{Any,Bool}())
    iomap = _dt_force(iomap)
    iomap isa IoMap || return found
    haskey(seen, iomap) && return found
    seen[iomap] = true
    push!(found, iomap)
    for child in something(get_child_iomaps(iomap), ())
        _dps_iomaps(child, found, seen)
    end
    for field in (:inner_iomap,)
        hasproperty(iomap, field) && _dps_iomaps(getproperty(iomap, field), found, seen)
    end
    found
end
