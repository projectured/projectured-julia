# WidgetToolbar pointer routing. A toolbar lays its items out horizontally, so the
# light of a move must land on the item actually under the pointer. The item
# canvas is bounded to its footprint: a GraphicsText has no right edge, so an
# auto-sized item canvas (w=h=0) would take every point to its right, and the
# first button would light wherever the pointer is.

using ProjecturedKernel.CellModule: Cell, Computation, is_cell_up_to_date

function test_widget_toolbar()
@testset "WidgetToolbar pointer routing" begin

_det = FixedMeasure(8, 12, 4, 0)
proj = make_widget_projection_example(measure = _det)
_mods = ModifierKeys()
_unwrap(el) = el isa Cell ? el[] : el

# The bound item canvas: a lone menu item projects to a non-auto-sized canvas.
@testset "a menu item projects to a bounded canvas" begin
    c = print_document(proj, WidgetMenuItem("Save")).output
    @test c isa GraphicsCanvas
    @test Int(c.w[]) > 0 && Int(c.h[]) > 0
end

@testset "the light lands on the item under the pointer, not the first" begin
    labels = ["New", "Open", "Save", "Undo", "Redo"]
    tb = WidgetToolbar([WidgetMenuItem(l) for l in labels]; padding = Inset(4, 4, 4, 4))
    io = print_document(proj, tb)

    wrappers = GraphicsCanvas[]
    for el in io.output.elements
        el = _unwrap(el)
        el isa GraphicsCanvas && push!(wrappers, el)
    end
    sort!(wrappers, by = c -> Int(c.x))
    @test length(wrappers) == length(labels)

    # Move just inside each button, at the middle of its height, and read which
    # items are lit.
    driver = MttDriver(proj, tb)
    for (i, c) in enumerate(wrappers)
        _mtt_move!(driver, Int(c.x) + 6, Int(c.y) + Int(c.h[]) ÷ 2, 1.0 + i)
        @test [item.action.label for item in tb.elements if get_mouse_target(item) !== nothing] == [labels[i]]
    end
end

# A hover writes the mouse target of an item. The layer that shows it reads that
# cell in cells of its own, so the element list and the extent of the item stay up
# to date: the toolbar does not lay out its items again, and a partial repaint
# paints only the layer.
@testset "a hover changes the layer of an item and nothing else" begin
    for item in (WidgetToolbarItem("Run"; icon = :play), WidgetMenuItem("Save"))
        c = print_document(proj, item).output
        width, height = Int(c.w[]), Int(c.h[])
        rects = [e for e in map(_unwrap, collect(c.elements)) if e isa GraphicsRect]
        hidden = [r for r in rects if Int(r.w) == 0 && Int(r.h) == 0]
        @test length(hidden) == 1
        replace_mouse_target!(item, EmptyReference())
        @test is_cell_up_to_date(getfield(c, :elements))
        @test is_cell_up_to_date(getfield(c.elements, :elements))
        @test is_cell_up_to_date(getfield(c, :w)) && is_cell_up_to_date(getfield(c, :h))
        layer = only(hidden)
        @test (Int(layer.w), Int(layer.h)) == (width, height)
        replace_mouse_target!(item, nothing)
        @test (Int(layer.w), Int(layer.h)) == (0, 0)
    end
end

# A toolbar item is flat at rest. Under the pointer its layer is a button: the
# light of the theme, with the outline and the corners of a control, as a
# `WidgetButton` draws them.
@testset "a lit toolbar item shows the outline of a button" begin
    theme = make_scaled_theme(make_widget_theme())
    item = WidgetToolbarItem("Run"; icon = :play)
    c = print_document(proj, item).output
    rects = [e for e in map(_unwrap, collect(c.elements)) if e isa GraphicsRect]
    @test all(Int(r.border_width) == 0 for r in rects if Int(r.w) > 0)
    layer = only(r for r in rects if Int(r.w) == 0 && Int(r.h) == 0)
    replace_mouse_target!(item, EmptyReference())
    @test (Int(layer.w), Int(layer.h)) == (Int(c.w[]), Int(c.h[]))
    @test layer.color == WidgetModule._get_hover_layer(theme)
    @test Int(layer.border_width) == Int(theme.border_width)
    @test layer.border_color == theme.border
    @test Int(layer.radius_tl) == Int(theme.radius) > 0
end

