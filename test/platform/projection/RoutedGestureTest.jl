# A gesture that follows a route through widget containers. The route names the
# part that the gesture is for, so the containers pass it on by reference and
# never by the position it holds: a move reaches the widget that the route names,
# wherever the pointer is.
function test_routed_gesture()
@testset "a gesture follows a route through widget containers" begin

_projection() = make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0))
_plain(op) = op isa ReplaceViewStateOperation ? get_wrapped_operation(op) : op

# A button inside a composite inside the second pane of a split pane, beside
# another button that the route does not name.
function _routed_scene()
    other = WidgetButton("Other")
    button = WidgetButton("Go"; position = Point2D(0, 40))
    split = WidgetSplitPane(:horizontal, Any[WidgetLabel("left"), WidgetComposite(Any[other, button])];
                            sizes = [300, 300])
    projection = _projection()
    (split, other, button, projection, print_document(projection, split))
end

_route_to_button() = extend_reference(EmptyReference(),
    FieldReferenceStep("elements"), ElementReferenceStep(2),
    FieldReferenceStep("elements"), ElementReferenceStep(2))

function _read_routed(projection, iomap, gesture, route)
    change = read_intent(projection, nothing, Intent(gesture, nothing, "", "", route), iomap)
    change isa Intent ? change.operation : change
end

@testset "a move with a route ends the press of the button it names, and no other" begin
    split, other, button, projection, iomap = _routed_scene()
    button.pressed = true
    other.pressed = true
    # The position is far from both buttons: the route alone names the part, and
    # a move with no button held off the button ends its press.
    op = _read_routed(projection, iomap, MouseMove(590, 5; time = 0.0), _route_to_button())
    @test op isa ReplaceViewStateOperation
    @test _plain(op).document === button
    evaluate_operation(nothing, op)
    @test button.pressed == false
    @test other.pressed == true
end

@testset "a route that names nothing the containers print answers nothing" begin
    split, other, button, projection, iomap = _routed_scene()
    route = extend_reference(EmptyReference(), FieldReferenceStep("elements"), ElementReferenceStep(3))
    @test _read_routed(projection, iomap, MouseMove(5, 5; time = 0.0), route) === nothing
end

# The value that an answer writes, or `nothing`: a slider writes the value of the
# point that it reads, so the value shows the point that reached it.
function _written_value(op)
    op isa ReplaceViewStateOperation && return _written_value(get_wrapped_operation(op))
    if op isa CompoundOperation
        for member in op.operations
            value = _written_value(member)
            value === nothing || return value
        end
    end
    op isa ReplaceReferencedValueOperation && op.value isa Real ? op.value : nothing
end

# The path of the part under `(x, y)`, which a move with no button held names.
function _part_at(projection, iomap, x, y)
    op = read_intent(projection, iomap, MouseMove(x, y; time = 0.0))
    op isa ReplaceMouseTargetOperation && return strip_reference_types(op.path)
    if op isa CompoundOperation
        for member in op.operations
            member isa ReplaceMouseTargetOperation && return strip_reference_types(member.path)
        end
    end
    nothing
end

_click(x, y) = MouseClick(:left, x, y; time = 0.0)

# A point on the slider: the middle of the first row of points where a click by
# position writes a value.
function _find_slider_point(projection, iomap)
    for y in 0:4:400
        xs = [x for x in 0:6:800
              if _written_value(read_intent(projection, iomap, _click(x, y))) !== nothing]
        isempty(xs) || return (xs[length(xs) ÷ 2 + 1], y)
    end
    nothing
end

# A slider inside each kind of container that draws its children in frames of
# their own, away from the origin of that container.
_slider() = WidgetSlider(0.5; position = Point2D(13, 9))
routed_scenes = [
    "a composite" => () -> WidgetComposite(Any[WidgetLabel("a"), _slider()]),
    "a split pane" => () -> WidgetSplitPane(:horizontal,
        Any[WidgetLabel("left"), WidgetComposite(Any[_slider()])]; sizes = [200, 400]),
    "a scrolled pane" => () -> WidgetScrollPane(WidgetComposite(Any[_slider()]);
        size = Point2D(200, 100), scroll_position = Point2D(40, 0)),
    "a scaled pane" => () -> WidgetTransformPane(WidgetComposite(Any[_slider()]);
        size = Point2D(600, 300),
        transform = make_affine_translate(20.0, 15.0) ∘ make_affine_scale(2.0, 2.0)),
    "a card" => () -> WidgetCard(; title = "Title", content = WidgetComposite(Any[_slider()])),
    "a tabbed pane" => () -> WidgetTabbedPane(Any[("x", WidgetComposite(Any[_slider()])),
                                                 ("y", WidgetLabel("y"))]),
    "a shell" => () -> WidgetShell(WidgetComposite(Any[_slider()]);
        menu_bar = WidgetMenu(Any[WidgetMenuItem("File")]), size = Point2D(600, 400)),
    "a layout" => () -> HorizontalLayout(Any[WidgetLabel("left"), _slider()]),
]

@testset "a route gives the part the point in its own frame: $label" for (label, make) in routed_scenes
    projection = _projection()
    iomap = print_document(projection, make())
    point = _find_slider_point(projection, iomap)
    @test point !== nothing
    if point !== nothing
        (x, y) = point
        by_position = _written_value(read_intent(projection, iomap, _click(x, y)))
        route = _part_at(projection, iomap, x, y)
        @test route isa ConcreteReference
        by_route = _written_value(_read_routed(projection, iomap, _click(x, y), route))
        @test by_position !== nothing
        @test by_route == by_position
    end
end

end # @testset
end # test_routed_gesture
