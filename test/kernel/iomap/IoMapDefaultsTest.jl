"""
`IoMapModule` — `@iomap`, the three accessors and the general IoMaps, over
test-local IoMap structs.
"""

using Test
using ProjecturedKernel.CellModule: Cell, @computation, ImmutableCell, MutableCell,
                                    ReactiveCell
using ProjecturedKernel.IoMapModule

@iomap struct PlainTestIoMap
    projection::Any
    input::Any
    output::Any
end

abstract type FamilyTestIoMap <: IoMap end

@iomap struct MemberTestIoMap <: FamilyTestIoMap
    projection::Any
    input::Any
    output::Any
end

@iomap ImmutableCell struct ImmutableTestIoMap
    projection::Any
    input::Any
    output::Any
end

@iomap MutableCell struct MutableTestIoMap
    projection::Any
    input::Any
    output::Any
end

@iomap struct DefaultedTestIoMap
    projection::Any = nothing
    input::Any = nothing
    output::Any = 0
end

function test_iomap_defaults()
@testset "IoMapDefaults" begin

    @testset "@iomap adds the supertype IoMap and keeps one that the struct names" begin
        @test supertype(PlainTestIoMap) === IoMap
        @test supertype(MemberTestIoMap) === FamilyTestIoMap
        @test MemberTestIoMap(nothing, 1, 2) isa IoMap
    end

    @testset "@iomap takes the kind of its cells before struct" begin
        @test getfield(PlainTestIoMap(nothing, 1, 2), :output) isa ReactiveCell
        @test getfield(ImmutableTestIoMap(nothing, 1, 2), :output) isa ImmutableCell
        @test getfield(MutableTestIoMap(nothing, 1, 2), :output) isa MutableCell
        no_kind = :(@iomap NoKind struct NoKindTestIoMap
            output::Any
        end)
        @test_throws "expected a cell kind" macroexpand(@__MODULE__, no_kind)
    end

    @testset "a field reads and writes through its cell" begin
        iomap = PlainTestIoMap(nothing, 1, 2)
        @test iomap.output == 2
        iomap.output = 3
        @test iomap.output == 3
        @test DefaultedTestIoMap(output = 5).output == 5
        @test DefaultedTestIoMap().input === nothing
    end

    @testset "the three accessors read the fields of the convention" begin
        iomap = SimpleIoMap(:projection, :input, :output)
        @test get_iomap_projection(iomap) === :projection
        @test get_iomap_input(iomap) === :input
        @test get_iomap_output(iomap) === :output

        # A computed output follows its source, and the IoMap stays the same object.
        source = Cell(1)
        derived = SimpleIoMap(:projection, :input, Cell(@computation source[] * 2))
        @test get_iomap_output(derived) == 2
        source[] = 5
        @test get_iomap_output(derived) == 10
    end

    @testset "a ChildrenIoMap and a ContentIoMap read their inner IoMaps" begin
        leaf = SimpleIoMap(:projection, :leaf, :shown)
        children = ChildrenIoMap(:projection, :input, :output,
                                 Cell(@computation Any[leaf, leaf]))
        @test children isa IoMap
        @test length(children.child_iomaps) == 2
        @test children.child_iomaps[1] === leaf
        @test get_iomap_output(children) === :output

        content = ContentIoMap(:projection, :input, :output, leaf)
        @test content isa IoMap
        @test content.inner_iomap === leaf
        @test get_iomap_input(content) === :input
    end

end
end # test_iomap_defaults
