# A part that a projection printed, such as the bracket of an array, is named by
# the projection that printed it: its introduced step holds the path of the part
# in that projection's output, and the path maps forward to the same place again.

# The path without its types, also inside an introduced step.
_ip_strip(path::ConcreteReference) =
    ConcreteReference(_ip_strip(path.head), _ip_strip(strip_reference_types(path.tail)))
_ip_strip(step::ProjectionReferenceStep) =
    ProjectionReferenceStep(step.projection, _ip_strip(strip_reference_types(step.output_path)))
_ip_strip(other) = strip_reference_types(other)

# The steps of `path`, the steps inside an introduced step included.
_ip_steps(path::ConcreteReference) = vcat(Any[path.head], _ip_steps(path.head), _ip_steps(path.tail))
_ip_steps(step::ProjectionReferenceStep) = _ip_steps(step.output_path)
_ip_steps(::Any) = Any[]

# Is `step` an introduced step of the collection that holds a bare offset?
_ip_is_flat(step) = step isa ProjectionReferenceStep &&
    step.projection isa CollectionCellVectorToSyntax &&
    step.output_path isa ConcreteReference && step.output_path.head isa RangeReferenceStep

function test_introduced_part_round_trip()
@testset "a printed part maps back to the projection that printed it" begin
    document = CellVector([PrimitiveNumber(1),
                           CellVector([PrimitiveNumber(2), PrimitiveNumber(3)])])
    to_syntax = RecursiveProjection(TypeDispatchingProjection(
        CellVector      => CollectionCellVectorToSyntax(),
        PrimitiveNumber => PrimitiveNumberToSyntaxLeaf()))
    chain = ChainingProjection(to_syntax, RecursiveProjection(SyntaxToText()))
    iomap = print_document(chain, document)
    caret(k) = ConcreteReference(RangeReferenceStep(k, k), EmptyReference())
    paths = Any[]
    for k in 0:200
        path = map_reference_backward(chain, iomap, caret(k))
        path === nothing || push!(paths, _ip_strip(path))
    end
    @test length(paths) > 10

    @testset "each caret goes forward and back to the same path" begin
        for path in paths
            forward = map_reference_forward(chain, iomap, path)
            @test forward !== nothing
            forward === nothing && continue
            @test _ip_strip(map_reference_backward(chain, iomap, forward)) == path
        end
    end

    @testset "the inner array names its own bracket" begin
        inner = [path for path in paths
                 if path.head == ElementReferenceStep(2) && path.tail isa ConcreteReference &&
                    path.tail.head isa ProjectionReferenceStep]
        @test !isempty(inner)
        @test all(path.tail.head.projection isa CollectionCellVectorToSyntax for path in inner)
        @test any(path.tail.head.output_path isa ConcreteReference &&
                  path.tail.head.output_path.head == FieldReferenceStep("open") for path in inner)
    end

    @testset "no introduced step of the collection holds an offset of the text" begin
        @test !any(_ip_is_flat(step) for path in paths for step in _ip_steps(path))
    end
end
end # test_introduced_part_round_trip

