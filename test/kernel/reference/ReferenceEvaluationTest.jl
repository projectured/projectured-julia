"""
`ReferenceModule` — the `@reference` builder, `evaluate_reference` and the path
algebra, walked over a test-local tree of `EvaluationBranch`, `EvaluationLeaf` and
`EvaluationList`. Kernel tests use ONLY toy documents so the reference interface
stands on its own without any concrete engine document.
"""

using Test
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.DocumentModule: @document, Document
# `reroot_reference` is the container readers' path-prepender; the narrowing
# tests below need the untyped nodes it produces, not a hand-built stand-in.
using ProjecturedKernel.OperationModule: reroot_reference
using ProjecturedKernel.ProjectionModule: ProjectionReferenceStep

@document struct EvaluationLeaf
    value::Int
end

@document struct EvaluationBranch
    left::EvaluationLeaf
    right::EvaluationLeaf
end

@document struct EvaluationList
    items::Vector{Any} = Any[]
end

struct EA end
struct EB end
struct EC end

# A step type that defines no `==` of its own.
mutable struct EvaluationToyStep <: ReferenceStep end
ReferenceModule.get_reference_step_kind(::EvaluationToyStep) = :structural
ReferenceModule.evaluate_reference_step(::EvaluationToyStep, document) = document

# A step type with no method of `evaluate_reference_step`, and one whose
# evaluation is stopped.
struct EvaluationMethodlessStep <: ReferenceStep end
ReferenceModule.get_reference_step_kind(::EvaluationMethodlessStep) = :structural
struct EvaluationStoppedStep <: ReferenceStep end
ReferenceModule.get_reference_step_kind(::EvaluationStoppedStep) = :structural
ReferenceModule.evaluate_reference_step(::EvaluationStoppedStep, document) =
    throw(InterruptException())

