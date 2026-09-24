"""
`PrinterContext` — the range that a parent gives on each axis.

Confirms:
- the three states of an axis: exact (the minimum and the maximum are one
  cell), bounded (a maximum and no minimum) and free (neither);
- each helper changes only the axis it is given, and keeps the other;
- `available_width` / `available_height` read the extent of an exact range and
  `nothing` otherwise;
- a child context, a new clock and a new property keep the ranges.
"""

using Test
using ProjecturedKernel.ProjectionModule: PrinterContext, make_child_context, with_exact_size,
    with_bounded_size, with_available_size, withhold_offer, with_clock, with_property
using ProjecturedKernel.CellModule: Cell
using ProjecturedKernel.ClockModule: Clock
using ProjecturedKernel.ReferenceModule: EmptyReference, FieldReferenceStep

function test_printer_context_range()
@testset "PrinterContext range" begin

    @testset "a root context is exact on each axis it is given" begin
        width, height = Cell(500), Cell(300)
        ctx = PrinterContext(EmptyReference(), width, height, Dict{Symbol,Any}())
        @test ctx.minimum_width === width && ctx.maximum_width === width
        @test ctx.minimum_height === height && ctx.maximum_height === height
        @test ctx.available_width === width
        @test ctx.available_height === height
    end

    @testset "a context with no size is free on both axes" begin
        ctx = PrinterContext()
        @test ctx.minimum_width === nothing && ctx.maximum_width === nothing
        @test ctx.minimum_height === nothing && ctx.maximum_height === nothing
        @test ctx.available_width === nothing
    end

    @testset "a bounded axis has an edge and no minimum, and is no slot" begin
        height = Cell(300)
        ctx = PrinterContext(EmptyReference(), Cell(500), height, Dict{Symbol,Any}())
        edge = Cell(400)
        bounded = with_bounded_size(ctx; width = edge)
        @test bounded.minimum_width === nothing
        @test bounded.maximum_width === edge
        @test bounded.available_width === nothing
        @test bounded.available_height === height        # the other axis keeps its range
    end

    @testset "an exact axis is one cell, and with_available_size is the same" begin
        slot = Cell(200)
        exact = with_exact_size(with_bounded_size(PrinterContext(); height = Cell(90)); width = slot)
        @test exact.minimum_width === slot && exact.maximum_width === slot
        @test exact.available_width === slot
        @test exact.minimum_height === nothing && exact.maximum_height[] == 90
        same = with_available_size(PrinterContext(); width = slot)
        @test same.minimum_width === slot && same.maximum_width === slot
    end

    @testset "withhold_offer frees one axis and keeps the other" begin
        edge = Cell(120)
        ctx = with_bounded_size(PrinterContext(EmptyReference(), Cell(500), Cell(300), Dict{Symbol,Any}());
                                height = edge)
        free = withhold_offer(ctx, :x)
        @test free.minimum_width === nothing && free.maximum_width === nothing
        @test free.minimum_height === nothing && free.maximum_height === edge
    end

    @testset "a child context, a clock and a property keep the ranges" begin
        edge = Cell(250)
        ctx = with_bounded_size(PrinterContext(); width = edge)
        for derived in (make_child_context(ctx, FieldReferenceStep("children")),
                        with_clock(ctx, Clock()), with_property(ctx, :theme, :dark))
            @test derived.minimum_width === nothing
            @test derived.maximum_width === edge
        end
    end

end
end # test_printer_context_range
