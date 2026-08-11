function test_searching()
@testset "SearchingProjection" begin

    cv = CellVector(Cell[Cell(PrimitiveString("foo")), Cell(PrimitiveString("bar")),
                         Cell(PrimitiveString("food"))])
    sp = SearchingProjection(r"foo")
    iomap = print_document(sp, nothing, cv, PrinterContext())

    # ── basic search: the matching objects, in pre-order ────────────────────
    @test iomap.output isa CellVector
    @test length(iomap.output) == 2
    @test iomap.output[1].value == "foo"
    @test iomap.output[2].value == "food"
    @test length(iomap.match_paths) == 2

    # ── reactive output (AR-STABLE-IOMAP-IDENTITY) ──────────────────────────
    # Appending a matching element re-walks the tree through the SAME iomap —
    # both output and match_paths track it — where the eager walk would freeze.
    id = objectid(iomap)
    push!(cv, PrimitiveString("foobar"))
    @test length(iomap.output) == 3
    @test iomap.output[3].value == "foobar"
    @test length(iomap.match_paths) == 3
    @test objectid(iomap) === id

end
end
