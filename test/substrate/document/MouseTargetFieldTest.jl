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