# A toolbar item states its size, and the bar takes it. A button can draw outside
# its size, as its shadow does, so the bar measures it. The box of a toolbar has no
# color, so its padding draws nothing, and the toolbar still keeps it on every side.
@testset "a toolbar holds what its items draw, and its padding" begin
    for items in (Any[WidgetToolbarItem("Run"; icon = :play), WidgetMenuItem("Save")],
                  Any[WidgetToolbarItem("Run"; icon = :play), WidgetButton("Go")])
        c = print_document(proj, WidgetToolbar(items)).output
        drawn_width, drawn_height = get_graphics_size(c, _det)
        @test Int(c.w[]) >= drawn_width && Int(c.h[]) >= drawn_height
    end
    make_items() = Any[WidgetToolbarItem("Run"; icon = :play), WidgetMenuItem("Save")]
    bare = print_document(proj, WidgetToolbar(make_items(); padding = Inset(0, 0, 0, 0))).output
    padded = print_document(proj, WidgetToolbar(make_items(); padding = Inset(3, 5, 7, 9))).output
    @test (Int(padded.w[]), Int(padded.h[])) == (Int(bare.w[]) + 7 + 9, Int(bare.h[]) + 3 + 5)
end

# What a canvas would draw, forced the way a backend forces it.
_drawn(canvas, ::Type{T}) where {T} = begin
    found = T[]
    walk(c) = for el in c.elements
        el = _unwrap(el)
        el isa T && push!(found, el)
        el isa GraphicsCanvas && walk(el)
    end
    walk(canvas)
    found
end
# The item canvases a toolbar laid out, left to right.
_items(io) = sort!([c for c in map(_unwrap, io.output.elements) if c isa GraphicsCanvas],
                   by = c -> Int(c.x))
_centre(c) = (Int(c.x) + Int(c.w[]) ÷ 2, Int(c.y) + Int(c.h[]) ÷ 2)
_press(io, (x, y); modifiers = _mods) = begin
    answer = read_intent(proj, nothing, Intent(MouseClick(:left, x, y, modifiers; time = 0.0), nothing), io)
    answer isa Intent ? answer.operation : answer
end

@testset "a toolbar item with an icon draws the icon alone" begin
    short = print_document(proj, WidgetToolbarItem("Log"; icon = :list,
                                                   padding = Inset(4, 4, 4, 4))).output
    long = print_document(proj, WidgetToolbarItem("Every gesture of this session"; icon = :keyboard,
                                                  padding = Inset(4, 4, 4, 4))).output
    # One text, and it is the glyph of the icon, not the label.
    @test [string(t.text) for t in _drawn(short, GraphicsText)] == [string(find_icon_character(:list))]
    # As wide as the icon and its padding, whatever the label says: the icon is
    # a square as tall as a line of the font, so the item is square too.
    @test Int(short.w[]) == Int(long.w[])
    @test Int(short.w[]) == Int(short.h[])
    @test Int(short.w[]) == 16 + 8
    # A band can offer the size of the window. The item stays as large as what
    # it shows, or it would take every press below it.
    offered = PrinterContext(EmptyReference(), Cell(1600), Cell(1000), Dict{Symbol,Any}())
    tall = print_document(proj, nothing, WidgetToolbarItem("Log"; icon = :list,
                                                           padding = Inset(4, 4, 4, 4)), offered).output
    @test (Int(tall.w[]), Int(tall.h[])) == (16 + 8, 16 + 8)
end

@testset "a toolbar item with no icon draws its label" begin
    canvas = print_document(proj, WidgetToolbarItem("Run")).output
    @test [string(t.text) for t in _drawn(canvas, GraphicsText)] == ["Run"]
end

@testset "a move and a press land on the toolbar item under the pointer" begin
    labels = ["Explorer", "Assistant", "Evaluator"]
    icons = [:folder, :chat, :terminal]
    tb = WidgetToolbar(Any[WidgetToolbarItem(l; icon = i) for (l, i) in zip(labels, icons)];
                       padding = Inset(4, 4, 4, 4))
    io = print_document(proj, tb)
    driver = MttDriver(proj, tb)
    items = _items(io)
    @test length(items) == length(labels)
    for (i, c) in enumerate(items)
        x, y = _centre(c)
        _mtt_move!(driver, x, y, 1.0 + i)
        @test [item.action.label for item in tb.elements if get_mouse_target(item) !== nothing] == [labels[i]]
        # A left press invokes the action of that item, and only reads it: the
        # reader answers the operation and runs nothing.
        op = _press(io, (x, y))
        @test op isa InvokeActionOperation && op.action === tb.elements[i].action
        # The whole button takes a press, also a corner where the picture draws
        # nothing.
        corner = (Int(c.x) + 1, Int(c.y) + 1)
        op = _press(io, corner)
        @test op isa InvokeActionOperation && op.action === tb.elements[i].action
    end
    # A picture made of thin filled bars takes a press between the bars too.
    chart = WidgetToolbar(Any[WidgetToolbarItem("Statistics"; icon = :chart)])
    io = print_document(proj, chart)
    c = only(_items(io))
    @test all(_press(io, (x, Int(c.y) + Int(c.h[]) ÷ 2)) isa InvokeActionOperation
              for x in Int(c.x):(Int(c.x) + Int(c.w[]) - 1))
