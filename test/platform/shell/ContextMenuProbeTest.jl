# The context menu probe: a right press asks the document under the pointer for
# its menu, and the menu opens through the popup route.

# A projection whose reader answers every press with a selection, as a row of the
# explorer answers a right press.
struct _ContextSelecting <: Projection end
ProjectionModule.print_document(::_ContextSelecting, recursion, input, ctx) =
    SimpleIoMap(_ContextSelecting(), input, input)
ProjectionModule.read_intent(::_ContextSelecting, iomap, event) =
    event isa MouseClick ? ReplaceSelectionOperation(EmptyReference()) : nothing

function test_context_menu_probe()
@testset "the context menu probe" begin

# `context_menu` is a field of the window's own frame and of nothing else, so
# the shell is what carries one. Every other document computes its menu.
_speaks() = WidgetShell(WidgetLabel("speaks");
                        size = Point2D(200, 100),
                        context_menu = WidgetMenu([WidgetMenuItem("Copy"),
                                                   WidgetMenuItem("Paste")]))

function _read(document; menu = compute_context_menu)
    _, projection = make_window_wrap(;
        gesture_help = false, command_palette = false,
        selection = false, context_menu = menu)(document, make_layout_projection_example())
    iomap = print_document(projection, document)
    answer = read_intent(projection, nothing,
                         Intent(MouseClick(:right, 5, 5, ModifierKeys(); time = 0.0)), iomap)
    answer isa Intent ? answer.operation : answer
end

@testset "a document that offers a menu opens one" begin
    marked = _read(_speaks())
    # To open a popup is not an edit, so the popup comes marked as view state.
    @test marked isa ReplaceViewStateOperation
    operation = get_wrapped_operation(marked)
    @test operation isa OpenPopupOperation
    @test operation.content isa WidgetMenu
    # The menu opens at the press.
    @test (operation.x, operation.y) == (5, 5)
    # A popup with no size is a window nobody sees.
    @test operation.width > 0 && operation.height > 0
end

# Whether an answer opens a popup: the popup comes marked as view state.
_opens_popup(operation) = operation isa ReplaceViewStateOperation &&
                          get_wrapped_operation(operation) isa OpenPopupOperation

@testset "a right press on a row selects it and opens the menu" begin
    menu = WidgetMenu([WidgetMenuItem("Open")])
    probe = ContextMenuProbeProjection(inner = _ContextSelecting(), compute_context_menu = _ -> menu)
    iomap = print_document(probe, PrimitiveString("row"))
    answer(button) = read_intent(probe, nothing,
                                 Intent(MouseClick(button, 7, 9, ModifierKeys(); time = 0.0)), iomap).operation
    right = answer(:right)
    @test right isa CompoundOperation
    @test right.operations[1] isa ReplaceSelectionOperation
    popup = get_wrapped_operation(right.operations[2])
    @test popup isa OpenPopupOperation
    @test (popup.x, popup.y) == (7, 9)
    @test popup.content === menu
    # A left press on the row only selects it.
    @test answer(:left) isa ReplaceSelectionOperation
end

@testset "a document that offers none opens none" begin
    @test !_opens_popup(_read(WidgetShell(WidgetLabel("silent"); size = Point2D(200, 100))))
end

@testset "no function, no probe" begin
    @test !_opens_popup(_read(_speaks(); menu = nothing))
end

end # @testset
end # function
