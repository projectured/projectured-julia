# The field `mouse_target` of a document: the path of the part under the pointer,
# view state as the selection is. A collection keeps its element sugar, a walk over
# the content does not enter it, and a load gives none.

_mt_path(k) = ConcreteReference(ElementReferenceStep(k), EmptyReference())

function test_mouse_target_field()
@testset "a document holds the part under the pointer as view state" begin

@testset "a collection of three documents is three elements" begin
    # The full constructor of `CellVector` also takes three arguments now, but it
    # takes only a cell or `nothing` for the mouse target, so three documents
    # reach the element sugar.
    vector = CellVector(PrimitiveString("a"), PrimitiveString("b"), PrimitiveString("c"))
    @test length(vector) == 3
    @test vector.mouse_target === nothing
    @test vector[3].value == "c"
end

@testset "a walk over the content does not enter the mouse target" begin
    vector = CellVector([PrimitiveString("a"), PrimitiveString("b")])
    vector.mouse_target = _mt_path(2)
    @test vector.mouse_target == _mt_path(2)
    @test isempty(search_documents(vector, node -> node isa RangeReferenceStep))
end

@testset "a load gives no mouse target, and keeps the selection" begin
    vector = CellVector([PrimitiveString("a"), PrimitiveString("b")])
    set_selection!(vector, _mt_path(1))
    vector.mouse_target = _mt_path(2)
    vector[2].mouse_target = EmptyReference()
    path = joinpath(mktempdir(), "vector.bin")
    save_document(vector, path)
    loaded = load_document(path)
    @test length(loaded) == 2
    @test loaded.mouse_target === nothing
    @test loaded[2].mouse_target === nothing
    @test strip_reference_types(loaded.selection) == _mt_path(1)
end

end # @testset
end # test_mouse_target_field

# The chain of the mouse target on `[1, [2, 3]]`: the root holds the whole path,
# each document on it holds its own tail, and a document off it holds nothing.
_mt_path(k, l) = ConcreteReference(ElementReferenceStep(k), _mt_path(l))

function test_mouse_target_chain()
@testset "each document on the path of the pointer holds its own tail" begin

make_nested() = CellVector([PrimitiveNumber(1),
                            CellVector([PrimitiveNumber(2), PrimitiveNumber(3)])])

@testset "the pointer on the 2" begin
    outer = make_nested()
    replace_mouse_target!(outer, _mt_path(2, 1))
    @test outer.mouse_target == _mt_path(2, 1)
    @test outer[2].mouse_target == _mt_path(1)
    @test outer[2][1].mouse_target == EmptyReference()
    @test outer[1].mouse_target === nothing
    @test outer[2][2].mouse_target === nothing
end

@testset "the same path again writes no cell" begin
    outer = make_nested()
    replace_mouse_target!(outer, _mt_path(2, 1))
    readers = [Cell(@computation getfield(document, :mouse_target)[])
               for document in (outer, outer[2], outer[2][1])]
    foreach(reader -> reader[], readers)
    replace_mouse_target!(outer, _mt_path(2, 1))
    @test all(is_cell_up_to_date, readers)
end

@testset "a move to another part clears the old branch" begin
    outer = make_nested()
    replace_mouse_target!(outer, _mt_path(2, 1))
    inner_reader = Cell(@computation getfield(outer[2], :mouse_target)[])
    inner_reader[]
    replace_mouse_target!(outer, _mt_path(2, 2))
    @test outer[2].mouse_target == _mt_path(2)
    @test outer[2][1].mouse_target === nothing
    @test outer[2][2].mouse_target == EmptyReference()
    replace_mouse_target!(outer, _mt_path(1))
    @test outer.mouse_target == _mt_path(1)
    @test outer[1].mouse_target == EmptyReference()
    @test outer[2].mouse_target === nothing
    @test outer[2][2].mouse_target === nothing
    @test !is_cell_up_to_date(inner_reader)
    replace_mouse_target!(outer, nothing)
    @test outer.mouse_target === nothing
    @test outer[1].mouse_target === nothing
end

@testset "the path is kept without its types" begin
    outer = make_nested()
    typed = ConcreteReference(CellVector, ElementReferenceStep(2), _mt_path(1))
    replace_mouse_target!(outer, typed)
    @test outer.mouse_target == _mt_path(2, 1)
    @test outer[2][1].mouse_target == EmptyReference()
end

@testset "a path to a part that is gone stops at the last document" begin
    outer = make_nested()
    replace_mouse_target!(outer, _mt_path(5, 1))
    @test outer.mouse_target == _mt_path(5, 1)
    @test outer[1].mouse_target === nothing
    @test outer[2].mouse_target === nothing
end

@testset "the operation writes at the root, keeps its kind and is no edit" begin
    outer = make_nested()
    operation = ReplaceMouseTargetOperation(_mt_path(1))
    @test operation isa ReplacePathOperation
    @test get_operation_path(operation) == _mt_path(1)
    evaluate_operation((document = outer,), operation)
    @test outer.mouse_target == _mt_path(1)
    @test outer[1].mouse_target == EmptyReference()
    rerooted = reroot_operation(ReplaceMouseTargetOperation(_mt_path(1)),
                                (ElementReferenceStep(2),))
    @test rerooted isa ReplaceMouseTargetOperation
    @test get_operation_path(rerooted) == _mt_path(2, 1)
    @test make_inverse_operation(outer, operation) isa DoNothingOperation
    @test startswith(describe_operation(operation), "point at ")
end

end # @testset
end # test_mouse_target_chain
