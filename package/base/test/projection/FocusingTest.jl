# Tests for FocusingProjection's reified focus gestures (Ctrl+, focus out;
# Ctrl+. focus in). These characterise the firing of its
# `get_projection_gesture_bindings` table through `read_projection_gesture` —
# fire == show at the projection layer.

function test_focusing()
@testset "FocusingProjection gestures" begin
    ctrl = ModifierKeys(ctrl=true)
    input = [[1, 2], [3, 4]]

    # ── focus out: Ctrl+, drops the last step of the focus part ──────────────
    let fp = FocusingProjection(part_type=Vector, part=ReferencePath(PositionReferenceStep(1)))
        iomap = print_document(fp, nothing, input, nothing)
        op = read_intent(fp, iomap, KeyDown(:comma, ctrl))
        @test op isa ReplaceFocusPartOperation
        @test op.projection === fp
        @test op.part == EmptyReferencePath()           # the single step was dropped
    end

    # ── focus out declines when already at the root (empty part) ─────────────
    let fp = FocusingProjection()                         # part defaults to ∅
        iomap = print_document(fp, nothing, input, nothing)
        @test read_intent(fp, iomap, KeyDown(:comma, ctrl)) === nothing
    end

    # ── focus in declines when the input has no selection to descend into ────
    let fp = FocusingProjection(part_type=Vector, part=ReferencePath(PositionReferenceStep(1)))
        iomap = print_document(fp, nothing, input, nothing)   # raw Vector: no `.selection`
        @test read_intent(fp, iomap, KeyDown(:period, ctrl)) === nothing
    end

    # ── exact modifiers: a bare comma (no Ctrl) is not the focus-out gesture ──
    let fp = FocusingProjection(part_type=Vector, part=ReferencePath(PositionReferenceStep(1)))
        iomap = print_document(fp, nothing, input, nothing)
        @test read_intent(fp, iomap, KeyDown(:comma, ModifierKeys())) === nothing
    end
end
end
