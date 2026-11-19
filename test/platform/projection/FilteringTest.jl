function test_filtering()
@testset "FilteringProjection" begin

    cv = CellVector(Cell[Cell(PrimitiveNumber(-1)), Cell(PrimitiveNumber(2)),
                         Cell(PrimitiveNumber(-3)), Cell(PrimitiveNumber(4))])
    fp = FilteringProjection(predicate = x -> x.value > 0)
    iomap = print_document(fp, IdentityProjection(), cv, PrinterContext())

    # ── basic filtering ─────────────────────────────────────────────────────
    @test iomap.output isa CellVector
    @test length(iomap.output) == 2
    @test iomap.output[1].value == 2
    @test iomap.output[2].value == 4
    @test iomap.kept_indices == [2, 4]

    # ── reactive output (PAR-STABLE-IOMAP-IDENTITY) ──────────────────────────
    # Appending a matching element re-derives kept_indices + output through the
    # SAME iomap — no re-print — where the eager subset would have frozen.
    id = objectid(iomap)
    push!(cv, PrimitiveNumber(5))
    @test iomap.kept_indices == [2, 4, 5]
    @test length(iomap.output) == 3
    @test iomap.output[3].value == 5
    @test objectid(iomap) === id

    # ── reference mapping (unchanged): kept element maps, filtered one drops ─
    @test map_reference_forward(fp, iomap, ConcreteReference(ElementReferenceStep(2), EmptyReference())) !== nothing
    @test map_reference_forward(fp, iomap, ConcreteReference(ElementReferenceStep(1), EmptyReference())) === nothing


    # ── the element type of the list ────────────────────────────────────────
    # The kept list keeps the element type of its input, so a field that
    # declares the element type of a list takes it.
    typed = CellVector{Document}(Any[PrimitiveNumber(2), PrimitiveNumber(1), PrimitiveNumber(3)])
    typed_output = print_document(FilteringProjection(predicate = x -> x.value > 1), IdentityProjection(), typed, PrinterContext()).output
    @test typed_output isa CellVector{Document}
    @test [element.value for element in typed_output] == [2, 3]

end
end
