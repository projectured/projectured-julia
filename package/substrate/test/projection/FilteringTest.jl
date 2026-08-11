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

    # ── reactive output (AR-STABLE-IOMAP-IDENTITY) ──────────────────────────
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

end
end
