"""
`OperationModule` — the way back. Verifies `make_inverse_operation` for every
operation this layer owns, the order `evaluate_invertible_operation!` keeps for a
container, and the `get_slot_at` seam. Each case is one round trip: apply, then
apply the inverse, and the document is what it was.

A **test-local** operation with no method proves the default is `nothing`, and a
test-local wrapper proves a wrapper's way back is the way back of what it holds.
It also verifies the splice helpers that the text edits use. The lists are a
test-local collection that keeps each element in a cell of its own, so a splice
must give each item as it is and let the collection wrap it. A second test-local
collection writes a value into the slot cell that is there, so the way back of an
overwrite must hold the old value and not the slot. It replaces the slot for a cell,
so the way back of a cell must hold the old slot.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.CellModule: AbstractCell, Cell, MutableCell, unwrap_cell
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

# A test-local collection of documents: it keeps each element in a `MutableCell`
# of its own. It wraps a value that it gets, and it keeps a cell that it gets, so
# an element that a way back puts back is the cell that was taken out.
struct InvCells
    cells::Vector{Any}
end
_wrap_inv_cell(value) = value isa AbstractCell ? value : MutableCell{Any}(value)
Base.length(list::InvCells) = length(list.cells)
Base.getindex(list::InvCells, index::Integer) = list.cells[index][]
Base.setindex!(list::InvCells, value, index::Integer) =
    (list.cells[index] = _wrap_inv_cell(value); value)
Base.insert!(list::InvCells, index::Integer, value) =
    (insert!(list.cells, index, _wrap_inv_cell(value)); list)
Base.deleteat!(list::InvCells, index) = (deleteat!(list.cells, index); list)
ProjecturedKernel.DocumentModule.is_element_collection(::InvCells) = true
ProjecturedKernel.OperationModule.get_slot_at(list::InvCells, index::Integer) =
    list.cells[index]

# A test-local collection that writes a value into the slot cell that is there,
# and replaces the slot only for a cell, as the reactive `CellVector` does.
struct InvSlots
    cells::Vector{Any}
end
Base.length(list::InvSlots) = length(list.cells)
Base.getindex(list::InvSlots, index::Integer) = list.cells[index][]
Base.setindex!(list::InvSlots, value, index::Integer) =
    (list.cells[index][] = value; value)
Base.setindex!(list::InvSlots, cell::AbstractCell, index::Integer) =
    (list.cells[index] = cell; cell)
ProjecturedKernel.OperationModule.get_slot_at(list::InvSlots, index::Integer) =
    list.cells[index]

@document struct InvList
    items::InvCells
end

@document struct InvBox
    collapsed::Bool
end

@document struct InvNumber
    value::Union{Nothing, Real}
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
_inv_list(texts...) = InvList(InvCells(Any[MutableCell{Any}(_leaf(t)) for t in texts]),
                              nothing)
_values(list) = [unwrap_cell(cell).value for cell in list.items.cells]

function test_inversion()
@testset "Inversion" begin

    @testset "an operation nobody taught to invert has no way back" begin
        @test make_inverse_operation(nothing, InvOpaqueOperation()) === nothing
        @test make_inverse_operation(nothing, nothing) === nothing
    end

    @testset "an operation that changes no document is undone by doing nothing" begin
        @test make_inverse_operation(nothing, DoNothingOperation()) isa DoNothingOperation
        @test make_inverse_operation(nothing, QuitEditorOperation()) isa DoNothingOperation
        @test make_inverse_operation(nothing, InvalidateProjectionOperation()) isa DoNothingOperation
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

    @testset "an element overwrite puts back the value that was there" begin
        list = _inv_list("a", "b")
        editor = _InvEditor(list)
        reference = Reference(FieldReferenceStep("items"), RangeReferenceStep(1, 2))
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(nothing, reference, _leaf("z")))
        @test _values(list) == ["a", "z"]
        evaluate_operation(editor, inverse)
        @test _values(list) == ["a", "b"]
    end

    # A reactive collection writes one value into the slot cell that is there, as
    # the reactive `CellVector` does. The way back must hold the old value, because
    # the slot cell holds the new value once the write runs.
    @testset "an overwrite in place is undone by the old value" begin
        slots = InvSlots(Any[MutableCell{Any}("a"), MutableCell{Any}("b")])
        editor = _InvEditor(nothing)
        slot = slots.cells[2]
        reference = Reference(RangeReferenceStep(1, 2))
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(slots, reference, "z"))
        @test [slots[1], slots[2]] == ["a", "z"]
        @test inverse.value == "b"
        evaluate_operation(editor, inverse)
        @test [slots[1], slots[2]] == ["a", "b"]
        @test slots.cells[2] === slot
        # A cell replaces the slot, so the way back puts the old slot back and
        # leaves the new cell as it is.
        c = Cell("z")
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(slots, reference, c))
        @test slots.cells[2] === c
        evaluate_operation(editor, inverse)
        @test slots.cells[2] === slot
        @test [slots[1], slots[2]] == ["a", "b"]
        @test c[] == "z"
    end

    # A step of the plain layout (`M…`) writes and inverts as the cell layout does.
    @testset "a write through a plain step has a way back" begin
        leaf = _leaf("a")
        editor = _InvEditor(nothing)
        inverse = evaluate_invertible_operation!(editor,
            ReplaceReferencedValueOperation(leaf, Reference(MFieldReferenceStep("value")),
                                            "b"))
        @test leaf.value == "b"
        evaluate_operation(editor, inverse)
        @test leaf.value == "a"

        list = _inv_list("a", "b")
        editor = _InvEditor(list)
        reference = Reference(MFieldReferenceStep("items"), MRangeReferenceStep(1, 2))
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
            list = _inv_list("a", "b", "c")
            editor = _InvEditor(list)
            reference = Reference(FieldReferenceStep("items"), RangeReferenceStep(start, stop))
            inverse = evaluate_invertible_operation!(editor,
                ReplaceReferencedValueOperation(nothing, reference, items))
            @test _values(list) == after
            evaluate_operation(editor, inverse)
            @test _values(list) == ["a", "b", "c"]
        end
    end

    # The collection, not the splice, decides the form in which an element is
    # stored: here a `MutableCell` of its own around the value.
    @testset "a splice gives each item to the collection as it is" begin
        list = _inv_list("a")
        reference = Reference(FieldReferenceStep("items"), RangeReferenceStep(1, 1))
        evaluate_operation(_InvEditor(list),
            ReplaceReferencedValueOperation(nothing, reference, Any[_leaf("b")]))
        @test _values(list) == ["a", "b"]
        @test all(cell -> cell isa MutableCell, list.items.cells)
        @test !any(cell -> unwrap_cell(cell) isa AbstractCell, list.items.cells)
    end

    @testset "a write refuses a key of a dictionary and a range of many elements" begin
        table = Dict{String, Any}("a" => 1)
        @test_throws "writes no key" evaluate_operation(_InvEditor(nothing),
            ReplaceReferencedValueOperation(table, "a", 2))
        @test table["a"] == 1

        list = _inv_list("a", "b", "c")
        reference = Reference(FieldReferenceStep("items"), RangeReferenceStep(0, 2))
        @test_throws "more than one element" evaluate_operation(_InvEditor(list),
            ReplaceReferencedValueOperation(nothing, reference, _leaf("z")))
        @test _values(list) == ["a", "b", "c"]
    end

    @testset "a compound of one operation holds that operation" begin
        compound = CompoundOperation(DoNothingOperation())
        @test compound.operations == Any[DoNothingOperation()]
    end

    # Each text edit goes through this one splice, between 0-based boundaries, so a
    # character of more than one byte stays whole.
    @testset "splice_string replaces the characters between two boundaries" begin
        @test splice_string("hello", 1, 3, "EY") == "hEYlo"
        @test splice_string("abc", 1, 1, "x") == "axbc"
        @test splice_string("aéb", 1, 2, "x") == "axb"
        @test splice_string("abc", -1, 1, "x") == "xbc"
        @test splice_string("abc", 2, 10, "x") == "abx"
    end

    @testset "splice_number splices the text and reads the number back" begin
        @test splice_number("4", 1, 1, "2") === 42
        @test splice_number("4", 1, 1, ".5") === 4.5
        @test splice_number("1", 1, 1, "e3") === 1000.0
        @test splice_number("4", 0, 1, "") === nothing
        @test splice_number("4", 1, 1, "x") === nothing
    end

    @testset "splice_value! writes the splice of the value that the field holds" begin
        leaf = _leaf("abc")
        splice_value!(leaf, :value, leaf.value, 1, 2, "X")
        @test leaf.value == "aXc"
        splice_value!(leaf, :value, nothing, 0, 0, "new")
        @test leaf.value == "new"
        number = InvNumber(4, nothing)
        splice_value!(number, :value, number.value, 1, 1, "2")
        @test number.value === 42
    end

    # An entry outlives the moment it was made, and the document may move in the
    # tree before it is applied. An inverse therefore names the OBJECT it writes
    # into rather than a path from the editor's root.
    @testset "an inverse carries the object it writes into" begin
        root = InvBranch(_leaf("a"), _leaf("b"), nothing)
        reference = Reference(FieldReferenceStep("left"), FieldReferenceStep("value"))
        inverse = make_inverse_operation(root,
            ReplaceReferencedValueOperation(nothing, reference, "changed"))
        @test inverse.document === root.left
        # So it applies against an editor that has never seen this document.
        evaluate_operation(_InvEditor(InvBranch(_leaf("p"), _leaf("q"), nothing)), inverse)
        @test root.left.value == "a"

        list = _inv_list("a", "b")
        splice = make_inverse_operation(list,
            ReplaceReferencedValueOperation(nothing,
                Reference(FieldReferenceStep("items"), RangeReferenceStep(0, 1)), Any[]))
        @test splice.document === list.items
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
        list = _inv_list("a", "b", "c")
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
