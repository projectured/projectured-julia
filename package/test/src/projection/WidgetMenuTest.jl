# WidgetMenu interactivity (Stage 3, Step 4 — foundation). A WidgetMenuItem gains
# an optional `action` callback; a left click on an enabled item invokes it (via
# InvokeWidgetActionOperation) and closes the enclosing popup (:widget_popup) in
# one CompoundOperation. The WidgetMenu reader routes clicks to the hit item.
# Disabled items and non-left clicks are inert. The close is a harmless no-op when
# the menu is rendered inline (no such window).

mutable struct _MenuMockEditor
    document::Any
end

# Absolute (x, y) of the first GraphicsText in a canvas tree, summing the origin
# of every nested canvas along the way. GraphicsText has no right edge, so a click
# at its origin reliably hits it (see hit_element_at).
function _first_text_xy(canvas)
    _gi(v) = Int(v isa Projectured.ReactiveModule.Cell ? v[] : v)
    for el in canvas.elements
        el = el isa Projectured.ReactiveModule.Cell ? el[] : el
        if el isa GraphicsText
            return (_gi(el.x), _gi(el.y))
        elseif el isa GraphicsCanvas
            sub = _first_text_xy(el)
            sub === nothing || return (sub[1] + _gi(el.x), sub[2] + _gi(el.y))
        end
    end
    nothing
end

function test_widget_menu()
@testset "WidgetMenu interactivity" begin

proj = make_layout_projection_example()

# Project `menu`, then click the first item by landing on its rendered text (the
# whole chain: menu reader hit-tests + routes to the item reader).
function _click_first_item(menu, button=:left)
    iomap = projection_print(proj, menu)
    xy = _first_text_xy(iomap.output)
    xy === nothing && return (nothing, nothing)
    op = projection_read(proj, iomap, MousePress(button, xy[1] + 2, xy[2] + 2, Modifiers()))
    (op, iomap)
end

@testset "a left click on an enabled item invokes its action and closes the popup" begin
    fired = Ref(0)
    item = WidgetMenuItem("New"; action = (_e) -> (fired[] += 1))
    menu = WidgetMenu([item, WidgetMenuItem("Other")])
    op, _ = _click_first_item(menu)
    @test op isa CompoundOperation
    @test length(op.operations) == 2
    @test op.operations[1] isa InvokeWidgetActionOperation
    @test op.operations[1].widget === item
    @test op.operations[2] isa CloseWindowOperation
    @test op.operations[2].id === :widget_popup
    evaluate_operation(_MenuMockEditor(menu), op.operations[1])
    @test fired[] == 1
end

@testset "an item with no action still closes the popup" begin
    item = WidgetMenuItem("Close")
    menu = WidgetMenu([item])
    op, _ = _click_first_item(menu)
    @test op isa CompoundOperation
    @test op.operations[2] isa CloseWindowOperation
    # The no-op action evaluates without error.
    evaluate_operation(_MenuMockEditor(menu), op.operations[1])
end

@testset "a disabled item is inert" begin
    item = WidgetMenuItem("Nope"; action = (_e) -> error("must not fire"), enabled = false)
    menu = WidgetMenu([item])
    op, _ = _click_first_item(menu)
    @test op === nothing
end

@testset "a non-left click does nothing" begin
    item = WidgetMenuItem("New"; action = (_e) -> error("must not fire"))
    menu = WidgetMenu([item])
    op, _ = _click_first_item(menu, :right)
    @test op === nothing
end

end # @testset
end # function
