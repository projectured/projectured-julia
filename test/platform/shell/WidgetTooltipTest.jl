# What a widget says about itself when the pointer rests on it.
#
# A widget stores its answer in a field that whoever placed it set. The tooltip
# binding that `WidgetDocument` declares answers a `MouseDwell` with it, so every
# widget type has the binding, and a widget with an empty field answers nothing.

# The content of the one layer that the dwell binding of `document` answers, or
# `nothing` when the binding does not answer.
function _read_widget_tooltip(document)
    operation = read_gesture(document, MouseDwell(0, 0; time = 0.0))
    operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
end

function test_widget_tooltip()
@testset "a widget says what it is" begin

@testset "a widget answers the field it was given" begin
    @test _read_widget_tooltip(WidgetButton("Run"; size = Point2D(80, 24))) === nothing
    # A string is the text of a note, because a one-line tooltip is what a caller
    # writes, and the label of the button is its title.
    answer = _read_widget_tooltip(WidgetButton("Run";
                                               size = Point2D(80, 24), tooltip = "Run the selected configurations"))
    @test answer isa TooltipNote
    @test (answer.title, answer.text) == ("Run", "Run the selected configurations")
    @test _read_widget_tooltip(WidgetLabel("x"; tooltip = "a tip")).text == "a tip"
    @test _read_widget_tooltip(WidgetLabel("x"; tooltip = "")) === nothing
    # A document passes through as it is.
    given = WidgetLabel("a tip")
    @test _read_widget_tooltip(WidgetLabel("x"; tooltip = given)) === given
end

@testset "a control of an action says its label, its key and its text" begin
    new_tab = Action("New tab"; shortcut = Shortcut(:t; ctrl = true))
    # A menu item shows its label, so with no tooltip it says nothing more.
    @test _read_widget_tooltip(WidgetMenuItem(new_tab)) === nothing
    note = _read_widget_tooltip(WidgetMenuItem(new_tab; tooltip = "Open an empty tab."))
    @test (note.title, note.text) == ("New tab", "Open an empty tab.")
    @test describe_gesture_pattern.(note.keys) == ["Ctrl+T"]
    # A toolbar item shows only a picture, so it says its label and its key with
    # no tooltip of its own.
    note = _read_widget_tooltip(WidgetToolbarItem(new_tab))
    @test (note.title, note.text) == ("New tab", nothing)
    @test describe_gesture_pattern.(note.keys) == ["Ctrl+T"]
    # A note that the author gives says itself.
    given = TooltipNote(; title = "Mine")
    @test _read_widget_tooltip(WidgetToolbarItem(new_tab; tooltip = given)) === given
end

@testset "the answer is an operation that opens the tooltip" begin
    operation = read_gesture(WidgetButton("Run"; size = Point2D(80, 24), tooltip = "Run it"),
                             MouseDwell(7, 9; time = 0.0))
    # A history does not record a tooltip, so the operation is a view change.
    @test operation isa ReplaceViewStateOperation
    open = get_wrapped_operation(operation)
    @test open isa OpenTooltipOperation
    @test is_collecting_operation(operation)
    @test open.point == (7, 9)
    @test only(open.layers)[1] == "WidgetButton"
end

@testset "every widget type carries the field" begin
    # The sweep is the claim, so the test is the sweep: a type that was missed
    # answers a MethodError rather than nothing.
    @test _read_widget_tooltip(WidgetTable(Any["a"], Any[Any["1"]])) === nothing
    @test _read_widget_tooltip(WidgetSwitch()) === nothing
    @test _read_widget_tooltip(WidgetSplitPane(:horizontal, Any[])) === nothing
    @test _read_widget_tooltip(WidgetTree(Any[])) === nothing
    @test _read_widget_tooltip(WidgetMenuItem("Copy")) === nothing
end

@testset "a document with nothing to say says nothing" begin
    @test _read_widget_tooltip(PrimitiveString("plain")) === nothing
    @test compute_context_menu(PrimitiveString("plain")) === nothing
end

@testset "a command runs the binding where it applies" begin
    found = filter(binding -> binding.domain == "tooltip",
                   collect_document_gesture_bindings(WidgetButton))
    @test length(found) == 1
    binding = only(found)
    @test binding.name == "Show the tooltip"
    with = WidgetButton("Run"; size = Point2D(80, 24), tooltip = "Run it")
    without = WidgetButton("Run"; size = Point2D(80, 24))
    @test binding.applicable(with, nothing)
    @test !binding.applicable(without, nothing)
    # A command runs the binding with no pointer, so the answer has no point.
    @test get_wrapped_operation(binding.operation(with, nothing)).point === nothing
end

end # @testset
end # function
