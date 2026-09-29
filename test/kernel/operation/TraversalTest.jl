"""
`OperationModule` — the open `child_reference_steps` traversal seam. Verifies
the default fieldnames-walk enumerates a document's children and that a
test-local override can name children differently (the seam pressure).

It also verifies the "next hole" walk of `SelectNextInsertionOperation`: the
selection goes to the next document in pre-order for which the predicate holds,
with the cursor suffix, and stays at the last one.
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.OperationModule: child_reference_steps, evaluate_operation,
    SelectNextInsertionOperation
using ProjecturedKernel.DocumentModule: @document, Document
using ProjecturedKernel.ReferenceModule: Reference, FieldReferenceStep,
    RangeReferenceStep, get_reference_steps, strip_reference_types
using ProjecturedKernel.SelectionModule: replace_selection!, get_selection

@document struct ToyLeaf
    value::Int
end

@document struct ToyBranch
    left::ToyLeaf
    right::ToyLeaf
end

@document struct ToyList
    items::Vector{ToyLeaf}
end

# The seam pressure — a test-local document type registers its own
# `child_reference_steps` method so its children are addressed by index rather
# than by field name.
ProjecturedKernel.OperationModule.child_reference_steps(node::ToyList) =
    [(RangeReferenceStep(i - 1, i), node.items[i]) for i in 1:length(node.items)]

# A test-local form with three holes: `name`, then `body.first` and
# `body.second` in pre-order.
@document struct ToyHole
    text::String
end

@document struct ToyHolePair
    first::ToyHole
    second::ToyHole
end

@document struct ToyHoleForm
    name::ToyHole
    body::ToyHolePair
end

_make_toy_hole_form() =
    ToyHoleForm(ToyHole("", nothing),
                ToyHolePair(ToyHole("", nothing), ToyHole("", nothing), nothing), nothing)

# The steps of the selection of `root`, with no type checkpoints.
_get_toy_selection_steps(root) =
    get_reference_steps(strip_reference_types(get_selection(root)))

# The steps of a caret at the start of the text of the hole at `names`.
_get_toy_caret_steps(names...) = [map(FieldReferenceStep, names)...,
                                  FieldReferenceStep("text"), RangeReferenceStep(0, 0)]

function test_traversal()
@testset "Traversal" begin

    @testset "default fieldnames-walk enumerates document fields" begin
        root = ToyBranch(ToyLeaf(1, nothing), ToyLeaf(2, nothing), nothing)
        steps = child_reference_steps(root)
        @test length(steps) == 2
        # order matches struct field order, `selection` is skipped
        @test steps[1][1] == FieldReferenceStep("left")
        @test steps[1][2] === root.left
        @test steps[2][1] == FieldReferenceStep("right")
        @test steps[2][2] === root.right
    end

    @testset "test-local override names children differently" begin
        list = ToyList([ToyLeaf(10, nothing), ToyLeaf(20, nothing)], nothing)
        steps = child_reference_steps(list)
        @test length(steps) == 2
        @test steps[1][1] == RangeReferenceStep(0, 1)
        @test steps[2][1] == RangeReferenceStep(1, 2)
    end

    @testset "the next hole is the next one in pre-order, with the cursor suffix" begin
        form = _make_toy_hole_form()
        editor = (document = form,)
        caret = Reference(FieldReferenceStep("text"), RangeReferenceStep(0, 0))
        next_hole = SelectNextInsertionOperation(node -> node isa ToyHole, caret)
        replace_selection!(form, Reference(_get_toy_caret_steps("name")...))
        evaluate_operation(editor, next_hole)
        @test _get_toy_selection_steps(form) == _get_toy_caret_steps("body", "first")
        # The hole that the selection leaves keeps no selection of its own.
        @test get_selection(form.name) === nothing
        evaluate_operation(editor, next_hole)
        @test _get_toy_selection_steps(form) == _get_toy_caret_steps("body", "second")
        # The last hole has no next one, so the selection stays.
        evaluate_operation(editor, next_hole)
        @test _get_toy_selection_steps(form) == _get_toy_caret_steps("body", "second")
    end

    @testset "with no selection the walk starts at the root" begin
        form = _make_toy_hole_form()
        evaluate_operation((document = form,),
                           SelectNextInsertionOperation(node -> node isa ToyHole))
        @test _get_toy_selection_steps(form) == [FieldReferenceStep("name")]
    end

    @testset "a root that is not a document leaves the walk nothing to do" begin
        @test evaluate_operation((document = "text",),
                                 SelectNextInsertionOperation(_ -> true)) === nothing
    end

end
end # test_traversal
