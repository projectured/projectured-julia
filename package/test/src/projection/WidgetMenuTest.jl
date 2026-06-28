# WidgetMenu interactivity (Stage 3, Step 4 — foundation). A WidgetMenuItem gains
# an optional `action` callback; a left click on an enabled item invokes it (via
# InvokeWidgetActionOperation) and closes the enclosing popup (:widget_popup) in
# one CompoundOperation. The WidgetMenu reader routes clicks to the hit item.
# Disabled items and non-left clicks are inert. The close is a harmless no-op when
# the menu is rendered inline (no such window).

using Projectured: MouseEnter

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

# ── Submenu-opener (Step 4b) ──────────────────────────────────────────────
# An item with a `submenu` opens it as an anchor-relative popup *below itself*
# (reusing the WidgetSelect dropdown route) instead of running an action. The
# item is printed standalone — its reader does not hit-test the click position
# (routing hit-tests upstream), so a left press anywhere triggers it.

@testset "a submenu item opens its submenu as an anchor-relative popup" begin
    submenu = WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open")])
    item = WidgetMenuItem("File"; submenu = submenu)
    iomap = projection_print(proj, item)

    op = projection_read(proj, iomap, MousePress(:left, 5, 5, Modifiers()))
    @test op isa OpenPopupOperation
    @test op.id === :widget_popup
    @test op.auto_dismiss === true
    @test op.anchor isa EmptyReferencePath      # anchored to the item itself (root)
    @test op.dx == 0                            # opens directly below
    @test op.dy > 0
    @test op.content === submenu                # the popup content is the submenu
    @test op.height > 0
end

@testset "a submenu takes precedence over an action" begin
    submenu = WidgetMenu([WidgetMenuItem("New")])
    item = WidgetMenuItem("File"; action = (_e) -> error("must not fire"), submenu = submenu)
    iomap = projection_print(proj, item)

    op = projection_read(proj, iomap, MousePress(:left, 5, 5, Modifiers()))
    @test op isa OpenPopupOperation            # opened the submenu, did not run the action
    @test !(op isa CompoundOperation)
end

@testset "a disabled submenu item is inert" begin
    submenu = WidgetMenu([WidgetMenuItem("New")])
    item = WidgetMenuItem("File"; submenu = submenu, enabled = false)
    iomap = projection_print(proj, item)
    @test projection_read(proj, iomap, MousePress(:left, 5, 5, Modifiers())) === nothing
end

@testset "the resolver maps the submenu anchor to an absolute OpenWindowOperation" begin
    submenu = WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open")])
    item = WidgetMenuItem("File"; submenu = submenu)
    # Mirror the real pipeline (as WidgetSelectTest does): the resolver wraps the
    # content projection, isolated through a NestingProjection.
    inner = NestingProjection(proj; recursion = PreservingProjection())
    resolver = WidgetPopupResolverProjection(inner = inner)
    rio = projection_print(resolver, item)

    op = projection_read(resolver, rio, MousePress(:left, 5, 5, Modifiers()))
    @test op isa OpenWindowOperation
    @test op.id === :widget_popup
    @test op.style === :floating
    @test op.auto_dismiss === true
    @test op.content === submenu
    # The item sits at the origin, so its top-left resolves to (0, 0); the popup
    # opens directly below (dx == 0, dy == item_height + gap > 0).
    @test op.x == 0
    @test op.y > 0
end

# ── Hover feedback (Qt-gap Part F) ─────────────────────────────────────────
@testset "hovering a menu item sets its hovered flag and draws a surface" begin
    item = WidgetMenuItem("New")
    menu = WidgetMenu([item, WidgetMenuItem("Open")])
    iomap = projection_print(proj, menu)
    xy = _first_text_xy(iomap.output)
    # The menu routes the crossing to the hit item, which flips `hovered`.
    op = projection_read(proj, iomap, MouseEnter(xy[1] + 2, xy[2] + 2, :none, Modifiers()))
    @test op isa ReplaceReferencedValue
    @test op.value === true

    # A hovered item renders an extra (hover surface) element vs an un-hovered one.
    plain = projection_print(proj, WidgetMenuItem("New"))
    hov   = WidgetMenuItem("New"); hov.hovered = true
    hovio = projection_print(proj, hov)
    @test length(collect(hovio.output.elements)) > length(collect(plain.output.elements))
    # A disabled hovered item shows no surface (same element count as plain).
    dis = WidgetMenuItem("New"; enabled=false); dis.hovered = true
    @test length(collect(projection_print(proj, dis).output.elements)) ==
          length(collect(plain.output.elements))
end

end # @testset
end # function
