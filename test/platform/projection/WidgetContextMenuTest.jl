# WidgetContextMenu: a transparent wrapper around a child. Its gesture table
# answers a right click with an `OpenContextMenuOperation` that holds `menu` and the
# point of the click, in the frame of the wrapper; each reader above moves the
# point into its own frame. The wrapper that keeps the context menu window at the
# screen opens the window (`ContextMenuWindowTest`). Every other event routes to
# the wrapped child.

mutable struct _CtxMenuMockEditor
    document::Any
end

function test_widget_context_menu()
@testset "WidgetContextMenu" begin

# Symbols resolve from the enclosing `ProjecturedTest` module (`using ProjecturedAll`
# / `using ProjecturedExample`).
proj = make_layout_projection_example()

# The IO map of `document` in the IO map tree of a print: the example projection
# is a chain, so the widget's own IO map sits inside the IO map of the print. The
# chain has the same input, so the deepest IO map of `document` is the one.
function _context_iomap_of(iomap, document, depth = 0)
    depth > 12 && return nothing
    for field in fieldnames(typeof(iomap))
        value = getfield(iomap, field)
        value = value isa CellModule.Cell ? value[] : value
        for candidate in (value isa AbstractVector ? value : (value,))
            candidate = candidate isa CellModule.Cell ? candidate[] : candidate
            candidate isa Tuple && (candidate = last(candidate))
            candidate isa IoMap || continue
            found = _context_iomap_of(candidate, document, depth + 1)
            found === nothing || return found
        end
    end
    iomap.input === document ? iomap : nothing
end

@testset "a right click answers the menu at the pointer" begin
    menu  = WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"), WidgetMenuItem("Paste")])
    child = WidgetLabel("right-click me")
    wrap  = WidgetContextMenu(child, menu)
    iomap = print_document(proj, wrap)

    op = read_intent(proj, iomap, MouseClick(:right, 12, 7, ModifierKeys(); time = 0.0))
    # To open a menu is not an edit, so the menu comes marked as view state.
    @test op isa ReplaceViewStateOperation
    opened = get_wrapped_operation(op)
    @test opened isa OpenContextMenuOperation
    @test opened.point == (12, 7)            # at the local click, in the wrapper's frame
    title, shown = only(opened.layers)
    @test title == "WidgetContextMenu"
    @test shown === menu                     # the menu of the wrapper
    # The part is the wrapper itself.
    @test strip_reference_types(opened.source) isa EmptyReference
end

@testset "a left click routes to the child, not the menu" begin
    fired = Ref(0)
    btn   = WidgetButton("OK"; size = Point2D(80, 24), action = (_e) -> (fired[] += 1))
    menu  = WidgetMenu([WidgetMenuItem("X")])
    wrap  = WidgetContextMenu(btn, menu)
    iomap = print_document(proj, wrap)

    op = read_intent(proj, iomap, MouseClick(:left, 2, 2, ModifierKeys(); time = 0.0))
    @test op isa InvokeActionOperation
    @test op.action === btn.action
    evaluate_operation(_CtxMenuMockEditor(btn), op)
    @test fired[] == 1
end

@testset "a disabled wrapper ignores the right click" begin
    menu  = WidgetMenu([WidgetMenuItem("X")])
    wrap  = WidgetContextMenu(WidgetLabel("x"), menu; enabled = false)
    iomap = print_document(proj, wrap)
    @test read_intent(proj, iomap, MouseClick(:right, 5, 5, ModifierKeys(); time = 0.0)) === nothing
end

@testset "a wrapper with no menu is inert on right click" begin
    wrap  = WidgetContextMenu(WidgetLabel("x"), nothing)
    iomap = print_document(proj, wrap)
    @test read_intent(proj, iomap, MouseClick(:right, 5, 5, ModifierKeys(); time = 0.0)) === nothing
end

@testset "a layout moves the menu of a wrapper into its own frame" begin
    menu = WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy")])
    wrap = WidgetContextMenu(WidgetLabel("target"), menu)
    layout = VerticalLayout(Any[WidgetLabel("above"), wrap])
    iomap = print_document(proj, layout)
    # The press lands 20 and 9 pixels into the wrapper, below the label, and the
    # menu opens at the press, in the frame of the layout.
    (x_cell, y_cell, _) = getfield(_context_iomap_of(iomap, layout), :child_iomaps)[][2]
    ox, oy = Int(x_cell[]), Int(y_cell[])
    press = MouseClick(:right, ox + 20, oy + 9, ModifierKeys(); time = 0.0)
    op = get_wrapped_operation(read_intent(proj, iomap, press))
    @test op isa OpenContextMenuOperation
    @test only(op.layers)[2] === menu
    @test oy > 0
    @test op.point == (ox + 20, oy + 9)
    # The part is the second child of the layout.
    @test strip_reference_types(op.source) ==
          ConcreteReference(FieldReferenceStep("children"),
                            ConcreteReference(RangeReferenceStep(1, 2), EmptyReference()))
end

@testset "a nearer wrapper gives the first menu, and the wrapper around it the next" begin
    inner = WidgetMenu([WidgetMenuItem("Rename")])
    outer = WidgetMenu([WidgetMenuItem("Close")])
    wrap = WidgetContextMenu(WidgetContextMenu(WidgetLabel("target"), inner), outer)
    iomap = print_document(proj, wrap)
    press = MouseClick(:right, 5, 5, ModifierKeys(); time = 0.0)
    op = get_wrapped_operation(read_intent(proj, iomap, press))
    @test op isa OpenContextMenuOperation
    @test length(op.layers) == 2
    @test op.layers[1][2] === inner && op.layers[2][2] === outer
    @test strip_reference_types(op.source) ==
          ConcreteReference(FieldReferenceStep("child"), EmptyReference())
end

end # @testset
end # function
