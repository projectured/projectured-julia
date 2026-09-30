"""
`@projection` — the codegen that declares a projection type. Verifies the default
supertype and a supertype that the declaration gives, the fields that read and
write through their cells and that a computation follows, the keyword constructor
of a declaration with a default, and the export of the declared type.
"""

using Test
using ProjecturedKernel.CellModule: Cell, @computation
using ProjecturedKernel.ProjectionModule: Projection

# `@projection` exports the type that it declares, so the probe types live in a
# module of their own and not in the test package.
module _ProjectionMacroProbe
    import ProjecturedKernel.CellModule: Cell, Computation
    import ProjecturedKernel.ProjectionModule: Projection, var"@projection"

    abstract type ProbeFamily <: Projection end

    @projection struct PlainProbe
        depth::Int
    end

    @projection struct DefaultedProbe <: ProbeFamily
        depth::Int = 2
        label::String
    end
end

function test_projection_macro()
@testset "@projection" begin
    P = _ProjectionMacroProbe

    @testset "a projection is a Projection, or of the supertype that it names" begin
        @test P.PlainProbe <: Projection
        @test P.DefaultedProbe <: P.ProbeFamily
    end

    # A parameter cell is what makes a printer reactive: a write to it makes a
    # computation that read it compute again.
    @testset "a field reads and writes through its cell" begin
        probe = P.PlainProbe(3)
        cell = getfield(probe, :depth)
        @test cell isa Cell
        @test probe.depth == 3
        doubled = Cell(@computation 2 * probe.depth)
        @test doubled[] == 6
        probe.depth = 4
        @test cell[] == 4
        @test getfield(probe, :depth) === cell
        @test doubled[] == 8
    end

    @testset "a field with a default is an optional keyword" begin
        probe = P.DefaultedProbe(; label = "x")
        @test (probe.depth, probe.label) == (2, "x")
        @test P.DefaultedProbe(; depth = 5, label = "y").depth == 5
        @test_throws UndefKeywordError P.DefaultedProbe()
    end

    @testset "the macro exports the type that it declares" begin
        @test Base.isexported(P, :PlainProbe)
        @test Base.isexported(P, :DefaultedProbe)
    end

end
end # test_projection_macro
