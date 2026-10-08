function test_switching()
@testset "SwitchingProjection reactive index" begin

    cv = CellVector(Cell[Cell(PrimitiveNumber(1)), Cell(PrimitiveNumber(2)), Cell(PrimitiveNumber(3))])
    index = Cell(1)
    sp = SwitchingProjection(Any[IdentityProjection(), ReversingProjection()], index)
    iomap = print_document(sp, IdentityProjection(), cv, PrinterContext())
    id = objectid(iomap)

    # branch 1 (IdentityProjection): output is the input
    @test iomap.output === cv

    # ── reactive branch swap (PAR-STABLE-IOMAP-IDENTITY) ─────────────────────
    # Writing the index cell reconciles the inner branch and re-derives output
    # through the SAME iomap — no re-print.
    index[] = 2                              # switch to ReversingProjection
    @test iomap.output isa CellVector
    @test iomap.output[1].value == 3         # reversed
    @test iomap.output[3].value == 1
    @test objectid(iomap) === id

    index[] = 1                              # switch back
    @test iomap.output === cv
    @test objectid(iomap) === id

end
end

function test_window_input_unwrapping()
@testset "WindowInputUnwrappingProjection transparent output" begin

    cv = CellVector(Cell[Cell(PrimitiveNumber(1)), Cell(PrimitiveNumber(2))])
    p = WindowInputUnwrappingProjection(IdentityProjection())
    iomap = print_document(p, nothing, cv, PrinterContext())

    @test iomap.output === cv                # transparent passthrough

    # a structural edit is visible through the held iomap (reactive forwarding)
    id = objectid(iomap)
    push!(cv, PrimitiveNumber(3))
    @test length(iomap.output) == 3
    @test objectid(iomap) === id

end
end

# A projection whose output is its input and whose reader answers one mark, so a
# test sees which reader a payload reaches.
struct NestMarkingProjection <: Projection end
ProjecturedKernel.ProjectionModule.print_document(p::NestMarkingProjection, recursion, input, ctx) =
    SimpleIoMap(p, input, input)
ProjecturedKernel.ProjectionModule.read_intent(::NestMarkingProjection, iomap::SimpleIoMap, payload) =
    ReplaceSelectionOperation(Reference(FieldReferenceStep("marked")))

function test_empty_nesting()
@testset "an empty NestingProjection prints and reads through the recursion" begin

    empty = NestingProjection()
    @test isempty(empty.elements)
    number = PrimitiveNumber(1)
    iomap = print_document(empty, NestMarkingProjection(), number, PrinterContext())
    @test iomap.output === number            # printed by the recursion that it got

    # A payload reaches the reader of the IO map that the print made, also with no
    # recursion at the read.
    answer = read_intent(empty, iomap, ReplaceSelectionOperation(EmptyReference()))
    @test answer isa ReplaceSelectionOperation
    @test get_reference_head(answer.path) == FieldReferenceStep("marked")

end
end
