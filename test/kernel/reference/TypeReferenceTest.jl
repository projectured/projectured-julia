"""
`ReferenceModule` — the node types of a path in the folded form, over test-local
documents. A `TypeReferenceStep` is the token that `@reference` writes for a
`::T`, and `fold_reference_types` folds it into the `type` of a path node. A path
that is stored, walked or matched records its types on its nodes, so
`annotate_reference_types` fills them in against a document, `strip_reference_types`
takes them out, and `get_valid_reference_prefix` cuts a path where a type no longer
holds.
"""

using Test
using ProjecturedKernel.DocumentModule: @document
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.SelectionModule: set_selection!, clear_selection!

@document struct CheckpointLeaf
    text::String = ""
end

@document struct CheckpointOther
    value::Int = 0
end

@document struct CheckpointList
    items::Vector{Any} = Any[]
end

@document struct CheckpointPair
    left::Any = nothing
    right::Any = nothing
end

function test_type_reference()
@testset "TypeReference" begin

    leaf = CheckpointLeaf(text = "x")
    list = CheckpointList(items = Any[leaf, CheckpointOther(value = 1)])
    plain = Reference(FieldReferenceStep("items"), ElementReferenceStep(1))

    @testset "a token folds into the node that it types" begin
        # A token at the end types the terminal node, which evaluates to the
        # node itself while the type holds.
        terminal = fold_reference_types(ConcreteReference(
            TypeReferenceStep(CheckpointLeaf), EmptyReference()))
        @test terminal isa EmptyReference
        @test terminal.type === CheckpointLeaf
        @test evaluate_reference(leaf, terminal) === leaf
        @test_throws ReferenceTypeMismatchException evaluate_reference(list, terminal)

        # A token in the middle types the node of the next step.
        middle = fold_reference_types(ConcreteReference(
            TypeReferenceStep(CheckpointList),
            ConcreteReference(FieldReferenceStep("items"),
                              ConcreteReference(ElementReferenceStep(1),
                                                EmptyReference()))))
        @test middle.type === CheckpointList
        @test get_reference_head(middle) == FieldReferenceStep("items")
        @test evaluate_reference(list, middle) === leaf
        # A folded node keeps its type, and a value that is no path answers itself.
        @test fold_reference_types(middle) == middle
        @test fold_reference_types(nothing) === nothing
    end

    @testset "a token left in a path has no reading" begin
        unfolded = ConcreteReference(TypeReferenceStep(CheckpointLeaf), EmptyReference())
        @test TypeReferenceStep(CheckpointLeaf) isa ReferenceStep
        @test_throws MethodError evaluate_reference(leaf, unfolded)
        # A path that still holds the token was never folded: a fault of the program,
        # which no walker turns into its default.
        @test_throws MethodError try_evaluate_reference(leaf, unfolded, :none)
        @test_throws MethodError get_valid_reference_prefix(leaf, unfolded)
        @test_throws MethodError annotate_reference_types(leaf, unfolded)
    end

    @testset "annotate and strip are inverse" begin
        annotated = annotate_reference_types(list, plain)
        @test annotated isa ConcreteReference
        # The head is the navigation step, and the type is a field of the node.
        @test get_reference_head(annotated) == FieldReferenceStep("items")
        @test annotated.type === CheckpointList
        @test get_reference_tail(get_reference_tail(annotated)).type === CheckpointLeaf
        @test evaluate_reference(list, annotated) === leaf
        @test strip_reference_types(annotated) == plain
        @test !is_reference_equal(annotated, plain)
        @test is_valid_reference(list, annotated)
        @test is_fully_typed_reference(annotated)
        @test !is_fully_typed_reference(plain)
    end

    @testset "a type that no longer holds cuts the path there" begin
        annotated = annotate_reference_types(list, plain)
        changed = CheckpointList(items = Any[CheckpointOther(value = 9)])
        @test !is_valid_reference(changed, annotated)
        prefix = get_valid_reference_prefix(changed, annotated)
        @test prefix != annotated
        @test strip_reference_types(prefix) == plain
        @test evaluate_reference(changed, prefix) === changed.items[1]
        # A step that can not be followed drops the rest of the path.
        past_end = Reference(FieldReferenceStep("items"), ElementReferenceStep(5))
        @test get_valid_reference_prefix(list, past_end) ==
              Reference(FieldReferenceStep("items"))
    end

    @testset "a caret records the type of the text and ends at a Position" begin
        caret = annotate_reference_types("hello", Reference(PositionReferenceStep(3)))
        @test caret.type === String
        @test is_position_reference_step(get_reference_head(caret))
        @test get_reference_tail(caret) == EmptyReference(Position)
        @test strip_reference_types(caret) == Reference(PositionReferenceStep(3))
        # An element step descends, so its terminal records the element.
        element = annotate_reference_types(list, plain)
        @test get_reference_tail(get_reference_tail(element)) ==
              EmptyReference(CheckpointLeaf)
        whole = annotate_reference_types(list, EmptyReference())
        @test whole == EmptyReference(CheckpointList)
    end

    @testset "a pattern matches a typed path as it matches the plain one" begin
        annotated = annotate_reference_types(list, plain)
        item_case(path) = @reference_case path begin
            items[i] => (:hit, i)
            __       => :miss
        end
        @test item_case(annotated) == (:hit, 1)
        @test item_case(plain) == (:hit, 1)
        whole_case(path) = @reference_case path begin
            ∅  => :whole
            __ => :other
        end
        @test whole_case(annotate_reference_types(list, EmptyReference())) === :whole
    end

    @testset "the selection writers walk a typed path as the plain one" begin
        pair = CheckpointPair(left = CheckpointLeaf(text = "a"))
        typed = annotate_reference_types(pair, Reference(FieldReferenceStep("left"),
                                                         FieldReferenceStep("text")))
        set_selection!(pair, typed)
        @test getfield(pair, :selection)[] == typed
        @test strip_reference_types(getfield(pair.left, :selection)[]) ==
              Reference(FieldReferenceStep("text"))
        clear_selection!(pair)
        @test getfield(pair, :selection)[] === nothing
        @test getfield(pair.left, :selection)[] === nothing
    end

    @testset "a search answers typed paths" begin
        found = search_references(list, "x")
        @test length(found) == 1
        @test is_fully_typed_reference(found[1])
        @test strip_reference_types(found[1]) == plain
        @test found[1] != plain
    end

end
end # test_type_reference
