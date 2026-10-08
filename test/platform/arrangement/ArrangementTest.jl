# An arrangement places projections at the parts of a document. A projection
# that a person adds to an entry, or removes from it, prints only its own place
# again, and the document outside that place keeps its IO maps.

using ProjecturedKernel.CellModule: Cell
using ProjecturedPlatform.CollectionModule: CellVector

# A copy that counts its prints, by the object that it prints.
struct _ArrangementCountingCopy <: Projection
    prints::Dict{UInt,Int}
end
function ProjectionModule.print_document(p::_ArrangementCountingCopy, recursion, input, ctx)
    p.prints[objectid(input)] = get(p.prints, objectid(input), 0) + 1
    print_document(CopyingProjection(), recursion, input, ctx)
end

# A description that a person places at a collection: show it in reverse.
struct _ArrangementReverseDescription end
ArrangementModule.make_arrangement_projection(::_ArrangementReverseDescription) = ReversingProjection()

function test_arrangement()
@testset "an arrangement places projections at the parts of a document" begin
    prints = Dict{UInt,Int}()
    rec = RecursiveProjection(make_arranged_dispatch(TypeDispatchingProjection(Pair{Type,Any}[
        ArrangementDocument => ArrangingProjection(),
        CellVector => _ArrangementCountingCopy(prints),
        Any => IdentityProjection()])))
    row(values) = CellVector(Cell[Cell(v) for v in values])
    first_row, second_row = row([1, 2, 3]), row([4, 5, 6])
    document = CellVector(Cell[Cell(first_row), Cell(second_row)])
    arranged = ArrangementDocument(document, ArrangementEntry[])
    io = print_document(rec, nothing, arranged, PrinterContext())
    shown() = [[value for value in shown_row] for shown_row in io.output]
    printed(object) = get(prints, objectid(object), 0)
    @test shown() == [[1, 2, 3], [4, 5, 6]]
    @test (printed(document), printed(first_row), printed(second_row)) == (1, 1, 1)

    # An entry at the second row: only that row prints again, through the chain.
    at_second = extend_reference(EmptyReference(), ElementReferenceStep(2))
    entry = ArrangementEntry(at_second, Any[_ArrangementReverseDescription()])
    push!(arranged.entries, entry)
    @test shown() == [[1, 2, 3], [6, 5, 4]]
    @test (printed(document), printed(first_row)) == (1, 1)

    # An edit of another entry, and an entry with no projection, change nothing
    # that shows and print nothing again.
    push!(arranged.entries, ArrangementEntry(extend_reference(EmptyReference(), ElementReferenceStep(1)), Any[]))
    count = sum(values(prints))
    @test shown() == [[1, 2, 3], [6, 5, 4]]
    @test sum(values(prints)) == count

    # The last projection goes, and the row shows as it is again.
    deleteat!(arranged.entries, 1)
    @test shown() == [[1, 2, 3], [4, 5, 6]]
    @test (printed(document), printed(first_row)) == (1, 1)

    # A path of the arranged document goes through the field `document`.
    image = map_reference_forward(rec, io, ConcreteReference(FieldReferenceStep("document"),
        extend_reference(EmptyReference(), ElementReferenceStep(1))))
    @test image !== nothing
    @test map_reference_forward(rec, io, ConcreteReference(FieldReferenceStep("entries"), EmptyReference())) === nothing
end
end
