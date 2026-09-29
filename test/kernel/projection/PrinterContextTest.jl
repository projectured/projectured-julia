"""
`PrinterContext` — the range that a parent gives on each axis.

Confirms:
- the three states of an axis: exact (the minimum and the maximum are one
  cell), bounded (a maximum and no minimum) and free (neither);
- each helper changes only the axis it is given, and keeps the other;
- `get_exact_width` / `get_exact_height` read the extent of an exact range and
  `nothing` otherwise;
- `withhold_offer` takes the axis `:x` or `:y`, and throws for any other;
- a child context, a new clock and a new property keep the ranges;
- `with_inner_size` keeps the state of each axis and reduces each extent, and
  `with_size_range` sets both ends of an axis;
- `get_property` reads a property with a default, and `with_property` copies;
- a child context of a document records the type of each node.
"""

using Test
using ProjecturedKernel.ProjectionModule: PrinterContext, make_child_context, with_exact_size,
    with_bounded_size, get_exact_width, get_exact_height, withhold_offer, with_clock,
    with_property, with_inner_size, with_size_range, get_property
using ProjecturedKernel.CellModule: Cell
using ProjecturedKernel.ClockModule: Clock
using ProjecturedKernel.DocumentModule: @document
using ProjecturedKernel.ReferenceModule: EmptyReference, FieldReferenceStep, Reference,
    strip_reference_types, get_reference_node_type, is_fully_typed_reference

@document struct ContextProbeLeaf
    text::String
end

function test_printer_context_range()
@testset "PrinterContext range" begin

    @testset "a root context is exact on each axis it is given" begin
        width, height = Cell(500), Cell(300)
        ctx = PrinterContext(EmptyReference(), width, height, Dict{Symbol,Any}())
        @test ctx.minimum_width === width && ctx.maximum_width === width
        @test ctx.minimum_height === height && ctx.maximum_height === height
        @test get_exact_width(ctx) === width
        @test get_exact_height(ctx) === height
    end

    @testset "a context with no size is free on both axes" begin
        ctx = PrinterContext()
        @test ctx.minimum_width === nothing && ctx.maximum_width === nothing
        @test ctx.minimum_height === nothing && ctx.maximum_height === nothing
        @test get_exact_width(ctx) === nothing
    end

    @testset "a bounded axis has an edge and no minimum, and is no slot" begin
        height = Cell(300)
        ctx = PrinterContext(EmptyReference(), Cell(500), height, Dict{Symbol,Any}())
        edge = Cell(400)
        bounded = with_bounded_size(ctx; width = edge)
        @test bounded.minimum_width === nothing
        @test bounded.maximum_width === edge
        @test get_exact_width(bounded) === nothing
        @test get_exact_height(bounded) === height        # the other axis keeps its range
    end

    @testset "an exact axis is one cell" begin
        slot = Cell(200)
        exact = with_exact_size(with_bounded_size(PrinterContext(); height = Cell(90)); width = slot)
        @test exact.minimum_width === slot && exact.maximum_width === slot
        @test get_exact_width(exact) === slot
        @test exact.minimum_height === nothing && exact.maximum_height[] == 90
    end

    @testset "withhold_offer frees one axis and keeps the other" begin
        edge = Cell(120)
        ctx = with_bounded_size(PrinterContext(EmptyReference(), Cell(500), Cell(300), Dict{Symbol,Any}());
                                height = edge)
        free = withhold_offer(ctx, :x)
        @test free.minimum_width === nothing && free.maximum_width === nothing
        @test free.minimum_height === nothing && free.maximum_height === edge
        @test_throws ArgumentError withhold_offer(ctx, :z)
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

    # A container passes its range on to its content less its margin: each axis
    # keeps its state, and each extent is reduced and never goes under 0.
    @testset "an inner size is the range less an inset, in the same state" begin
        width, edge = Cell(100), Cell(50)
        ctx = with_bounded_size(PrinterContext(EmptyReference(), width, nothing,
                                               Dict{Symbol,Any}()); height = edge)
        inner = with_inner_size(ctx; width = 10, height = Cell(5))
        @test inner.minimum_width === inner.maximum_width
        @test get_exact_width(inner)[] == 90
        @test inner.minimum_height === nothing && inner.maximum_height[] == 45
        # The inner extent follows the outer one.
        width[] = 200
        @test get_exact_width(inner)[] == 190
        # A free axis stays free, and an inset larger than the extent gives 0.
        free = with_inner_size(PrinterContext(); width = 10)
        @test free.minimum_width === nothing && free.maximum_width === nothing
        @test get_exact_width(with_inner_size(ctx; width = 500))[] == 0
        ranged = with_size_range(PrinterContext(); width = (Cell(20), Cell(100)))
        narrowed = with_inner_size(ranged; width = 30)
        @test (narrowed.minimum_width[], narrowed.maximum_width[]) == (0, 70)
    end

    @testset "a size range sets both ends of the axes that it gets" begin
        height = Cell(300)
        ctx = PrinterContext(EmptyReference(), Cell(500), height, Dict{Symbol,Any}())
        lower, upper = Cell(10), Cell(90)
        ranged = with_size_range(ctx; width = (lower, upper))
        @test ranged.minimum_width === lower && ranged.maximum_width === upper
        @test get_exact_width(ranged) === nothing
        @test get_exact_height(ranged) === height        # the other axis keeps its range
        freed = with_size_range(ctx; height = (nothing, nothing))
        @test freed.minimum_height === nothing && freed.maximum_height === nothing
    end

    @testset "a property is read with a default, and a copy keeps it apart" begin
        ctx = PrinterContext()
        @test get_property(ctx, :theme) === nothing
        @test get_property(ctx, :theme, :light) === :light
        dark = with_property(ctx, :theme, :dark)
        @test get_property(dark, :theme) === :dark
        # The parent and a sibling do not see the property.
        @test get_property(ctx, :theme) === nothing
        @test get_property(with_property(ctx, :focus, true), :theme) === nothing
    end

    @testset "a child context of a document records the type of each node" begin
        leaf = ContextProbeLeaf("text", nothing)
        ctx = with_bounded_size(PrinterContext(); width = Cell(250))
        child = make_child_context(ctx, leaf, FieldReferenceStep("text"))
        @test strip_reference_types(child.reference) ==
              Reference(FieldReferenceStep("text"))
        @test child.reference.type === get_reference_node_type(leaf)
        @test is_fully_typed_reference(child.reference)
        @test child.maximum_width === ctx.maximum_width
        # The steps alone record no type.
        untyped = make_child_context(ctx, FieldReferenceStep("text"))
        @test untyped.reference.type === nothing
        # A whole reference is the reference of the child as it is.
        reference = Reference(FieldReferenceStep("other"))
        @test make_child_context(ctx, reference).reference === reference
    end

end
end # test_printer_context_range
