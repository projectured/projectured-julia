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
    op = read_intent(proj, iomap, MouseClick(button, xy[1] + 2, xy[2] + 2, ModifierKeys(); time = 0.0))
    (op, iomap)
end

@testset "a menu bar keeps its items side by side, each as wide as its label" begin
    # A menu bar is offered the width of its window. It is as wide as its items
    # together, so it offers them no width: an item that took the offer would be
    # as wide as the window, and the next item would start past its right edge.
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch))
    bar = WidgetMenu(Any[WidgetMenuItem("File"), WidgetMenuItem("View"), WidgetMenuItem("Help")];
                     orientation = :horizontal)
    ctx = with_exact_size(PrinterContext(); width = Cell(Int32(1000)), height = Cell(Int32(600)))
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
    # A menu bar draws on the bar that holds it: no surface of its own.
    first_element = output.elements[1]
    first_element = first_element isa CellModule.Cell ? first_element[] : first_element
    @test !(first_element isa GraphicsRect)
end

@testset "a dropdown draws the popover, and every item is as wide as the widest" begin
    # A dropdown is offered the exact size of its window. It offers its items no
    # height, and each item the width that the widest item needs, so a highlight
    # spans the row and the menu is as large as its items, not as the window.
    det = FixedMeasure(8, 12, 4, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch))
    menu = WidgetMenu(Any[WidgetMenuItem("Documents"), WidgetMenuItem("About")])
    ctx = with_exact_size(PrinterContext(); width = Cell(Int32(640)), height = Cell(Int32(800)))
    iomap = print_document(rec, nothing, menu, ctx)
    items = [entry[3] for entry in iomap.child_iomaps]
    @test Int(items[1].natural_width) > Int(items[2].natural_width)
    @test Int(items[1].control_width) == Int(items[2].control_width) == Int(items[1].natural_width)
    output = iomap.output
    @test Int(output.w) < 640 && Int(output.h) < 800
    # The popover of the theme: its fill and its hairline border, as large as the
    # menu.
    theme = make_widget_theme(font = StyleFont("Ubuntu", 20))
    panel = output.elements[1]
    panel = panel isa CellModule.Cell ? panel[] : panel
    @test panel isa GraphicsRect
    @test is_color_equal(panel.color, get_theme_value(theme, :popover))
    @test is_color_equal(panel.border_color, get_theme_value(theme, :border))
    @test (Int(panel.w), Int(panel.h)) == (Int(output.w), Int(output.h))
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
# An item with a `submenu` opens it as a popup *below itself*, at a position in
# its own frame, instead of running an action. The item is printed standalone —
# its reader does not hit-test the click position (routing hit-tests upstream),
# so a left press anywhere triggers it. To open a popup is not an edit, so the
# popup comes marked as view state.

_menu_popup(op) = op isa ReplaceViewStateOperation ? get_wrapped_operation(op) : op

# The IO map of `document` in the IO map tree of a print: the example projection
# is a chain, so the widget's own IO map sits inside the IO map of the print. The
# chain has the same input, so the deepest IO map of `document` is the one.
function _menu_iomap_of(iomap, document, depth = 0)
    depth > 12 && return nothing
    for field in fieldnames(typeof(iomap))
        value = getfield(iomap, field)
        value = value isa CellModule.Cell ? value[] : value
        for candidate in (value isa AbstractVector ? value : (value,))
            candidate = candidate isa CellModule.Cell ? candidate[] : candidate
            candidate isa Tuple && (candidate = last(candidate))
            candidate isa IoMap || continue
            found = _menu_iomap_of(candidate, document, depth + 1)
            found === nothing || return found
        end
    end
    iomap.input === document ? iomap : nothing
end

@testset "a submenu item opens its submenu below itself" begin
    submenu = WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open")])
    item = WidgetMenuItem("File"; submenu = submenu)
    iomap = print_document(proj, item)

    op = read_intent(proj, iomap, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0))
    @test op isa ReplaceViewStateOperation
    popup = _menu_popup(op)
    @test popup isa OpenPopupOperation
    @test popup.id === :widget_popup
    @test popup.auto_dismiss === true
    @test popup.x == 0                          # at the left edge of the item
    @test popup.y == _menu_iomap_of(iomap, item).control_height + 2   # just below it
    @test popup.content === submenu             # the popup content is the submenu
    @test popup.height > 0
end

@testset "a submenu takes precedence over an action" begin
    submenu = WidgetMenu([WidgetMenuItem("New")])
    item = WidgetMenuItem("File"; action = (_e) -> error("must not fire"), submenu = submenu)
    iomap = print_document(proj, item)

    op = read_intent(proj, iomap, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0))
    @test _menu_popup(op) isa OpenPopupOperation   # opened the submenu, did not run the action
    @test !(op isa CompoundOperation)
end

@testset "a disabled submenu item is inert" begin
    submenu = WidgetMenu([WidgetMenuItem("New")])
    item = WidgetMenuItem("File"; submenu = submenu, enabled = false)
    iomap = print_document(proj, item)
    @test read_intent(proj, iomap, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0)) === nothing
end

@testset "a menu bar moves the popup of an item into its own frame" begin
    submenu = WidgetMenu([WidgetMenuItem("New"), WidgetMenuItem("Open")])
    bar = WidgetMenu(Any[WidgetMenuItem("File"), WidgetMenuItem("View"; submenu = submenu)];
                     orientation = :horizontal, padding = Inset(2, 2, 2, 2))
    iomap = print_document(proj, bar)
    # The press lands on the second item, and the popup opens below that item,
    # in the frame of the bar: its position is where the bar placed the item.
    (ox, oy, cim) = getfield(_menu_iomap_of(iomap, bar), :child_iomaps)[][2]
    popup = _menu_popup(read_intent(proj, iomap, MouseClick(:left, ox + 3, oy + 3, ModifierKeys(); time = 0.0)))
    @test popup isa OpenPopupOperation
    @test ox > 0
    @test popup.x == ox
    @test popup.y == oy + cim.control_height + 2
    @test popup.content === submenu
end

# ── Light feedback (Qt-gap Part F) ─────────────────────────────────────────
@testset "a move onto a menu item makes it the part under the pointer, and draws a surface" begin
    item = WidgetMenuItem("New")
    menu = WidgetMenu([item, WidgetMenuItem("Open")])
    iomap = print_document(proj, menu)
    xy = _first_text_xy(iomap.output)
    # A point on the item maps backward to it, so the move writes the item's own
    # mouse target.
    _mtt_move!(MttDriver(proj, menu), xy[1] + 2, xy[2] + 2, 1.0)
    @test get_mouse_target(item) !== nothing

    # A lit item draws one more surface as large as the item: the layer of the
    # light, which has no size while the pointer is off the item.
    full_surfaces(io) = begin
        size = (Int(io.output.w[]), Int(io.output.h[]))
        count(e -> e isa GraphicsRect && (Int(e.w), Int(e.h)) == size,
              map(e -> e isa CellModule.Cell ? e[] : e, collect(io.output.elements)))
    end
    plain = print_document(proj, WidgetMenuItem("New"))
    lit   = WidgetMenuItem("New"); getfield(lit, :mouse_target)[] = EmptyReference()
    @test full_surfaces(print_document(proj, lit)) == full_surfaces(plain) + 1
    # A disabled lit item shows no surface.
    dis = WidgetMenuItem("New"; enabled=false); getfield(dis, :mouse_target)[] = EmptyReference()
    @test full_surfaces(print_document(proj, dis)) == full_surfaces(plain)
end

end # @testset
end # function
