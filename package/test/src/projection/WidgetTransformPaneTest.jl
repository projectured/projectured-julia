# Reader-level tests for WidgetTransformPane: Ctrl+wheel zooms about the cursor,
# a plain wheel pans, both as a `ReplaceReferencedValue(pane, "transform", M')`.
function test_widget_transform_pane()
@testset "WidgetTransformPane zoom/pan" begin

    # Deterministic measure: "M" → (10, 24), so the pan step (line height) is 24.
    _stub(t, f) = (max(1, length(t)) * 10, 24)
    _proj() = make_widget_projection_example(measure=_stub)

    # A pane with no insets, so the content offset is (0, 0) and the cursor
    # coordinate equals the viewport-space coordinate.
    _doc() = WidgetTransformPane(WidgetComposite(Point2D(0, 0),
                Any[WidgetLabel(Point2D(0, 0), "x")]); size=Point2D(200, 200))

    @testset "Ctrl+wheel zooms in about the cursor" begin
        doc   = _doc()
        proj  = _proj()
        iomap = projection_print(proj, doc)
        op = projection_read(proj, iomap, MouseScroll(0, 1, 50, 50, Modifiers(ctrl=true)))
        @test op isa ReplaceReferencedValue
        M = op.value
        @test M isa AffineTransform
        @test M.a ≈ 1.1            # zoomed in by one step
        @test M.d ≈ 1.1
        # The point under the cursor stays fixed: M·(50,50) == (50,50).
        @test all(affine_apply(M, 50.0, 50.0) .≈ (50.0, 50.0))
    end

    @testset "Ctrl+wheel zooms out below 1×" begin
        doc   = _doc()
        proj  = _proj()
        iomap = projection_print(proj, doc)
        op = projection_read(proj, iomap, MouseScroll(0, -1, 50, 50, Modifiers(ctrl=true)))
        @test op isa ReplaceReferencedValue
        @test op.value.a ≈ 1.0 / 1.1
    end

    @testset "zoom clamps at the maximum" begin
        doc   = WidgetTransformPane(WidgetComposite(Point2D(0, 0), Any[WidgetLabel(Point2D(0, 0), "x")]);
                                    size=Point2D(200, 200), transform=affine_scale(4.0, 4.0))
        proj  = _proj()
        iomap = projection_print(proj, doc)
        # Already at ZOOM_MAX (4.0); a further zoom-in is a no-op.
        op = projection_read(proj, iomap, MouseScroll(0, 1, 50, 50, Modifiers(ctrl=true)))
        @test op === nothing
    end

    @testset "plain wheel pans, does not zoom" begin
        doc   = _doc()
        proj  = _proj()
        iomap = projection_print(proj, doc)
        op = projection_read(proj, iomap, MouseScroll(0, 1, 50, 50, Modifiers()))
        @test op isa ReplaceReferencedValue
        M = op.value
        @test M.a ≈ 1.0            # no scale change
        @test M.d ≈ 1.0
        @test M.f ≈ 24.0           # panned vertically by the line step
        @test M.e ≈ 0.0
    end

    @testset "horizontal wheel pans on x" begin
        doc   = _doc()
        proj  = _proj()
        iomap = projection_print(proj, doc)
        op = projection_read(proj, iomap, MouseScroll(1, 0, 50, 50, Modifiers()))
        @test op isa ReplaceReferencedValue
        @test op.value.e ≈ 24.0
        @test op.value.f ≈ 0.0
    end

    @testset "successive zooms accumulate" begin
        doc   = _doc()
        proj  = _proj()
        iomap = projection_print(proj, doc)
        op1 = projection_read(proj, iomap, MouseScroll(0, 1, 50, 50, Modifiers(ctrl=true)))
        evaluate_operation(nothing, op1)
        op2 = projection_read(proj, iomap, MouseScroll(0, 1, 50, 50, Modifiers(ctrl=true)))
        @test op2.value.a ≈ 1.1 * 1.1
    end

end
end
