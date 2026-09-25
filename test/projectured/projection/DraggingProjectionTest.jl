# Reader-level tests for DraggingProjection. We feed a synthetic
# MouseDown → MouseMove → MouseUp sequence through the projection and assert the
# state machine's phase transitions, the emitted MoveRangeOperation, and the
# resulting collection order after evaluation.
#
# DraggingProjection resolves the grab/drop targets by synthesising a MousePress
# at the press/release point and delegating it to the inner chain (the real
# graphics-layer hit-test path). Here a stub inner projection plays the graphics
# chain: it maps a synthetic MousePress's x coordinate to a content-domain
# reference, so the DraggingProjection logic is exercised end-to-end without the
# full pixel pipeline.


# Stub inner projection: `f(gesture) -> op` plays the graphics-layer hit-test.
struct _CoordStub <: Projection
    f::Any
end
ProjectionModule.read_intent(p::_CoordStub, recursion, change::Intent, iomap) =
    Intent(change.gesture, p.f(change.gesture))

struct _StubInner
    projection::Any
    output::Any
end

_elem_path(i) = ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(ElementReferenceStep(i), EmptyReference()))

# Build (projection, iomap) for a DraggingState wrapping `content`; the inner
# stub resolves a synthetic MousePress via `hit` (a `gesture -> op` function).
function _drag_setup(content, hit)
    proj  = DraggingProjection()
    state = DraggingState(content, 5)
    inner = _StubInner(_CoordStub(hit), nothing)
    iomap = DraggingIoMap(proj, state, nothing, inner)
    (proj, iomap)
end

_feed(proj, iomap, evt) = read_intent(proj, iomap, evt)

function test_dragging()
@testset "DraggingProjection drag-and-drop" begin

    # Map a synthetic MousePress's x to an element reference: x=100 → 2, x=300 → 4.
    _hit_2_or_4(g) = g isa MousePress ?
        (g.x == 100 ? ReplaceSelectionOperation(_elem_path(2)) :
         g.x == 300 ? ReplaceSelectionOperation(_elem_path(4)) : nothing) : nothing

    @testset "press → drag → drop reorders the collection" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20), JsonNumber(30), JsonNumber(40))
        c2 = get_cell_at(content.elements, 2)
        proj, iomap = _drag_setup(content, _hit_2_or_4)

        # MouseDown hit-tests the grab point (x=100 → element 2) and arms a
        # pending drag, absorbing the press.
        @test _feed(proj, iomap, MouseDown(:left, 100, 100, ModifierKeys())) === nothing
        @test proj.state.phase === :pending

        # A move past the 5px threshold activates the drag, still absorbed.
        @test _feed(proj, iomap, MouseMove(120, 100, MouseButtons(:left), ModifierKeys())) === nothing
        @test proj.state.phase === :dragging

        # MouseUp hit-tests the drop point (x=300 → element 4): element 2 moves there.
        op = _feed(proj, iomap, MouseUp(:left, 300, 100, ModifierKeys()))
        @test op isa MoveRangeOperation
        @test proj.state.phase === :idle

        evaluate_operation(nothing, op)
        @test [Int(content.elements[i].value) for i in 1:4] == [10, 30, 20, 40]
        @test get_cell_at(content.elements, 3) === c2          # cell identity preserved
    end

    @testset "sub-threshold press-release is a click, not a drag" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20), JsonNumber(30))
        proj, iomap = _drag_setup(content, _hit_2_or_4)

        @test _feed(proj, iomap, MouseDown(:left, 100, 100, ModifierKeys())) === nothing
        @test proj.state.phase === :pending
        # Release within threshold (2px): no drag, no op — the backend's
        # synthesised MousePress handles the click selection separately.
        op = _feed(proj, iomap, MouseUp(:left, 102, 100, ModifierKeys()))
        @test op === nothing
        @test proj.state.phase === :idle
        @test [Int(content.elements[i].value) for i in 1:3] == [10, 20, 30]
    end

    @testset "drop on an unresolvable target yields no move" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20))
        # Grab resolves (x=100 → element 2), but the drop point (x=999) hits nothing.
        hit(g) = g isa MousePress && g.x == 100 ? ReplaceSelectionOperation(_elem_path(2)) : nothing
        proj, iomap = _drag_setup(content, hit)

        _feed(proj, iomap, MouseDown(:left, 100, 100, ModifierKeys()))
        _feed(proj, iomap, MouseMove(120, 100, MouseButtons(:left), ModifierKeys()))
        op = _feed(proj, iomap, MouseUp(:left, 999, 100, ModifierKeys()))
        @test !(op isa MoveRangeOperation)
        @test [Int(content.elements[i].value) for i in 1:2] == [10, 20]
    end

    # End-to-end through the real json → syntax → text → graphics pipeline: the
    # grab/drop points are resolved by the actual graphics-layer hit-test (no
    # stub). The array renders one element per line at y = 24/48/72, x ≈ 24.
    @testset "real pipeline: drag an array element to reorder" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20), JsonNumber(30))
        c1 = get_cell_at(content.elements, 1)
        inner = print_document(make_json_projection_example(), content)
        proj  = DraggingProjection()
        iomap = DraggingIoMap(proj, DraggingState(content, 5),
                                        inner.output, inner)

        @test _feed(proj, iomap, MouseDown(:left, 24, 24, ModifierKeys())) === nothing   # grab element 1
        @test proj.state.phase === :pending
        _feed(proj, iomap, MouseMove(24, 48, MouseButtons(:left), ModifierKeys()))                     # cross threshold
        @test proj.state.phase === :dragging
        op = _feed(proj, iomap, MouseUp(:left, 24, 72, ModifierKeys()))                  # drop at element 3
        @test op isa MoveRangeOperation
        @test op.source_start == 1 && op.destination_index == 3

        evaluate_operation(nothing, op)
        @test [Int(content.elements[i].value) for i in 1:3] == [20, 10, 30]
        @test get_cell_at(content.elements, 2) === c1                                     # identity preserved
    end

end
end