function test_reference_evaluation()
@testset "ReferenceEvaluation" begin

    root = EvaluationBranch(EvaluationLeaf(10, nothing), EvaluationLeaf(20, nothing), nothing)

    @testset "a walker answers its default only for a path that does not resolve" begin
        stale = Reference(FieldReferenceStep("missing"))
        @test try_evaluate_reference(root, stale, :none) === :none
        @test get_valid_reference_prefix(root, stale) isa EmptyReference
        @test annotate_reference_types(root, stale) isa ConcreteReference

        methodless = Reference(EvaluationMethodlessStep())
        @test_throws MethodError try_evaluate_reference(root, methodless, :none)
        @test_throws MethodError get_valid_reference_prefix(root, methodless)
        @test_throws MethodError annotate_reference_types(root, methodless)

        stopped = Reference(EvaluationStoppedStep())
        @test_throws InterruptException try_evaluate_reference(root, stopped, :none)
        @test_throws InterruptException get_valid_reference_prefix(root, stopped)
        @test_throws InterruptException annotate_reference_types(root, stopped)
    end

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

    @testset "@reference_case evaluates its input once" begin
        reads = Ref(0)
        read_input() = (reads[] += 1; Reference(FieldReferenceStep("right")))
        matched = @reference_case read_input() begin
            left.value  => :a
            left        => :b
            right.value => :c
            below(left) => :d
            right       => :e
        end
        @test matched === :e
        @test reads[] == 1
    end

    @testset "a type step takes a bare type name" begin
        message = "a type step takes a bare type name"
        @test_throws message parse_reference_path(:(::Mod.T))
        @test_throws message parse_reference_path(:(left::Mod.T))
        @test_throws message parse_reference_path(:(left::Mod.T{1}))
        # A field after a type stays a field.
        @test length(parse_reference_path(:(left::EB.value))) == 3
        @test length(parse_reference_path(:(::EB.value{0:1}))) == 3
    end

    @testset "a `::T` in a pattern narrows the match" begin
        # The skeleton records no node type anywhere; annotating it against `root`
        # fills every node in — so the pair below is the same shape, once untyped
        # and once knowing what it stands on.
        skeleton  = strip_reference_types(@reference ::EA.left::EB.value::EC)
        annotated = annotate_reference_types(root, skeleton)
        @test annotated.type === EvaluationBranch

        right(p) = @reference_case p begin
            ::EvaluationBranch.left.value => :hit
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
            ::EvaluationBranch.left.value => :right_arm
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
            above(::EvaluationBranch.left.value) => :hit
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
            above(::EvaluationBranch.left.value) => :right_arm
            __                             => :miss
        end

        @test above_right(short) === :hit
        @test above_wrong(short) === :miss
        @test above_super(short) === :hit
        @test above_wrong(strip_reference_types(short)) === :hit
        @test above_two_arms(short) === :right_arm
    end

    @testset "a re-rooted path keeps matching" begin
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
            ::EA.outer::EvaluationBranch.left.value => :hit
            __                                => :miss
        end
        @test mid_wrong(rerooted) === :miss
        @test mid_right(rerooted) === :hit
    end

    @testset "∅::T narrows a whole-element selection" begin
        typed = annotate_reference_types(root, EmptyReference())
        @test typed.type === EvaluationBranch

        m(p) = @reference_case p begin
            ∅::EvaluationBranch => :branch
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
        within_arm(p) = @reference_case p begin within(left.value) => :yes end
        above_arm(p)       = @reference_case p begin above(left.value) => :yes end
        toward_arm(p) = @reference_case p begin toward(left.value) => :yes end

        for (arm, expected) in ((at_arm, [exact]),
                                (bare_arm, [exact]),
                                (below_arm, [deep]),
                                (within_arm, [exact, deep]),
                                (above_arm, [shallow]),
                                (toward_arm, [shallow, exact]))
            @test [p for p in paths if arm(p) === :yes] == expected
        end

        # `prefix(…)` named `above(…)` while reading like `within(…)`; it is
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

    @testset "an element step on a String counts characters" begin
        text = "héllo"                  # 'é' takes two bytes
        third = Reference(ElementReferenceStep(3))
        sixth = Reference(ElementReferenceStep(6))
        middle = Reference(RangeReferenceStep(2, 4))
        @test evaluate_reference(text, third) == 'l'
        @test try_evaluate_reference(text, sixth) === nothing
        @test !is_valid_reference(text, sixth)
        @test get_valid_reference_prefix(text, middle) == middle
        # A caret between characters still answers its position.
        @test evaluate_reference(text, Reference(PositionReferenceStep(2))) == Position(2)
    end

    @testset "a reference names a schema, not the layout it was built on" begin
        # The simulator mutates the native tree while the editor navigates the cell
        # shadow. A path built on one has to be the path built on the other, or a
        # selection cannot cross between them.
        # `MEvaluationBranch.left` is typed to one schema, so it holds a cell leaf,
        # not a native one. That is the limit of a schema-typed field; a field typed
        # `Document` takes either layout. The node under test here is the root.
        native = MEvaluationBranch(root.left, root.right, nothing)
        @test get_reference_node_type(native) === get_reference_node_type(root)
        @test get_reference_node_type(native) === EvaluationBranch

        skeleton = strip_reference_types(@reference ::EA.left::EB)
        @test annotate_reference_types(native, skeleton) ==
              annotate_reference_types(root, skeleton)

        # The token is still the bare name a pattern is written with, so a path
        # annotated on the native tree matches and evaluates on the cell tree.
        annotated = annotate_reference_types(native, skeleton)
        @test annotated.type === EvaluationBranch
        @test evaluate_reference(root, strip_reference_types(annotated)) === root.left
    end

    @testset "copy_reference copies a range step in its own layout" begin
        caret = MPositionReferenceStep(2)
        path = Reference(MFieldReferenceStep("items"), caret)
        copied = get_reference_head(get_reference_tail(copy_reference(path)))
        @test copied isa MRangeReferenceStep
        @test copied == caret
        @test copied !== caret
        reactive = PositionReferenceStep(2)
        copied = get_reference_head(copy_reference(Reference(reactive)))
        @test copied isa RangeReferenceStep
        @test copied == reactive
        @test copied !== reactive
    end

    @testset "get_valid_reference_prefix keeps the part of a path that resolves" begin
        typed = annotate_reference_types(root, Reference(FieldReferenceStep("left"),
                                                         FieldReferenceStep("value")))
        @test get_valid_reference_prefix(root, typed) == typed
        @test is_valid_reference(root, typed)

        missing_field = Reference(FieldReferenceStep("left"), FieldReferenceStep("none"))
        @test get_valid_reference_prefix(root, missing_field) ==
              Reference(FieldReferenceStep("left"))
        @test !is_valid_reference(root, missing_field)

        list = EvaluationList(items = Any[EvaluationLeaf(1, nothing)])
        past_end = Reference(FieldReferenceStep("items"), ElementReferenceStep(3))
        @test get_valid_reference_prefix(list, past_end) ==
              Reference(FieldReferenceStep("items"))
        @test !is_valid_reference(list, past_end)
        first_value = Reference(FieldReferenceStep("items"), ElementReferenceStep(1),
                                FieldReferenceStep("value"))
        @test is_valid_reference(list, first_value)
    end

    @testset "try_evaluate_reference answers a default where a path can not resolve" begin
        @test try_evaluate_reference(root, Reference(FieldReferenceStep("left"))) ===
              root.left
        gone = Reference(FieldReferenceStep("none"))
        @test try_evaluate_reference(root, gone) === nothing
        @test try_evaluate_reference(root, gone, :none) === :none
        # No selection resolves to no node.
        @test try_evaluate_reference(root, nothing) === nothing
        @test try_evaluate_reference(root, nothing, :none) === :none
    end

    @testset "a copy keeps the numbers of a range step that is written later" begin
        path = Reference(FieldReferenceStep("items"), PositionReferenceStep(1))
        copied = copy_reference(path)
        range = get_reference_head(get_reference_tail(path))
        range.start = 3
        range.stop = 3
        @test get_reference_head(get_reference_tail(copied)) == PositionReferenceStep(1)
        @test get_reference_head(copied) == FieldReferenceStep("items")
        # Anything that is not a path answers itself.
        @test copy_reference(nothing) === nothing
        @test copy_reference(EmptyReference(EA)) == EmptyReference(EA)
    end

    @testset "extend_reference appends steps and keeps the node types" begin
        @test extend_reference(EmptyReference(), FieldReferenceStep("left"),
                               FieldReferenceStep("value")) ==
              Reference(FieldReferenceStep("left"), FieldReferenceStep("value"))
        base = annotate_reference_types(root, Reference(FieldReferenceStep("left")))
        @test extend_reference(base) == base
        extended = extend_reference(base, FieldReferenceStep("value"))
        @test extended.type === EvaluationBranch
        # The first new node stands on the node where `base` ends.
        @test get_reference_tail(extended).type === EvaluationLeaf
        @test get_reference_tail(get_reference_tail(extended)).type === nothing
        @test evaluate_reference(root, extended) == 10
    end

    @testset "concat_references joins two paths and keeps the types of both" begin
        @test concat_references(Reference(FieldReferenceStep("left")),
                                Reference(FieldReferenceStep("value"))) ==
              Reference(FieldReferenceStep("left"), FieldReferenceStep("value"))
        # At the junction the node takes the type of the second path, or else the
        # terminal type of the first.
        typed_prefix = annotate_reference_types(root,
                                                Reference(FieldReferenceStep("left")))
        joined = concat_references(typed_prefix, Reference(FieldReferenceStep("value")))
        @test get_reference_tail(joined).type === EvaluationLeaf
        typed_suffix = annotate_reference_types(root.left,
                                                Reference(FieldReferenceStep("value")))
        joined = concat_references(Reference(FieldReferenceStep("left")), typed_suffix)
        @test joined.type === nothing
        @test get_reference_tail(joined).type === EvaluationLeaf
        @test evaluate_reference(root, joined) == 10
        @test concat_references(EmptyReference(EA), EmptyReference()) ==
              EmptyReference(EA)
        @test concat_references(EmptyReference(EA), EmptyReference(EB)) ==
              EmptyReference(EB)
    end

    @testset "search_references answers a typed path to each place of a match" begin
        found = search_references(root, x -> x isa EvaluationLeaf && x.value == 20)
        @test length(found) == 1
        @test found[1].type === EvaluationBranch
        @test strip_reference_types(found[1]) == Reference(FieldReferenceStep("right"))
        @test evaluate_reference(root, found[1]) === root.right
        # A match on a value folds to the document that holds it, unless `raw`.
        @test strip_reference_types.(search_references(root, x -> x == 20)) ==
              [Reference(FieldReferenceStep("right"))]
        @test strip_reference_types.(search_references(root, x -> x == 20; raw = true)) ==
              [Reference(FieldReferenceStep("right"), FieldReferenceStep("value"))]
        @test strip_reference_types.(search_references(root, "20")) ==
              [Reference(FieldReferenceStep("right"))]
        # One document in two places is two places.
        shared = EvaluationLeaf(5, nothing)
        pair = EvaluationBranch(shared, shared, nothing)
        @test Set(strip_reference_types.(search_references(pair, x -> x === shared))) ==
              Set([Reference(FieldReferenceStep("left")),
                   Reference(FieldReferenceStep("right"))])
    end

    @testset "a step type with no == of its own equals itself" begin
        step = EvaluationToyStep()
        @test step == step
        @test step != EvaluationToyStep()
        @test is_valid_reference(root, Reference(step))
    end

    @testset "a projection step hashes as it compares" begin
        projection = Ref(0)
        first_step = ProjectionReferenceStep(projection,
                                             Reference(FieldReferenceStep("x")))
        second_step = ProjectionReferenceStep(projection,
                                              Reference(FieldReferenceStep("x")))
        @test first_step == second_step
        @test hash(first_step) == hash(second_step)
        @test length(Set([Reference(first_step), Reference(second_step)])) == 1
    end

end
end # test_reference_evaluation
