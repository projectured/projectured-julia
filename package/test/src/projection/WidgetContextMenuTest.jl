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

@testset "a right click opens the menu at the pointer" begin
    menu  = WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy"), WidgetMenuItem("Paste")])
    child = WidgetLabel(Point2D(0, 0), "right-click me")
    wrap  = WidgetContextMenu(child, menu)
    iomap = projection_print(proj, wrap)

    op = projection_read(proj, iomap, MousePress(:right, 12, 7, Modifiers()))
    @test op isa OpenPopupOperation
    @test op.id === :widget_popup
    @test op.auto_dismiss === true
    @test op.anchor isa EmptyReferencePath   # anchored to the wrapper itself (root)
    @test op.dx == 12                        # local click coords are the offset
    @test op.dy == 7
    @test op.content === menu                # the popup content is the context menu
    @test op.height > 0
end

@testset "a left click routes to the child, not the menu" begin
    fired = Ref(0)
    btn   = WidgetButton(Point2D(0, 0), Point2D(80, 24), "OK"; action = (_e) -> (fired[] += 1))
    menu  = WidgetMenu([WidgetMenuItem("X")])
    wrap  = WidgetContextMenu(btn, menu)
    iomap = projection_print(proj, wrap)

    op = projection_read(proj, iomap, MousePress(:left, 2, 2, Modifiers()))
    @test !(op isa OpenPopupOperation)
    @test op isa InvokeWidgetActionOperation
    @test op.widget === btn
    evaluate_operation(_CtxMenuMockEditor(btn), op)
    @test fired[] == 1
end

@testset "a disabled wrapper ignores the right click" begin
    menu  = WidgetMenu([WidgetMenuItem("X")])
    wrap  = WidgetContextMenu(WidgetLabel(Point2D(0, 0), "x"), menu; enabled = false)
    iomap = projection_print(proj, wrap)
    @test projection_read(proj, iomap, MousePress(:right, 5, 5, Modifiers())) === nothing
end

@testset "a wrapper with no menu is inert on right click" begin
    wrap  = WidgetContextMenu(WidgetLabel(Point2D(0, 0), "x"), nothing)
    iomap = projection_print(proj, wrap)
    @test projection_read(proj, iomap, MousePress(:right, 5, 5, Modifiers())) === nothing
end

@testset "the resolver places the menu at the pointer (absolute OpenWindowOperation)" begin
    menu = WidgetMenu([WidgetMenuItem("Cut"), WidgetMenuItem("Copy")])
    wrap = WidgetContextMenu(WidgetLabel(Point2D(0, 0), "target"), menu)
    # Mirror the real pipeline (as WidgetSelectTest does): the resolver wraps the
    # content projection, isolated through a NestingProjection.
    inner    = NestingProjection(proj; recursion = IdentityProjection())
    resolver = WidgetPopupResolverProjection(inner = inner)
    rio = projection_print(resolver, wrap)

    op = projection_read(resolver, rio, MousePress(:right, 20, 9, Modifiers()))
    @test op isa OpenWindowOperation
    @test op.id === :widget_popup
    @test op.style === :floating
    @test op.auto_dismiss === true
    @test op.content === menu
    # Wrapper sits at the origin, so its top-left resolves to (0, 0); the local
    # click offset (20, 9) places the popup under the pointer.
    @test op.x == 20
    @test op.y == 9
end

end # @testset
end # function
