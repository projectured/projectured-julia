# Reader-level tests for DraggingProjection. The state of a drag is the press that
# the `DraggingState` keeps. The source and the target are the elements that the
# mouse target of the content names at the press and at the release, as a move of
# the pointer writes it. A stub inner projection answers nothing, so the logic of
# the DraggingProjection runs alone; the last test goes through the real pipeline,
# where a move names the part under the pointer.

struct _DraggingStub <: Projection end
ProjectionModule.read_intent(::_DraggingStub, recursion, change::Intent, iomap) =
    Intent(change.gesture, nothing)

struct _StubInner
    projection::Any
    output::Any
end

_elem_path(i) = ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(ElementReferenceStep(i), EmptyReference()))

# (projection, state, iomap) for a DraggingState that wraps `content`.
function _drag_setup(content)
    proj = DraggingProjection()
    state = DraggingState(content, 5)
    (proj, state, DraggingIoMap(proj, state, nothing, _StubInner(_DraggingStub(), nothing)))
end

_feed(proj, iomap, evt) = read_intent(proj, iomap, evt)

# Evaluate an answer as the editor does: the part under the pointer by the chain
# write at `root`, and every other operation on its own document.
function _drag_apply!(root, op)
    op === nothing && return
    if op isa CompoundOperation
        foreach(member -> _drag_apply!(root, member), op.operations)
    elseif op isa ReplaceMouseTargetOperation
        replace_mouse_target!(root, op.path)
    else
        evaluate_operation(nothing, op)
    end
    nothing
end

# Whether `op` holds an operation of type `T`.
_drag_holds(op, T) = op isa T ||
    (op isa CompoundOperation && any(member -> _drag_holds(member, T), op.operations)) ||
    (op isa ReplaceViewStateOperation && _drag_holds(get_wrapped_operation(op), T))

# The `MoveRangeOperation` in `op`, or `nothing`.
function _drag_move_of(op)
    op isa MoveRangeOperation && return op
    if op isa CompoundOperation
        for member in op.operations
            found = _drag_move_of(member)
            found === nothing || return found
        end
    end
    nothing
end

_drag_held(x, y) = MouseMove(x, y, MouseButtons(:left), ModifierKeys(); time = 0.0)

function test_dragging()
@testset "DraggingProjection drag-and-drop" begin

    @testset "press → drag → drop reorders the collection" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20), JsonNumber(30), JsonNumber(40))
        c2 = get_cell_at(content.elements, 2)
        proj, state, iomap = _drag_setup(content)

        # The pointer is over element 2: the press keeps it as the source, and
        # the press goes no further.
        replace_mouse_target!(content, _elem_path(2))
        _drag_apply!(state, _feed(proj, iomap, MouseDown(:left, 100, 100, ModifierKeys(); time = 0.0)))
        @test state.press !== nothing && state.press.started == false
        @test strip_reference_types(state.press.source) == _elem_path(2)

        # A move past the 5px threshold starts the drag of the state.
        start = _feed(proj, iomap, _drag_held(120, 100))
        @test _drag_holds(start, StartDragOperation)
        _drag_apply!(state, start)
        @test state.press.started

        # The pointer is over element 4 at the release: element 2 moves there.
        replace_mouse_target!(content, _elem_path(4))
        op = _feed(proj, iomap, DragEnd(300, 100; time = 0.0))
        @test _drag_move_of(op) isa MoveRangeOperation
        _drag_apply!(state, op)
        @test state.press === nothing
        @test [Int(content.elements[i].value) for i in 1:4] == [10, 30, 20, 40]
        @test get_cell_at(content.elements, 3) === c2          # cell identity preserved
    end

    @testset "sub-threshold press-release is a click, not a drag" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20), JsonNumber(30))
        proj, state, iomap = _drag_setup(content)
        replace_mouse_target!(content, _elem_path(2))
        _drag_apply!(state, _feed(proj, iomap, MouseDown(:left, 100, 100, ModifierKeys(); time = 0.0)))
        # A move within the threshold (2px) starts no drag.
        @test !_drag_holds(_feed(proj, iomap, _drag_held(102, 100)), StartDragOperation)
        # The release ends the press; the click that the gesture tracker makes of
        # it selects separately.
        op = _feed(proj, iomap, MouseUp(:left, 102, 100, ModifierKeys(); time = 0.0))
        @test !_drag_holds(op, MoveRangeOperation)
        _drag_apply!(state, op)
        @test state.press === nothing
        @test [Int(content.elements[i].value) for i in 1:3] == [10, 20, 30]
    end

    @testset "a drop where no element is under the pointer yields no move" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20))
        proj, state, iomap = _drag_setup(content)
        replace_mouse_target!(content, _elem_path(2))
        _drag_apply!(state, _feed(proj, iomap, MouseDown(:left, 100, 100, ModifierKeys(); time = 0.0)))
        _drag_apply!(state, _feed(proj, iomap, _drag_held(120, 100)))
        replace_mouse_target!(content, nothing)
        op = _feed(proj, iomap, DragEnd(999, 100; time = 0.0))
        @test _drag_move_of(op) === nothing
        _drag_apply!(state, op)
        @test state.press === nothing
        @test [Int(content.elements[i].value) for i in 1:2] == [10, 20]
    end

    @testset "a cancel ends the drag with no move" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20), JsonNumber(30))
        proj, state, iomap = _drag_setup(content)
        replace_mouse_target!(content, _elem_path(1))
        _drag_apply!(state, _feed(proj, iomap, MouseDown(:left, 100, 100, ModifierKeys(); time = 0.0)))
        _drag_apply!(state, _feed(proj, iomap, _drag_held(130, 100)))
        replace_mouse_target!(content, _elem_path(3))
        op = _feed(proj, iomap, DragCancel(; time = 0.0))
        @test _drag_move_of(op) === nothing
        _drag_apply!(state, op)
        @test state.press === nothing
        @test [Int(content.elements[i].value) for i in 1:3] == [10, 20, 30]
    end

    # End-to-end through the real json → syntax → text → graphics pipeline: a move
    # names the element under the pointer, as the window of an editor does. The
    # array renders one element per line, 14 high; the middle of each line is at
    # y = 21/35/49, and x ≈ 21 is the middle of the two digits.
    @testset "real pipeline: drag an array element to reorder" begin
        content = JsonArray(JsonNumber(10), JsonNumber(20), JsonNumber(30))
        c1 = get_cell_at(content.elements, 1)
        inner = print_document(make_json_projection_example(), content)
        proj  = DraggingProjection()
        state = DraggingState(content, 5)
        iomap = DraggingIoMap(proj, state, inner.output, inner)
        point!(x, y) = _drag_apply!(content, read_child_move(inner, MouseMove(x, y; time = 0.0)))

        point!(21, 21)                                                   # over element 1
        _drag_apply!(state, _feed(proj, iomap, MouseDown(:left, 21, 21, ModifierKeys(); time = 0.0)))
        start = _feed(proj, iomap, _drag_held(21, 35))                  # cross the threshold
        @test _drag_holds(start, StartDragOperation)
        _drag_apply!(state, start)
        point!(21, 49)                                                   # over element 3
        op = _feed(proj, iomap, DragEnd(21, 49; time = 0.0))
        move = _drag_move_of(op)
        @test move isa MoveRangeOperation
        @test move.source_start == 1 && move.destination_index == 3

        _drag_apply!(state, op)
        @test [Int(content.elements[i].value) for i in 1:3] == [20, 10, 30]
        @test get_cell_at(content.elements, 2) === c1                    # identity preserved
    end

end
end
