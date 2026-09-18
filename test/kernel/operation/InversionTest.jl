"""
`OperationModule` — the way back. Verifies `make_inverse_operation` for every
operation this layer owns, the order `evaluate_invertible_operation!` keeps for a
container, and the `get_slot_at` seam. Each case is one round trip: apply, then
apply the inverse, and the document is what it was.

A **test-local** operation with no method proves the default is `nothing`, and a
test-local wrapper proves a wrapper's way back is the way back of what it holds.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.CellModule: unwrap_cell
using ProjecturedKernel.OperationModule
using ProjecturedKernel.DocumentModule: @document, Document
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.SelectionModule

@document struct InvLeaf
    value::String
end

@document struct InvBranch
    left::InvLeaf
    right::InvLeaf
end

@document struct InvList
    items::Vector{Any}
end

@document struct InvBox
    collapsed::Bool
end

# The editor an operation is applied against: whatever object holds the document.
mutable struct _InvEditor
    document::Any
end

# A test-local operation nobody taught to invert. It must answer `nothing`, which
# is what makes a history stop at it rather than undo past it.
struct InvOpaqueOperation <: Operation end

# A test-local wrapper: its way back is the way back of what it holds.
struct InvWrapperOperation <: WrappingOperation
    operation::Any
end
ProjecturedKernel.OperationModule.get_wrapped_operation(op::InvWrapperOperation) = op.operation
ProjecturedKernel.OperationModule.rewrap_operation(::InvWrapperOperation, inner) =
    InvWrapperOperation(inner)

_leaf(text) = InvLeaf(text, nothing)
_values(list) = [unwrap_cell(item).value for item in list.items]

function test_inversion()
@testset "Inversion" begin

    @testset "an operation nobody taught to invert has no way back" begin
        @test make_inverse_operation(nothing, InvOpaqueOperation()) === nothing
        @test make_inverse_operation(nothing, nothing) === nothing
    end

    @testset "an operation that changes no document is undone by doing nothing" begin
        @test make_inverse_operation(nothing, DoNothingOperation()) isa DoNothingOperation
        @test make_inverse_operation(nothing, QuitEditorOperation()) isa DoNothingOperation
        @test make_inverse_operation(nothing, AdjustZoomOperation(1)) isa DoNothingOperation
        @test make_inverse_operation(nothing, AdjustFontZoomOperation(-1)) isa DoNothingOperation
    end

    @testset "a field write puts back what the field held" begin
        root = InvBranch(_leaf("a"), _leaf("b"), nothing)
        editor = _InvEditor(root)
        reference = Reference(FieldReferenceStep("left"), FieldReferenceStep("value"))
        operation = ReplaceReferencedValueOperation(nothing, reference, "changed")
        inverse = evaluate_invertible_operation!(editor, operation)
        @test root.left.value == "changed"
        @test inverse isa ReplaceReferencedValueOperation
        evaluate_operation(editor, inverse)
        @test root.left.value == "a"
    end

    @testset "a write on a carried root is inverted against that root" begin
        leaf = _leaf("a")
        editor = _InvEditor(InvBranch(_leaf("x"), _leaf("y"), nothing))
        operation = ReplaceReferencedValueOperation(leaf, "value", "changed")
        inverse = evaluate_invertible_operation!(editor, operation)
        @test leaf.value == "changed"
        evaluate_operation(editor, inverse)
        @test leaf.value == "a"
    end

    @testset "an element overwrite puts back the slot that was there" begin
        list = InvList(Any[_leaf("a"), _leaf("b")], nothing)
        editor = _InvEditor(list)
        reference = Reference(FieldReferenceStep("items"), RangeReferenceStep(1, 2))
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(nothing, reference, _leaf("z")))
        @test _values(list) == ["a", "z"]
        evaluate_operation(editor, inverse)
        @test _values(list) == ["a", "b"]
    end

    # One rule covers insert, delete and replace, because all three are a splice
    # of `[start, stop)` with a vector of items.
    @testset "a splice is undone by the opposite splice" begin
        for (start, stop, items, after) in
                ((1, 1, Any[_leaf("x")],               ["a", "x", "b", "c"]),   # insert
                 (1, 2, Any[],                          ["a", "c"]),            # delete
                 (0, 2, Any[_leaf("x")],                ["x", "c"]),            # replace
                 (0, 3, Any[_leaf("x"), _leaf("y")],    ["x", "y"]))            # replace many
            list = InvList(Any[_leaf("a"), _leaf("b"), _leaf("c")], nothing)
            editor = _InvEditor(list)
            reference = Reference(FieldReferenceStep("items"), RangeReferenceStep(start, stop))
            inverse = evaluate_invertible_operation!(editor,
                ReplaceReferencedValueOperation(nothing, reference, items))
            @test _values(list) == after
            evaluate_operation(editor, inverse)
            @test _values(list) == ["a", "b", "c"]
        end
    end

    @testset "a whole-root swap puts the old root back" begin
        old = InvBranch(_leaf("a"), _leaf("b"), nothing)
        new = InvBranch(_leaf("c"), _leaf("d"), nothing)
        editor = _InvEditor(old)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(nothing, EmptyReference(), new))
        @test editor.document === new
        evaluate_operation(editor, inverse)
        @test editor.document === old
    end

    @testset "flipping a collapsed node again is the way back" begin
        box = InvBox(false, nothing)
        editor = _InvEditor(box)
        inverse = evaluate_invertible_operation!(editor, ToggleCollapseOperation(box))
        @test box.collapsed
        evaluate_operation(editor, inverse)
        @test !box.collapsed
        # A target nobody resolved is no node to flip.
        @test make_inverse_operation(box, ToggleCollapseOperation()) === nothing
    end

    @testset "a selection move is undone by the selection that was there" begin
        root = InvBranch(_leaf("abc"), _leaf("def"), nothing)
        editor = _InvEditor(root)
        first_path = Reference(FieldReferenceStep("left"), FieldReferenceStep("value"),
                               RangeReferenceStep(1, 1))
        replace_selection!(root, first_path)
        second_path = Reference(FieldReferenceStep("right"), FieldReferenceStep("value"),
                                RangeReferenceStep(2, 2))
        inverse = evaluate_invertible_operation!(editor, ReplaceSelectionOperation(second_path))
        @test inverse isa ReplaceSelectionOperation
        evaluate_operation(editor, inverse)
        @test get_reference_steps(strip_reference_types(get_selection(root))) ==
              get_reference_steps(first_path)
    end

    # The selection chain is live: the stored path's steps are mutated in place as
    # the caret moves, so a captured path must be a rebuild and not a borrow.
    @testset "the captured selection is a copy, not the live path" begin
        root = InvBranch(_leaf("abc"), _leaf("def"), nothing)
        replace_selection!(root, Reference(FieldReferenceStep("left"),
                                           FieldReferenceStep("value"),
                                           RangeReferenceStep(1, 1)))
        stored = get_selection(root)
        captured = make_inverse_operation(root, ReplaceSelectionOperation(EmptyReference())).path
        stored_steps = get_reference_steps(strip_reference_types(stored))
        captured_steps = get_reference_steps(strip_reference_types(captured))
        @test captured_steps == stored_steps
        @test captured_steps[end] !== stored_steps[end]
    end

    @testset "a document with no selection answers do-nothing" begin
        root = InvBranch(_leaf("a"), _leaf("b"), nothing)
        @test make_inverse_operation(root, ReplaceSelectionOperation(EmptyReference())) isa
              DoNothingOperation
    end

    @testset "a wrapper's way back is the way back of what it holds" begin
        root = InvBranch(_leaf("a"), _leaf("b"), nothing)
        reference = Reference(FieldReferenceStep("left"), FieldReferenceStep("value"))
        inner = ReplaceReferencedValueOperation(nothing, reference, "changed")
        inverse = make_inverse_operation(root, InvWrapperOperation(inner))
        @test inverse isa ReplaceReferencedValueOperation
        @test inverse.value == "a"
    end

    # The whole reason `evaluate_invertible_operation!` exists: the inverse of the
    # second member depends on what the first member did. Two deletes of the same
    # index are the smallest case that shows it — inverting both up front would
    # put the first element back twice.
    @testset "a compound is inverted while it is applied" begin
        list = InvList(Any[_leaf("a"), _leaf("b"), _leaf("c")], nothing)
        editor = _InvEditor(list)
        delete_second() = ReplaceReferencedValueOperation(nothing,
            Reference(FieldReferenceStep("items"), RangeReferenceStep(1, 2)), Any[])
        inverse = evaluate_invertible_operation!(editor,
            CompoundOperation(Any[delete_second(), delete_second()]))
        @test _values(list) == ["a"]
        @test inverse isa CompoundOperation
        evaluate_operation(editor, inverse)
        @test _values(list) == ["a", "b", "c"]
    end

    @testset "a member with no way back leaves the whole step with none" begin
        root = InvBranch(_leaf("a"), _leaf("b"), nothing)
        editor = _InvEditor(root)
        reference = Reference(FieldReferenceStep("left"), FieldReferenceStep("value"))
        operation = CompoundOperation(Any[
            ReplaceReferencedValueOperation(nothing, reference, "changed"),
            InvOpaqueOperation()])
        @test evaluate_invertible_operation!(editor, operation) === nothing
        # The members that ran stay applied: the document is right, and only the
        # way back is gone.
        @test root.left.value == "changed"
    end

    @testset "get_slot_at answers the value by default" begin
        @test get_slot_at(Any[10, 20, 30], 2) == 20
    end

end
end # test_inversion
