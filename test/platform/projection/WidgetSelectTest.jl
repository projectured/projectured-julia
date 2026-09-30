# WidgetSelect dropdown. A click on the closed select answers an
# `OpenPopupOperation` just below it, in its own frame, whose content is a
# vertical `WidgetMenu` of `WidgetOption`s; each reader above moves the position
# into its own frame. Clicking an option writes the value back to the select and
# closes the popup in one `CompoundOperation`.

mutable struct _SelectMockEditor
    document::Any
end

function test_widget_select_dropdown()
@testset "WidgetSelect dropdown" begin

# Symbols resolve from the enclosing `ProjecturedTest` module (`using Projectured`
# / `using ProjecturedExample`).
proj = make_layout_projection_example()

_select_popup(op) = op isa ReplaceViewStateOperation ? get_wrapped_operation(op) : op

# The IO map of `document` in the IO map tree of a print: the example projection
# is a chain, so the widget's own IO map sits inside the IO map of the print. The
# chain has the same input, so the deepest IO map of `document` is the one.
function _select_iomap_of(iomap, document, depth = 0)
    depth > 12 && return nothing
    for field in fieldnames(typeof(iomap))
        value = getfield(iomap, field)
        value = value isa CellModule.Cell ? value[] : value
        for candidate in (value isa AbstractVector ? value : (value,))
            candidate = candidate isa CellModule.Cell ? candidate[] : candidate
            candidate isa Tuple && (candidate = last(candidate))
            candidate isa IoMap || continue
            found = _select_iomap_of(candidate, document, depth + 1)
            found === nothing || return found
        end
    end
    iomap.input === document ? iomap : nothing
end

@testset "click opens the option list below the box" begin
    select = WidgetSelect("Apple";
                          options=["Apple", "Banana", "Cherry"], width=180)
    iomap = print_document(proj, select)

    # To open a popup is not an edit, so the popup comes marked as view state.
    marked = read_intent(proj, iomap, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0))
    @test marked isa ReplaceViewStateOperation
    op = _select_popup(marked)
    @test op isa OpenPopupOperation
    @test op.id === :widget_popup
    @test op.auto_dismiss === true
    # Opens just below the box, in the select's own frame.
    @test op.x == 0
    @test op.y == _select_iomap_of(iomap, select).control_height + 4
    # Content is a dropdown of one option per selectable value.
    @test op.content isa WidgetMenu
    @test length(op.content.elements) == 3
    first_opt = op.content.elements[1]
    @test first_opt isa WidgetOption
    @test first_opt.value == "Apple"
    @test first_opt.select === select
    @test first_opt.popup_id === :widget_popup
end

@testset "a select with no options is inert" begin
    select = WidgetSelect("x"; width=120)
    iomap = print_document(proj, select)
    @test read_intent(proj, iomap, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0)) === nothing
end

@testset "a disabled select swallows the click" begin
    select = WidgetSelect("Apple"; options=["Apple", "Banana"], enabled=false)
    iomap = print_document(proj, select)
    @test read_intent(proj, iomap, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0)) === nothing
end

@testset "a layout moves the popup of a select into its own frame" begin
    select = WidgetSelect("Apple"; options=["Apple", "Banana"], width=180)
    layout = VerticalLayout(Any[WidgetLabel("above"), select])
    iomap = print_document(proj, layout)
    # The press lands on the select, below the label, and the dropdown opens
    # below the select, in the frame of the layout.
    (x_cell, y_cell, cim) = getfield(_select_iomap_of(iomap, layout), :child_iomaps)[][2]
    ox, oy = Int(x_cell[]), Int(y_cell[])
    op = _select_popup(read_intent(proj, iomap, MouseClick(:left, ox + 5, oy + 5, ModifierKeys(); time = 0.0)))
    @test op isa OpenPopupOperation
    @test oy > 0
    @test op.x == ox
    @test op.y == oy + cim.control_height + 4
end

@testset "a scrolled pane moves the popup of a select by its scroll offset" begin
    select = WidgetSelect("Apple"; options=["Apple", "Banana"], width=180)
    layout = VerticalLayout(Any[WidgetLabel("above"), select])
    (_, y_cell, cim) = getfield(_select_iomap_of(print_document(proj, layout), layout), :child_iomaps)[][2]
    oy = Int(y_cell[])
    # The viewport is shorter than the layout, so a scroll of 10 is kept, and the
    # select is drawn 10 pixels higher than the layout places it.
    pane = WidgetScrollPane(layout; size = Point2D(200, 30), scroll_position = Point2D(0, 10))
    iomap = print_document(proj, pane)
    op = _select_popup(read_intent(proj, iomap, MouseClick(:left, 5, oy - 10 + 5, ModifierKeys(); time = 0.0)))
    @test op isa OpenPopupOperation
    @test op.x == 0
    @test op.y == oy - 10 + cim.control_height + 4
end

@testset "a zoomed pane moves the popup of a select through its transform" begin
    select = WidgetSelect("Apple"; options=["Apple", "Banana"], width=180)
    height = _select_iomap_of(print_document(proj, select), select).control_height
    pane = WidgetTransformPane(VerticalLayout(Any[select]); size = Point2D(400, 400),
                               transform = make_affine_scale(2.0, 2.0))
    iomap = print_document(proj, pane)
    # At twice the size, the select is drawn at twice its extent, and so is the
    # place just below it; the bound of the popup stays in screen pixels.
    op = _select_popup(read_intent(proj, iomap, MouseClick(:left, 10, 10, ModifierKeys(); time = 0.0)))
    @test op isa OpenPopupOperation
    @test op.x == 0
    @test op.y == 2 * (height + 4)
    @test (op.width, op.height) == (640, 800)
end

@testset "clicking an option writes the value back and closes the popup" begin
    select = WidgetSelect("Apple"; options=["Apple", "Banana"], width=180)
    option = WidgetOption(select, "Banana"; width=180)
    oio = print_document(proj, option)

    op = read_intent(proj, oio, MouseClick(:left, 5, 5, ModifierKeys(); time = 0.0))
    @test op isa CompoundOperation
    @test length(op.operations) == 2

    write = op.operations[1]
    @test write isa ReplaceReferencedValueOperation
    @test write.document === select          # identity-rooted: targets the real select
    @test write.value == "Banana"

    close = op.operations[2]
    @test close isa CloseWindowOperation
    @test close.id === :widget_popup

    # Applying the write updates the select's value (the close is owned by the
    # WindowManager; see TooltipTest's focus-lost/close coverage).
    @test select.value == "Apple"
    evaluate_operation(_SelectMockEditor(select), write)
    @test select.value == "Banana"
end

@testset "a non-left click on an option does nothing" begin
    select = WidgetSelect("Apple"; options=["Apple"], width=120)
    option = WidgetOption(select, "Apple"; width=120)
    oio = print_document(proj, option)
    @test read_intent(proj, oio, MouseClick(:right, 5, 5, ModifierKeys(); time = 0.0)) === nothing
    @test select.value == "Apple"
end

end # @testset
end # function
