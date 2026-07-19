function test_reversing()
@testset "ReversingProjection" begin

    cv = CellVector(Cell[Cell(PrimitiveNumber(1)), Cell(PrimitiveNumber(2)), Cell(PrimitiveNumber(3))])
    rp = ReversingProjection()
    iomap = print_document(rp, IdentityProjection(), cv, PrinterContext())

    # ── basic reversal ──────────────────────────────────────────────────────
    @test iomap.output isa CellVector
    @test length(iomap.output) == 3
    @test iomap.output[1].value == 3
    @test iomap.output[2].value == 2
    @test iomap.output[3].value == 1

    # ── reactive output (AR-STABLE-IOMAP-IDENTITY) ──────────────────────────
    # A structural edit re-derives `output` through the SAME iomap object — no
    # re-print — which is what lets Reversing sit inside a chain. Before the
    # reactive conversion the eager `reverse(input)` froze at its first value.
    id = objectid(iomap)
    push!(cv, PrimitiveNumber(4))
    @test length(iomap.output) == 4
    @test iomap.output[1].value == 4        # newest element leads after reversal
    @test iomap.output[4].value == 1
    @test objectid(iomap) === id            # same iomap object throughout

    # ── reference mapping still maps (unchanged by the conversion) ──────────
    fwd = map_reference_forward(rp, iomap, ConcreteReference(ElementReferenceStep(1), EmptyReference()))
    @test fwd !== nothing                   # input head → output tail

end
end
