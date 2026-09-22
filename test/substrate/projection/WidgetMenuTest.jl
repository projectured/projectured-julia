# WidgetMenu interactivity (Stage 3, Step 4 — foundation). A WidgetMenuItem gains
# an optional `action` callback; a left click on an enabled item invokes it (via
# InvokeActionOperation) and closes the enclosing popup (:widget_popup) in
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
    _gi(v) = Int(v isa CellModule.Cell ? v[] : v)
    for el in canvas.elements
        el = el isa CellModule.Cell ? el[] : el
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
    iomap = print_document(proj, menu)
    xy = _first_text_xy(iomap.output)
    xy === nothing && return (nothing, nothing)
    op = read_intent(proj, iomap, MousePress(button, xy[1] + 2, xy[2] + 2, ModifierKeys()))
    (op, iomap)
end

@testset "a menu bar keeps its items side by side, each as wide as its label" begin
    # A menu bar is offered the width of its window. It is as wide as its items
    # together, so it offers them no width: an item that took the offer would be
    # as wide as the window, and the next item would start past its right edge.
    det = (t, f) -> (length(t) * 8, 16)
    rec = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(font_ubuntu_regular_20; measure = det).dispatch))
    bar = WidgetMenu(Any[WidgetMenuItem("File"), WidgetMenuItem("View"), WidgetMenuItem("Help")];
                     orientation = :horizontal)
    ctx = with_available_size(PrinterContext(); width = Cell(Int32(1000)), height = Cell(Int32(600)))
    output = print_document(rec, nothing, bar, ctx).output
    xs = Int[]
    for element in output.elements
        element = element isa CellModule.Cell ? element[] : element
        push!(xs, Int(element.x isa CellModule.Cell ? element.x[] : element.x))
    end
    @test length(xs) == 3
    @test issorted(xs) && allunique(xs)
    # Each step is one label and the gap between items, not the window.
    @test all(step -> step < 8 * 4 + 40, diff(xs))
    @test Int(output.w) < 1000
end

@testset "a left click on an enabled item invokes its action and closes the popup" begin
    fired = Ref(0)
    item = WidgetMenuItem("New"; action = (_e) -> (fired[] += 1))
    menu = WidgetMenu([item, WidgetMenuItem("Other")])
    op, _ = _click_first_item(menu)
    @test op isa CompoundOperation
    @test length(op.operations) == 2
    @test op.operations[1] isa InvokeActionOperation
    @test op.operations[1].action === item.action
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
    iomap = print_document(proj, item)

    op = read_intent(proj, iomap, MousePress(:left, 5, 5, ModifierKeys()))
    @test op isa OpenPopupOperation
    @test op.id === :widget_popup
    @test op.auto_dismiss === true
    @test op.anchor isa EmptyReference      # anchored to the item itself (root)
    @test op.dx == 0                            # opens directly below
    @test op.dy > 0
    @test op.content === submenu                # the popup content is the submenu
    @test op.height > 0
end

@testset "a submenu takes precedence over an action" begin
    submenu = WidgetMenu([WidgetMenuItem("New")])
    item = WidgetMenuItem("File"; action = (_e) -> error("must not fire"), submenu = submenu)
    iomap = print_document(proj, item)

    op = read_intent(proj, iomap, MousePress(:left, 5, 5, ModifierKeys()))
    @test op isa OpenPopupOperation            # opened the submenu, did not run the action
    @test !(op isa CompoundOperation)
end

@testset "a disabled submenu item is inert" begin
    submenu = WidgetMenu([WidgetMenuItem("New")])
    item = WidgetMenuItem("File"; submenu = submenu, enabled = false)
    iomap = print_document(proj, item)
    @test read_intent(proj, iomap, MousePress(:left, 5, 5, ModifierKeys())) === nothing
end

@testset "the resolver maps the submenu anchor to an absolute OpenWindowOperation" begin
    submenu = WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open")])
    item = WidgetMenuItem("File"; submenu = submenu)
    # Mirror the real pipeline (as WidgetSelectTest does): the resolver wraps the
    # content projection, isolated through a NestingProjection.
    inner = NestingProjection(proj; recursion = IdentityProjection())
    resolver = WidgetPopupResolverProjection(inner = inner)
    rio = print_document(resolver, item)

    op = read_intent(resolver, rio, MousePress(:left, 5, 5, ModifierKeys()))
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
    iomap = print_document(proj, menu)
    xy = _first_text_xy(iomap.output)
    # The menu routes the crossing to the hit item, which flips `hovered`.
    op = read_intent(proj, iomap, MouseEnter(xy[1] + 2, xy[2] + 2, :none, ModifierKeys()))
    @test op isa ReplaceReferencedValueOperation
    @test op.value === true

    # A hovered item renders an extra (hover surface) element vs an un-hovered one.
    plain = print_document(proj, WidgetMenuItem("New"))
    hov   = WidgetMenuItem("New"); hov.hovered = true
    hovio = print_document(proj, hov)
    @test length(collect(hovio.output.elements)) > length(collect(plain.output.elements))
    # A disabled hovered item shows no surface (same element count as plain).
    dis = WidgetMenuItem("New"; enabled=false); dis.hovered = true
    @test length(collect(print_document(proj, dis).output.elements)) ==
          length(collect(plain.output.elements))
end

end # @testset
end # function
