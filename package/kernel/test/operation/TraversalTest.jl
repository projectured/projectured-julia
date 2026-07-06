"""
`OperationModule` — the open `child_reference_steps` traversal seam. Verifies
the default fieldnames-walk enumerates a document's children and that a
test-local override can name children differently (the seam pressure).
"""

using Test
using ProjecturedKernel
using ProjecturedKernel.OperationModule: child_reference_steps
using ProjecturedKernel.DocumentModule: @document, Document
using ProjecturedKernel.ReferenceModule: Reference, FieldReference, RangeReference

@document struct ToyLeaf
    value::Int
    selection::Reference
end

@document struct ToyBranch
    left::ToyLeaf
    right::ToyLeaf
    selection::Reference
end

@document struct ToyList
    items::Vector{ToyLeaf}
    selection::Reference
end

# The seam pressure — a test-local document type registers its own
# `child_reference_steps` method so its children are addressed by index rather
# than by field name.
ProjecturedKernel.OperationModule.child_reference_steps(node::ToyList) =
    [(RangeReference(i - 1, i), node.items[i]) for i in 1:length(node.items)]

@testset "Traversal" begin

    @testset "default fieldnames-walk enumerates document fields" begin
        root = ToyBranch(ToyLeaf(1, nothing), ToyLeaf(2, nothing), nothing)
        steps = child_reference_steps(root)
        @test length(steps) == 2
        # order matches struct field order, `selection` is skipped
        @test steps[1][1] == FieldReference("left")
        @test steps[1][2] === root.left
        @test steps[2][1] == FieldReference("right")
        @test steps[2][2] === root.right
    end

    @testset "test-local override names children differently" begin
        list = ToyList([ToyLeaf(10, nothing), ToyLeaf(20, nothing)], nothing)
        steps = child_reference_steps(list)
        @test length(steps) == 2
        @test steps[1][1] == RangeReference(0, 1)
        @test steps[2][1] == RangeReference(1, 2)
    end

end
