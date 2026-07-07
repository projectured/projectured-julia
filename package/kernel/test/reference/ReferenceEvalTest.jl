"""
`ReferenceModule` — the `@reference` builder and `evaluate_reference` walked
over a test-local `ToyNode` tree. Kernel tests use ONLY toy documents so the
reference interface stands on its own without any concrete engine document.
"""

using Test
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.DocumentModule: @document, Document

@document struct EvalLeaf
    value::Int
    selection::Reference
end

@document struct EvalBranch
    left::EvalLeaf
    right::EvalLeaf
    selection::Reference
end

function test_reference_eval()
@testset "ReferenceEval" begin

    root = EvalBranch(EvalLeaf(10, nothing), EvalLeaf(20, nothing), nothing)

    @testset "evaluate_reference walks fields" begin
        # empty path resolves to the root document
        @test evaluate_reference(root, EmptyReferencePath()) === root
        # simple field navigation
        @test evaluate_reference(root, @reference left) === root.left
        @test evaluate_reference(root, @reference right.value) == 20
    end

    @testset "@reference_case destructures paths" begin
        # exact-path match wins
        p = @reference right.value
        matched = @reference_case p begin
            right.value => :hit
            _           => :miss
        end
        @test matched === :hit

        # wildcard fallback fires on non-match
        q = @reference left
        matched2 = @reference_case q begin
            right.value => :hit
            _           => :miss
        end
        @test matched2 === :miss
    end

    @testset "prefix + suffix predicates" begin
        base = @reference left
        deep = @reference left.value
        @test is_prefix_of(base, deep)
        @test !is_prefix_of(deep, base)
    end

end
end # test_reference_eval
