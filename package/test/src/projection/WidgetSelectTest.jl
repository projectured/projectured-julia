# WidgetSelect dropdown (Stage 3, Step 3c). A click on the closed select emits an
# anchor-relative `OpenPopupOperation` whose content is a `VerticalLayout` of
# `WidgetOption`s; a content-root `WidgetPopupResolverProjection` maps the anchor
# forward to graphics coordinates and turns it into an absolute
# `OpenWindowOperation` (the window route). Clicking an option writes the value
# back to the select and closes the popup in one `CompoundOperation`.

mutable struct _SelectMockEditor
    document::Any
end

function test_widget_select_dropdown()
@testset "WidgetSelect dropdown" begin

# Symbols resolve from the enclosing `ProjecturedTest` module (`using Projectured`
# / `using ProjecturedExample`).
proj = make_layout_projection_example()

@testset "click opens the option list as an anchor-relative popup" begin
    select = WidgetSelect(Point2D(0, 0), "Apple";
                          options=["Apple", "Banana", "Cherry"], width=180)
    iomap = projection_print(proj, select)

    op = projection_read(proj, iomap, MousePress(:left, 5, 5, Modifiers()))
    @test op isa OpenPopupOperation
    @test op.id === :widget_popup
    @test op.auto_dismiss === true
    # Anchored to the select itself (its document path; empty as the root).
    @test op.anchor isa EmptyReferencePath
    # Opens below the box: zero horizontal offset, positive vertical offset.
    @test op.dx == 0
    @test op.dy > 0
    # Content is a column of one option per selectable value.
    @test op.content isa VerticalLayout
    @test length(op.content.children) == 3
    first_opt = op.content.children[1]
    @test first_opt isa WidgetOption
    @test first_opt.value == "Apple"
    @test first_opt.select === select
    @test first_opt.popup_id === :widget_popup
end

@testset "a select with no options is inert" begin
    select = WidgetSelect(Point2D(0, 0), "x"; width=120)
    iomap = projection_print(proj, select)
    @test projection_read(proj, iomap, MousePress(:left, 5, 5, Modifiers())) === nothing
end

@testset "a disabled select swallows the click" begin
    select = WidgetSelect(Point2D(0, 0), "Apple"; options=["Apple", "Banana"], enabled=false)
    iomap = projection_print(proj, select)
    @test projection_read(proj, iomap, MousePress(:left, 5, 5, Modifiers())) === nothing
end

@testset "the resolver maps the anchor to an absolute OpenWindowOperation" begin
    select = WidgetSelect(Point2D(0, 0), "Apple"; options=["Apple", "Banana"], width=180)
    # Mirror the real pipeline: the resolver wraps the content projection, isolated
    # through a NestingProjection (as HoverProbe does).
    inner = NestingProjection(proj; recursion = PreservingProjection())
    resolver = WidgetPopupResolverProjection(inner = inner)
    rio = projection_print(resolver, select)

    op = projection_read(resolver, rio, MousePress(:left, 5, 5, Modifiers()))
    @test op isa OpenWindowOperation
    @test op.id === :widget_popup
    @test op.style === :floating
    @test op.auto_dismiss === true
    @test op.content isa VerticalLayout
    # Select sits at the origin, so its top-left resolves to (0, 0); the popup opens
    # directly below (dx == 0, dy == box_height + gap > 0).
    @test op.x == 0
    @test op.y > 0
end

@testset "clicking an option writes the value back and closes the popup" begin
    select = WidgetSelect(Point2D(0, 0), "Apple"; options=["Apple", "Banana"], width=180)
    option = WidgetOption(Point2D(0, 0), select, "Banana"; width=180)
    oio = projection_print(proj, option)

    op = projection_read(proj, oio, MousePress(:left, 5, 5, Modifiers()))
    @test op isa CompoundOperation
    @test length(op.operations) == 2

    write = op.operations[1]
    @test write isa ReplaceReferencedValue
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
    select = WidgetSelect(Point2D(0, 0), "Apple"; options=["Apple"], width=120)
    option = WidgetOption(Point2D(0, 0), select, "Apple"; width=120)
    oio = projection_print(proj, option)
    @test projection_read(proj, oio, MousePress(:right, 5, 5, Modifiers())) === nothing
    @test select.value == "Apple"
end

end # @testset
end # function