# Every kind of path maps back as the selection does: a mouse target at a text
# caret arrives at the collection as the same path, and it stays a mouse target.
function test_every_kind_of_path()
@testset "every kind of path maps back as the selection does" begin
    document = CellVector([PrimitiveNumber(1),
                           CellVector([PrimitiveNumber(2), PrimitiveNumber(3)])])
    to_syntax = RecursiveProjection(TypeDispatchingProjection(
        CellVector      => CollectionCellVectorToSyntax(),
        PrimitiveNumber => PrimitiveNumberToSyntaxLeaf()))
    chain = ChainingProjection(to_syntax, RecursiveProjection(SyntaxToText()))
    iomap = print_document(chain, document)
    caret(k) = ConcreteReference(RangeReferenceStep(k, k), EmptyReference())
    select(k) = read_intent(chain, iomap, ReplaceSelectionOperation(caret(k)))
    point(k) = read_intent(chain, iomap, ReplaceMouseTargetOperation(caret(k)))

    compared = 0
    for k in 0:200
        selection = select(k)
        selection isa ReplaceSelectionOperation || continue
        target = point(k)
        @test target isa ReplaceMouseTargetOperation
        target isa ReplaceMouseTargetOperation || continue
        @test _ip_strip(get_operation_path(target)) == _ip_strip(get_operation_path(selection))
        compared += 1
    end
    @test compared > 10

    @testset "the pointer on the inner bracket" begin
        is_inner_bracket(path) = begin
            path = _ip_strip(path)
            path isa ConcreteReference && path.head == ElementReferenceStep(2) &&
                path.tail isa ConcreteReference && path.tail.head isa ProjectionReferenceStep &&
                get_reference_head(path.tail.head.output_path) == FieldReferenceStep("open")
        end
        k = findfirst(k -> (op = select(k); op isa ReplaceSelectionOperation && is_inner_bracket(op.path)), 0:200)
        @test k !== nothing
        k === nothing && return
        evaluate_operation((document = document,), point(k - 1))
        inner = document[2]
        @test _ip_strip(document.mouse_target).head == ElementReferenceStep(2)
        @test inner.mouse_target isa ConcreteReference
        @test inner.mouse_target.head isa ProjectionReferenceStep
        @test inner.mouse_target.head.projection isa CollectionCellVectorToSyntax
        @test document[1].mouse_target === nothing
        @test inner[1].mouse_target === nothing
    end
end
end # test_every_kind_of_path

# Every kind of path of an output document is the forward image of the same kind of
# path of its input: the syntax node of each array holds the part under the pointer
# in its own terms.
function test_output_paths()
@testset "an output document holds the forward image of each kind of path" begin
    document = CellVector([PrimitiveNumber(1),
                           CellVector([PrimitiveNumber(2), PrimitiveNumber(3)])])
    to_syntax = RecursiveProjection(TypeDispatchingProjection(
        CellVector      => CollectionCellVectorToSyntax(),
        PrimitiveNumber => PrimitiveNumberToSyntaxLeaf()))
    chain = ChainingProjection(to_syntax, RecursiveProjection(SyntaxToText()))
    iomap = print_document(chain, document)
    caret(k) = ConcreteReference(RangeReferenceStep(k, k), EmptyReference())
    select(k) = read_intent(chain, iomap, ReplaceSelectionOperation(caret(k)))
    is_inner_bracket(path) = begin
        path = _ip_strip(path)
        path isa ConcreteReference && path.head == ElementReferenceStep(2) &&
            path.tail isa ConcreteReference && path.tail.head isa ProjectionReferenceStep
    end
    k = findfirst(k -> (op = select(k); op isa ReplaceSelectionOperation && is_inner_bracket(op.path)), 0:200)
    @test k !== nothing
    k === nothing && return
    evaluate_operation((document = document,),
                       read_intent(chain, iomap, ReplaceMouseTargetOperation(caret(k - 1))))

    syntax = print_document(to_syntax, document).output
    outer = strip_reference_types(getfield(syntax, :mouse_target)[])
    inner = strip_reference_types(getfield(syntax.children[2], :mouse_target)[])
    @test get_reference_head(inner) == FieldReferenceStep("open")
    @test outer isa ConcreteReference && get_reference_head(outer) == FieldReferenceStep("children")
    @test getfield(syntax.children[1], :mouse_target)[] === nothing

    # A move to the number `3` moves the image too.
    evaluate_operation((document = document,), ReplaceMouseTargetOperation(
        ConcreteReference(ElementReferenceStep(2), ConcreteReference(ElementReferenceStep(2),
            ConcreteReference(FieldReferenceStep("value"), ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))))))
    @test getfield(syntax.children[2], :mouse_target)[] !== nothing
    @test get_reference_head(strip_reference_types(getfield(syntax.children[2], :mouse_target)[])) ==
          FieldReferenceStep("children")
    @test getfield(syntax.children[2].children[2], :mouse_target)[] !== nothing
end
end # test_output_paths
