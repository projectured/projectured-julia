function test_sorting()
@testset "SortingProjection" begin

    cv = CellVector(Cell[Cell(PrimitiveNumber(3)), Cell(PrimitiveNumber(1)), Cell(PrimitiveNumber(2))])
    sp = SortingProjection(by = x -> x.value)
    iomap = print_document(sp, IdentityProjection(), cv, PrinterContext())

    # ── basic sort ──────────────────────────────────────────────────────────
    @test iomap.output isa CellVector
    @test length(iomap.output) == 3
    @test iomap.output[1].value == 1
    @test iomap.output[2].value == 2
    @test iomap.output[3].value == 3
    @test iomap.index_map == [2, 3, 1]      # output position -> input index

    # ── reference mapping (unchanged): forward then backward round-trips ─────
    fwd = map_reference_forward(sp, iomap, ConcreteReference(ElementReferenceStep(1), EmptyReference()))
    @test fwd !== nothing
    @test map_reference_backward(sp, iomap, fwd) !== nothing

    # ── reactive output (PAR-STABLE-IOMAP-IDENTITY) ──────────────────────────
    # Inserting a new smallest element re-sorts through the SAME iomap — no
    # re-print — where the eager perm/output would have frozen.
    id = objectid(iomap)
    push!(cv, PrimitiveNumber(0))
    @test length(iomap.output) == 4
    @test iomap.output[1].value == 0
    @test iomap.output[4].value == 3
    @test iomap.index_map == [4, 2, 3, 1]
    @test objectid(iomap) === id


    # ── the element type of the list ────────────────────────────────────────
    # The sorted list keeps the element type of its input, so a field that
    # declares the element type of a list takes it.
    typed = CellVector{Document}(Any[PrimitiveNumber(2), PrimitiveNumber(1), PrimitiveNumber(3)])
    typed_output = print_document(SortingProjection(by = x -> x.value), IdentityProjection(), typed, PrinterContext()).output
    @test typed_output isa CellVector{Document}
    @test [element.value for element in typed_output] == [1, 2, 3]

end
end
