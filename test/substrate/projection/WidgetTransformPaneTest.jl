# Reader-level tests for WidgetTransformPane: Ctrl+wheel zooms about the cursor,
# a plain wheel pans, both as a write of `transform` marked as view state, so a
# history never records a zoom or a pan.
function test_widget_transform_pane()
@testset "WidgetTransformPane zoom/pan" begin

    # The transform an answer writes.
    _written(op) = get_wrapped_operation(op).value

    # Deterministic measure: "M" → (10, 24), so the pan step (line height) is 24.
    _stub(t, f) = (max(1, length(t)) * 10, 24)
    _proj() = make_widget_projection_example(measure=_stub)

    # A pane with no insets, so the content offset is (0, 0) and the cursor
    # coordinate equals the viewport-space coordinate.
    _doc() = WidgetTransformPane(WidgetComposite(Any[WidgetLabel("x")]); size=Point2D(200, 200))

    @testset "Ctrl+wheel zooms in about the cursor" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true)))
        @test op isa ReplaceViewStateOperation
        M = _written(op)
        @test M isa AffineTransform
        @test M.a ≈ 1.1            # zoomed in by one step
        @test M.d ≈ 1.1
        # The point under the cursor stays fixed: M·(50,50) == (50,50).
        @test all(apply_affine_transform(M, 50.0, 50.0) .≈ (50.0, 50.0))
    end

    @testset "Ctrl+wheel zooms out below 1×" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(0, -1, 50, 50, ModifierKeys(ctrl=true)))
        @test op isa ReplaceViewStateOperation
        @test _written(op).a ≈ 1.0 / 1.1
    end

    @testset "zoom clamps at the maximum" begin
        doc   = WidgetTransformPane(WidgetComposite(Any[WidgetLabel("x")]);
                                    size=Point2D(200, 200), transform=make_affine_scale(4.0, 4.0))
        proj  = _proj()
        iomap = print_document(proj, doc)
        # Already at ZOOM_MAX (4.0); a further zoom-in is a no-op.
        op = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true)))
        @test op === nothing
    end

    @testset "plain wheel pans, does not zoom" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys()))
        @test op isa ReplaceViewStateOperation
        M = _written(op)
        @test M.a ≈ 1.0            # no scale change
        @test M.d ≈ 1.0
        @test M.f ≈ 24.0           # panned vertically by the line step
        @test M.e ≈ 0.0
    end

    @testset "horizontal wheel pans on x" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(1, 0, 50, 50, ModifierKeys()))
        @test op isa ReplaceViewStateOperation
        @test _written(op).e ≈ 24.0
        @test _written(op).f ≈ 0.0
    end

    @testset "successive zooms accumulate" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op1 = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true)))
        evaluate_operation(nothing, op1)
        op2 = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true)))
        @test _written(op2).a ≈ 1.1 * 1.1
    end

    @testset "Ctrl+= zooms in about the viewport centre" begin
        doc   = _doc()                       # 200×200, no insets → centre (100,100)
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, KeyDown(:equals, ModifierKeys(ctrl=true)))
        @test op isa ReplaceViewStateOperation
        @test _written(op).a ≈ 1.1
        @test all(apply_affine_transform(_written(op), 100.0, 100.0) .≈ (100.0, 100.0))
    end

    @testset "Ctrl+- zooms out" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, KeyDown(:minus, ModifierKeys(ctrl=true)))
        @test op isa ReplaceViewStateOperation
        @test _written(op).a ≈ 1.0 / 1.1
    end

    @testset "Ctrl+0 resets to the identity" begin
        doc   = WidgetTransformPane(WidgetComposite(Any[WidgetLabel("x")]);
                                    size=Point2D(200, 200), transform=make_affine_scale(2.0, 2.0))
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, KeyDown(:zero, ModifierKeys(ctrl=true)))
        @test op isa ReplaceViewStateOperation
        @test _written(op) == affine_identity
    end

    @testset "Ctrl+0 at the identity is a no-op" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        @test read_intent(proj, iomap, KeyDown(:zero, ModifierKeys(ctrl=true))) === nothing
    end

    @testset "plain = (no Ctrl) does not zoom" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        @test read_intent(proj, iomap, KeyDown(:equals, ModifierKeys())) === nothing
    end

end
end
