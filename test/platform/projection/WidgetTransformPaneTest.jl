# Reader-level tests for WidgetTransformPane: Ctrl+wheel zooms about the cursor,
# a plain wheel pans, both as a write of `transform` marked as view state, so a
# history never records a zoom or a pan.
function test_widget_transform_pane()
@testset "WidgetTransformPane zoom/pan" begin

    # The transform an answer writes. A pan writes it first, before the run of
    # the wheel.
    _written(op) = get_wrapped_operation(op isa CompoundOperation ? first(op.operations) : op).value

    # Deterministic measure: "M" → (10, 24), so the pan step (line height) is 24.
    _stub = FixedMeasure(10, 18, 6, 0)
    _proj() = make_widget_projection_example(measure=_stub)

    # A pane with no insets, so the content offset is (0, 0) and the cursor
    # coordinate equals the viewport-space coordinate.
    _doc() = WidgetTransformPane(WidgetComposite(Any[WidgetLabel("x")]); size=Point2D(200, 200))

    @testset "Ctrl+wheel zooms in about the cursor" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true); time = 0.0))
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
        op = read_intent(proj, iomap, MouseScroll(0, -1, 50, 50, ModifierKeys(ctrl=true); time = 0.0))
        @test op isa ReplaceViewStateOperation
        @test _written(op).a ≈ 1.0 / 1.1
    end

    @testset "zoom clamps at the maximum" begin
        doc   = WidgetTransformPane(WidgetComposite(Any[WidgetLabel("x")]);
                                    size=Point2D(200, 200), transform=make_affine_scale(4.0, 4.0))
        proj  = _proj()
        iomap = print_document(proj, doc)
        # Already at ZOOM_MAX (4.0); a further zoom-in is a no-op.
        op = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true); time = 0.0))
        @test op === nothing
    end

    @testset "plain wheel pans, does not zoom" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(); time = 0.0))
        @test op isa CompoundOperation
        @test all(o -> o isa ReplaceViewStateOperation, op.operations)
        M = _written(op)
        @test M.a ≈ 1.0            # no scale change
        @test M.d ≈ 1.0
        @test M.f ≈ 72.0           # panned vertically by three lines of 24
        @test M.e ≈ 0.0
    end

    @testset "horizontal wheel pans on x" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(1, 0, 50, 50, ModifierKeys(); time = 0.0))
        @test op isa CompoundOperation
        @test _written(op).e ≈ 72.0
        @test _written(op).f ≈ 0.0
    end

    @testset "a touchpad pans by the fraction of a notch" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(0, 0, 50, 50, ModifierKeys(); time = 0.0,
                                                  precise_dy = 0.5))
        @test _written(op).f ≈ 36.0     # half of three lines of 24
    end

    @testset "Ctrl and the wheel zoom a step for each notch, and not for a fraction" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, MouseScroll(0, 2, 50, 50, ModifierKeys(ctrl=true); time = 0.0))
        @test _written(op).a ≈ 1.1^2
        @test read_intent(proj, iomap, MouseScroll(0, 0, 50, 50, ModifierKeys(ctrl=true); time = 0.0,
                                                   precise_dy = 0.3)) === nothing
    end

    @testset "Ctrl and the wheel zoom a pane inside a composite" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, WidgetComposite(Any[doc]))
        op = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true); time = 0.0))
        @test _written(op).a ≈ 1.1
    end

    # The shape of a dashboard: a pane in a card, and the card in a scroll pane
    # that is shorter than the card. The card gives the wheel to the slot under
    # the pointer.
    _card_page() = WidgetScrollPane(WidgetCard(; title = WidgetLabel("plot"), content = _doc());
                                    size = Point2D(240, 120))

    @testset "Ctrl and the wheel zoom a pane in a card, and do not scroll the page" begin
        proj  = _proj()
        iomap = print_document(proj, _card_page())
        op = read_intent(proj, iomap, MouseScroll(0, 1, 50, 80, ModifierKeys(ctrl=true); time = 0.0))
        @test _written(op) isa AffineTransform
        @test _written(op).a ≈ 1.1
    end

    @testset "a turn that no slot of a card uses scrolls the page" begin
        proj  = _proj()
        iomap = print_document(proj, _card_page())
        op = read_intent(proj, iomap, MouseScroll(0, -1, 50, 12, ModifierKeys(); time = 0.0))
        @test _written(op) isa Point2D
        @test Int(_written(op).y[]) > 0
    end

    @testset "successive zooms accumulate" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op1 = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true); time = 0.0))
        evaluate_operation(nothing, op1)
        op2 = read_intent(proj, iomap, MouseScroll(0, 1, 50, 50, ModifierKeys(ctrl=true); time = 0.0))
        @test _written(op2).a ≈ 1.1 * 1.1
    end

    @testset "Ctrl+= zooms in about the viewport centre" begin
        doc   = _doc()                       # 200×200, no insets → centre (100,100)
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, KeyDown(:equals, ModifierKeys(ctrl=true); time = 0.0))
        @test op isa ReplaceViewStateOperation
        @test _written(op).a ≈ 1.1
        @test all(apply_affine_transform(_written(op), 100.0, 100.0) .≈ (100.0, 100.0))
    end

    @testset "Ctrl+- zooms out" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, KeyDown(:minus, ModifierKeys(ctrl=true); time = 0.0))
        @test op isa ReplaceViewStateOperation
        @test _written(op).a ≈ 1.0 / 1.1
    end

    @testset "Ctrl+0 resets to the identity" begin
        doc   = WidgetTransformPane(WidgetComposite(Any[WidgetLabel("x")]);
                                    size=Point2D(200, 200), transform=make_affine_scale(2.0, 2.0))
        proj  = _proj()
        iomap = print_document(proj, doc)
        op = read_intent(proj, iomap, KeyDown(:zero, ModifierKeys(ctrl=true); time = 0.0))
        @test op isa ReplaceViewStateOperation
        @test _written(op) == affine_identity
    end

    @testset "Ctrl+0 at the identity is a no-op" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        @test read_intent(proj, iomap, KeyDown(:zero, ModifierKeys(ctrl=true); time = 0.0)) === nothing
    end

    @testset "plain = (no Ctrl) does not zoom" begin
        doc   = _doc()
        proj  = _proj()
        iomap = print_document(proj, doc)
        @test read_intent(proj, iomap, KeyDown(:equals, ModifierKeys(); time = 0.0)) === nothing
    end

end
end
