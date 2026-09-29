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