end

@testset "a disabled toolbar item is inert" begin
    item = WidgetToolbarItem("Log"; icon = :list, enabled = false)
    io = print_document(proj, item)
    @test _press(io, _centre(io.output)) === nothing
    bound = WidgetToolbarItem(Action("Log"; icon = :list, enabled = false))
    io = print_document(proj, bound)
    @test _press(io, _centre(io.output)) === nothing
end

@testset "Alt and a press select a toolbar item, and run nothing" begin
    # The layers above turn a declined Alt press into a selection of the item,
    # and the tooltip probe finds the item with the same press.
    io = print_document(proj, WidgetToolbarItem("Log"; icon = :list))
    @test _press(io, _centre(io.output)) isa InvokeActionOperation
    @test !(_press(io, _centre(io.output); modifiers = ModifierKeys(alt = true)) isa
            InvokeActionOperation)

    # In a toolbar the selection names the item under the pointer, not the
    # whole toolbar.
    tb = WidgetToolbar(Any[WidgetToolbarItem("Explorer"; icon = :folder),
                           WidgetToolbarItem("Log"; icon = :list)])
    io = print_document(proj, tb)
    op = _press(io, _centre(_items(io)[2]); modifiers = ModifierKeys(alt = true))
    @test op isa ReplaceSelectionOperation
    @test try_evaluate_reference(tb, op.path, missing) === tb.elements[2]
end

# What the toolbar `io` answers to the pointer event `evt`, and the write of
# pointer state inside that answer.
_read_event(io, evt) = begin
    answer = read_intent(proj, nothing, Intent(evt, nothing), io)
    answer isa Intent ? answer.operation : answer
end
_toolbar_state_write(op) = op isa ReplaceViewStateOperation ? get_wrapped_operation(op) : nothing

# A left down on an item, through the toolbar, writes the `pressed` of that item
# and of no other, and its layer shows the pressed color until the up. The down
# is the answer of the item, so it moves no focus.
@testset "a held toolbar item shows its press" begin
    theme = make_scaled_theme(make_widget_theme())
    tb = WidgetToolbar(Any[WidgetToolbarItem("Explorer"; icon = :folder),
                           WidgetToolbarItem("Log"; icon = :list)])
    io = print_document(proj, tb)
    item = tb.elements[2]
    x, y = _centre(_items(io)[2])
    layer = only(r for r in _drawn(_items(io)[2], GraphicsRect) if Int(r.border_width) > 0)
    down = _read_event(io, MouseDown(:left, x, y, _mods; time = 0.0))
    held = _toolbar_state_write(down)
    @test held isa ReplaceReferencedValueOperation
    @test held.document === item && held.value == true
    evaluate_operation((document = tb,), down)
    @test item.pressed == true && tb.elements[1].pressed == false
    @test Int(layer.w) > 0 && Int(layer.h) > 0
    @test layer.color == WidgetModule._get_pressed_layer(theme)
    up = _read_event(io, MouseUp(:left, x, y, _mods; time = 0.1))
    @test _toolbar_state_write(up).document === item && _toolbar_state_write(up).value == false
    evaluate_operation((document = tb,), up)
    @test item.pressed == false
    replace_mouse_target!(item, EmptyReference())
    @test layer.color == WidgetModule._get_hover_layer(theme)
    # The press that the gesture tracking makes after the up runs the action.
    @test _read_event(io, MouseClick(:left, x, y, _mods; time = 0.1)) isa InvokeActionOperation
end

