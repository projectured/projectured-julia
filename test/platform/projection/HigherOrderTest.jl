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

function test_reference_dispatching_path()
@testset "a dispatch by path whose path moves with the same choice leaves its output" begin
    # The path of a row of a list moves when a row before it goes. The choice reads
    # the path; with the same projection chosen, the IO map and its output stay,
    # so a reader of the output does not compute again.
    count = Cell(3)
    path = Cell(@computation extend_reference(EmptyReference(), FieldReferenceStep("rows"),
                                              ElementReferenceStep(count[])))
    context = make_child_context(PrinterContext(), path)
    chosen = Ref{Any}(nothing)
    rule = reference -> (chosen[] = reference; IdentityProjection())
    io = print_document(ReferenceDispatchingProjection(rule), IdentityProjection(),
                        PrimitiveNumber(7), context)
    runs = Ref(0)
    reader = Cell(@computation (runs[] += 1; io.output))
    @test reader[] isa PrimitiveNumber && runs[] == 1
    count[] = 2
    @test reader[] isa PrimitiveNumber
    @test runs[] == 1
    @test strip_reference_types(chosen[]) ==
          extend_reference(EmptyReference(), FieldReferenceStep("rows"), ElementReferenceStep(2))

    @testset "a new choice prints the position again" begin
        other = Cell(:identity)
        projections = Dict(:identity => IdentityProjection(), :copy => CopyingProjection())
        switch = ReferenceDispatchingProjection(reference -> projections[other[]])
        io = print_document(switch, IdentityProjection(), PrimitiveNumber(7), PrinterContext())
        first = io.inner_iomap
        other[] = :copy
        @test io.inner_iomap !== first
    end
end
end
