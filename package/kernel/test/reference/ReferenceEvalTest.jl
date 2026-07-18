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
end

@document struct EvalBranch
    left::EvalLeaf
    right::EvalLeaf
end

struct EA end
struct EB end
struct EC end

function test_reference_eval()
@testset "ReferenceEval" begin

    root = EvalBranch(EvalLeaf(10, nothing), EvalLeaf(20, nothing), nothing)

    @testset "evaluate_reference walks fields" begin
        # empty path resolves to the root document
        @test evaluate_reference(root, EmptyReference()) === root
        # simple field navigation
        @test evaluate_reference(root, strip_reference_types(@reference ::EA.left::EB)) === root.left
        @test evaluate_reference(root, strip_reference_types(@reference ::EA.right::EB.value::EC)) == 20
    end

    @testset "@reference_case destructures paths" begin
        # exact-path match wins
        p = strip_reference_types(@reference ::EA.right::EB.value::EC)
        matched = @reference_case p begin
            right.value => :hit
            _           => :miss
        end
        @test matched === :hit

        # wildcard fallback fires on non-match
        q = strip_reference_types(@reference ::EA.left::EB)
        matched2 = @reference_case q begin
            right.value => :hit
            _           => :miss
        end
        @test matched2 === :miss
    end

    @testset "prefix + suffix predicates" begin
        base = strip_reference_types(@reference ::EA.left::EB)
        deep = strip_reference_types(@reference ::EA.left::EB.value::EC)
        @test is_reference_prefix(base, deep)
        @test !is_reference_prefix(deep, base)
    end

end
end # test_reference_eval