# A press released off the item ends when the pointer leaves the item, as on a
# button.
@testset "a move off a held toolbar item ends its press" begin
    tb = WidgetToolbar(Any[WidgetToolbarItem("Explorer"; icon = :folder),
                           WidgetToolbarItem("Log"; icon = :list)])
    io = print_document(proj, tb)
    driver = MttDriver(proj, tb)
    for (i, away) in ((2, _centre(_items(io)[1])), (1, (500, 500)))
        x, y = _centre(_items(io)[i])
        _mtt_move!(driver, x, y, 1.0 + i)
        evaluate_operation((document = tb,), _read_event(io, MouseDown(:left, x, y, _mods; time = 0.0)))
        @test tb.elements[i].pressed == true
        _mtt_move!(driver, away..., 1.5 + i)
        @test tb.elements[i].pressed == false
    end
end

@testset "a disabled toolbar item shows no press" begin
    tb = WidgetToolbar(Any[WidgetToolbarItem("Stop"; icon = :stop, enabled = false)])
    io = print_document(proj, tb)
    x, y = _centre(only(_items(io)))
    @test _read_event(io, MouseDown(:left, x, y, _mods; time = 0.0)) === nothing
    @test _read_event(io, MouseUp(:left, x, y, _mods; time = 0.0)) === nothing
    @test only(tb.elements).pressed == false
end

@testset "a toolbar item says its label when it has no tooltip" begin
    # The content of the one layer that the dwell binding answers.
    dwell(item) = let operation = read_gesture(item, MouseDwell(0, 0; time = 0.0))
        operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
    end
    @test dwell(WidgetToolbarItem("Gesture log"; icon = :keyboard)).value == "Gesture log"
    @test dwell(WidgetToolbarItem("Gesture log"; icon = :keyboard,
                                  tooltip = "Every gesture")).value == "Every gesture"
    @test dwell(WidgetToolbarItem(""; icon = :keyboard)) === nothing
end

# An edit under the pointer keeps one item lit. The pointer rests on Copy, and the
# items change by splices, as the editor makes an edit, an undo and a redo: a
# delete, an insert before the pointer, a delete of the last item, and a write of
# the whole list. After each one the move of the frame names the slot under the
# pointer again, and the item there is the only one lit.
@testset "an edit under the pointer leaves one item lit" begin
    slot(i) = ConcreteReference(FieldReferenceStep("elements"),
                                ConcreteReference(RangeReferenceStep(i - 1, i), EmptyReference()))
    span(a, b) = ConcreteReference(FieldReferenceStep("elements"),
                                   ConcreteReference(RangeReferenceStep(a, b), EmptyReference()))
    splice_items!(bar, a, b, values) =
        evaluate_operation(nothing, ReplaceReferencedValueOperation(bar, span(a, b), Any[values...]))
    labels(bar) = [string(item.action.label) for item in bar.elements]
    lit(shown) = [string(item.action.label) for item in shown if get_mouse_target(item) !== nothing]
    cut, copy, paste = WidgetToolbarItem("Cut"), WidgetToolbarItem("Copy"), WidgetToolbarItem("Paste")
    items = (cut, copy, paste)
    bar = WidgetToolbar(Any[cut, copy, paste])
    replace_mouse_target!(bar, slot(2))
    @test lit(items) == ["Copy"]

    # A delete takes Copy from under the pointer, and Paste moves into its slot.
    splice_items!(bar, 1, 2, ())
    @test labels(bar) == ["Cut", "Paste"] && lit(items) == []
    replace_mouse_target!(bar, slot(2))
    @test lit(items) == ["Paste"]

    # The undo puts Copy back: the path moves with Paste until the next move.
    splice_items!(bar, 1, 1, (copy,))
    @test labels(bar) == ["Cut", "Copy", "Paste"] && lit(items) == ["Paste"]
    @test get_mouse_target(bar) == slot(3)
    replace_mouse_target!(bar, slot(2))
    @test lit(items) == ["Copy"]
    replace_mouse_target!(bar, slot(1))
    @test lit(items) == ["Cut"]
    replace_mouse_target!(bar, nothing)
    @test lit(items) == []

    # A delete of the last item under the pointer leaves the list of items itself.
    replace_mouse_target!(bar, slot(3))
    splice_items!(bar, 2, 3, ())
    @test lit(items) == []
    @test get_mouse_target(bar) == ConcreteReference(FieldReferenceStep("elements"), EmptyReference())

    # A write of the whole list clears the item that the old list held.
    replace_mouse_target!(bar, slot(2))
    @test lit(items) == ["Copy"]
    evaluate_operation(nothing, ReplaceReferencedValueOperation(bar,
        ConcreteReference(FieldReferenceStep("elements"), EmptyReference()), CellVector(Any[cut])))
    @test lit(items) == []
end

end # @testset
end # function
