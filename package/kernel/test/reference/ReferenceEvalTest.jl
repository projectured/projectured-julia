"""
`ReferenceModule` — the `@reference` builder and `evaluate_reference` walked
over a test-local `ToyNode` tree. Kernel tests use ONLY toy documents so the
reference interface stands on its own without any concrete engine document.
"""

using Test
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.DocumentModule: @document, Document
# `reroot_reference` is the container readers' path-prepender; the narrowing
# tests below need the untyped nodes it produces, not a hand-built stand-in.
using ProjecturedKernel.OperationModule: reroot_reference

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
            __          => :miss
        end
        @test matched === :hit

        # wildcard fallback fires on non-match
        q = strip_reference_types(@reference ::EA.left::EB)
        matched2 = @reference_case q begin
            right.value => :hit
            __          => :miss
        end
        @test matched2 === :miss
    end

    @testset "a `::T` in a pattern narrows the match" begin
        # The skeleton records no node type anywhere; annotating it against `root`
        # fills every node in — so the pair below is the same shape, once untyped
        # and once knowing what it stands on.
        skeleton  = strip_reference_types(@reference ::EA.left::EB.value::EC)
        annotated = annotate_reference_types(root, skeleton)
        @test annotated.type === EvalBranch

        right(p) = @reference_case p begin
            ::EvalBranch.left.value => :hit
            __                      => :miss
        end
        wrong(p) = @reference_case p begin
            ::EA.left.value => :hit
            __              => :miss
        end
        supertype_pattern(p) = @reference_case p begin
            ::Document.left.value => :hit
            __                    => :miss
        end
        # A narrowed-away arm must not swallow the input: the next arm gets its say.
        two_arms(p) = @reference_case p begin
            ::EA.left.value         => :wrong_arm
            ::EvalBranch.left.value => :right_arm
            __                      => :miss
        end

        @test right(annotated) === :hit
        @test wrong(annotated) === :miss
        @test supertype_pattern(annotated) === :hit
        # No type recorded, nothing to narrow on — the pattern still matches.
        @test wrong(skeleton) === :hit
        @test two_arms(annotated) === :right_arm

        # `above(P)` succeeds when the input runs out INSIDE `P`, so the pattern
        # has to be longer than the path.
        short     = annotate_reference_types(root, strip_reference_types(@reference ::EA.left::EB))
        above_right(p) = @reference_case p begin
            above(::EvalBranch.left.value) => :hit
            __                             => :miss
        end
        above_wrong(p) = @reference_case p begin
            above(::EA.left.value) => :hit
            __                     => :miss
        end
        above_super(p) = @reference_case p begin
            above(::Document.left.value) => :hit
            __                           => :miss
        end
        above_two_arms(p) = @reference_case p begin
            above(::EA.left.value)         => :wrong_arm
            above(::EvalBranch.left.value) => :right_arm
            __                             => :miss
        end

        @test above_right(short) === :hit
        @test above_wrong(short) === :miss
        @test above_super(short) === :hit
        @test above_wrong(strip_reference_types(short)) === :hit
        @test above_two_arms(short) === :right_arm
    end

    @testset "a re-rooted path keeps matching — the June 2026 regression" begin
        # `reroot_reference` prepends nodes with the two-arg `ConcreteReference`,
        # which records no type. Narrowing must stay silent on those, or every
        # container that routes a gesture into a child breaks.
        annotated = annotate_reference_types(root, strip_reference_types(@reference ::EA.left::EB.value::EC))
        rerooted  = reroot_reference(annotated, (FieldReferenceStep("outer"),))
        @test rerooted.type === nothing

        leading(p) = @reference_case p begin
            ::EA.outer.left.value => :hit
            __                    => :miss
        end
        @test leading(rerooted) === :hit

        above_leading(p) = @reference_case p begin
            above(::EA.outer.left.value.deeper) => :hit
            __                                  => :miss
        end
        @test above_leading(rerooted) === :hit

        # Deeper in, the child's own nodes ARE typed, and a pattern naming the
        # wrong type there is narrowed away — that is the tripwire, not a defect.
        mid_wrong(p) = @reference_case p begin
            ::EA.outer::EA.left.value => :hit
            __                        => :miss
        end
        mid_right(p) = @reference_case p begin
            ::EA.outer::EvalBranch.left.value => :hit
            __                                => :miss
        end
        @test mid_wrong(rerooted) === :miss
        @test mid_right(rerooted) === :hit
    end

    @testset "∅::T narrows a whole-element selection" begin
        typed = annotate_reference_types(root, EmptyReference())
        @test typed.type === EvalBranch

        m(p) = @reference_case p begin
            ∅::EvalBranch => :branch
            ∅::EA         => :ea
            ∅             => :untyped
            __            => :miss
        end
        @test m(typed) === :branch
        @test m(EmptyReference()) === :branch   # untyped ∅ is tolerated by the first arm
    end

    @testset "the arm vocabulary" begin
        # One pattern, five forms, over paths that sit above / at / below it —
        # the same table `@reference_rules` is held to, so the two DSLs say the
        # same thing with the same words.
        shallow = Reference(FieldReferenceStep("left"))
        exact = Reference(FieldReferenceStep("left"), FieldReferenceStep("value"))
        deep = Reference(FieldReferenceStep("left"), FieldReferenceStep("value"),
                         FieldReferenceStep("more"))
        elsewhere = Reference(FieldReferenceStep("right"))
        paths = (shallow, exact, deep, elsewhere)

        at_arm(p)          = @reference_case p begin at(left.value) => :yes end
        bare_arm(p)        = @reference_case p begin left.value => :yes end
        below_arm(p)       = @reference_case p begin below(left.value) => :yes end
        at_or_below_arm(p) = @reference_case p begin at_or_below(left.value) => :yes end
        above_arm(p)       = @reference_case p begin above(left.value) => :yes end
        at_or_above_arm(p) = @reference_case p begin at_or_above(left.value) => :yes end

        for (arm, expected) in ((at_arm, [exact]),
                                (bare_arm, [exact]),
                                (below_arm, [deep]),
                                (at_or_below_arm, [exact, deep]),
                                (above_arm, [shallow]),
                                (at_or_above_arm, [shallow, exact]))
            @test [p for p in paths if arm(p) === :yes] == expected
        end

        # `prefix(…)` named `above(…)` while reading like `at_or_below(…)`; it is
        # gone, and the error says which one to write instead.
        @test_throws LoadError @eval @reference_case Reference() begin
            prefix(left.value) => :nope
        end
    end

    @testset "is_reference_prefix" begin
        base = strip_reference_types(@reference ::EA.left::EB)
        deep = strip_reference_types(@reference ::EA.left::EB.value::EC)
        @test is_reference_prefix(base, deep)
        @test !is_reference_prefix(deep, base)
    end

end
end # test_reference_eval
