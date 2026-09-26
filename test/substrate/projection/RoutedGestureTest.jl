# A gesture that follows a route through widget containers. The route names the
# part that the gesture is for, so the containers pass it on by reference and
# never by the position it holds: a leave reaches the widget that the pointer
# left, wherever the pointer is now.
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

@testset "an enter with a route lights the button it names, and no other" begin
    split, other, button, projection, iomap = _routed_scene()
    # The position is far from both buttons: the route alone names the part.
    op = _read_routed(projection, iomap, MouseEnter(5, 5; time = 0.0), _route_to_button())
    @test op isa ReplaceViewStateOperation
    @test _plain(op).document === button
    evaluate_operation(nothing, op)
    @test button.hovered == true
    @test other.hovered == false
end

@testset "a leave with a route clears the button, wherever the pointer is" begin
    split, other, button, projection, iomap = _routed_scene()
    evaluate_operation(nothing, _read_routed(projection, iomap, MouseEnter(5, 5; time = 0.0),
                                             _route_to_button()))
    @test button.hovered == true
    op = _read_routed(projection, iomap, MouseLeave(590, 5; time = 0.0), _route_to_button())
    evaluate_operation(nothing, op)
    @test button.hovered == false
end

@testset "a route that names nothing the containers print answers nothing" begin
    split, other, button, projection, iomap = _routed_scene()
    route = extend_reference(EmptyReference(), FieldReferenceStep("elements"), ElementReferenceStep(3))
    @test _read_routed(projection, iomap, MouseEnter(5, 5; time = 0.0), route) === nothing
end

end # @testset
end # test_routed_gesture
