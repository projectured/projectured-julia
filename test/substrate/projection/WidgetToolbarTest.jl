# WidgetToolbar pointer routing. A toolbar lays its items out horizontally, so the
# light of the mouse target tracking must land on the item actually under the
# pointer. The item canvas is bounded to its footprint: a GraphicsText has no right
# edge, so an auto-sized item canvas (w=h=0) would take every point to its right,
# and the first button would light wherever the pointer is.

using ProjecturedKernel.CellModule: Cell, Computation

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

@testset "a crossing and a press land on the toolbar item under the pointer" begin
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

end # @testset
end # function
