# WidgetContextMenu (Stage 3, Step 4d). A transparent wrapper around a child: a
# right click opens `menu` as a popup placed at the pointer via an anchor-relative
# `OpenPopupOperation` whose offset is the local click coordinates; a content-root
# `WidgetPopupResolverProjection` maps the wrapper's anchor forward and adds the
# offset, yielding an absolute `OpenWindowOperation` at the pointer. Non-right
# events route to the wrapped child.

mutable struct _CtxMenuMockEditor
    document::Any
end

function test_widget_context_menu()
@testset "WidgetContextMenu" begin

# Symbols resolve from the enclosing `ProjecturedTest` module (`using Projectured`
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

@testset "a right click opens the menu at the pointer" begin
    menu  = WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"), WidgetMenuItem("Paste")])
    child = WidgetLabel("right-click me")
    wrap  = WidgetContextMenu(child, menu)
    iomap = print_document(proj, wrap)

    op = read_intent(proj, iomap, MousePress(:right, 12, 7, ModifierKeys()))
    # To open a popup is not an edit, so the popup comes marked as view state.
    @test op isa ReplaceViewStateOperation
    popup = get_wrapped_operation(op)
    @test popup isa OpenPopupOperation
    @test popup.id === :widget_popup
    @test popup.auto_dismiss === true
    @test popup.x == 12                      # at the local click, in the wrapper's frame
    @test popup.y == 7
    @test popup.content === menu             # the popup content is the context menu
    @test popup.height > 0
end

@testset "a left click routes to the child, not the menu" begin
    fired = Ref(0)
    btn   = WidgetButton("OK"; size = Point2D(80, 24), action = (_e) -> (fired[] += 1))
    menu  = WidgetMenu([WidgetMenuItem("X")])
    wrap  = WidgetContextMenu(btn, menu)
    iomap = print_document(proj, wrap)

    op = read_intent(proj, iomap, MousePress(:left, 2, 2, ModifierKeys()))
    @test !(op isa OpenPopupOperation)
    @test op isa InvokeActionOperation
    @test op.action === btn.action
    evaluate_operation(_CtxMenuMockEditor(btn), op)
    @test fired[] == 1
end

@testset "a disabled wrapper ignores the right click" begin
    menu  = WidgetMenu([WidgetMenuItem("X")])
    wrap  = WidgetContextMenu(WidgetLabel("x"), menu; enabled = false)
    iomap = print_document(proj, wrap)
    @test read_intent(proj, iomap, MousePress(:right, 5, 5, ModifierKeys())) === nothing
end

@testset "a wrapper with no menu is inert on right click" begin
    wrap  = WidgetContextMenu(WidgetLabel("x"), nothing)
    iomap = print_document(proj, wrap)
    @test read_intent(proj, iomap, MousePress(:right, 5, 5, ModifierKeys())) === nothing
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
    op = get_wrapped_operation(read_intent(proj, iomap, MousePress(:right, ox + 20, oy + 9, ModifierKeys())))
    @test op isa OpenPopupOperation
    @test op.content === menu
    @test oy > 0
    @test (op.x, op.y) == (ox + 20, oy + 9)
end

end # @testset
end # function
