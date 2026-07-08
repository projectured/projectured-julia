"""
`@cell_struct` — the transparent-Cell struct codegen the declarative struct
macros (`@document`, `@iomap`, `@projection`) build on, exercised directly.

Like the rest of the cell layer, exercised entirely from ProjecturedKernel —
the structs below are test-local, no document/projection vocabulary in scope.
"""

using Test
using ProjecturedKernel.CellModule

# Bare and typed fields: everything becomes a transparent Cell.
@cell_struct struct CsPlain
    a
    b::Int
end

# Defaulted fields: keyword ctor with optional/required split.
@cell_struct struct CsDefaults
    x
    y::Float64 = 1.5
end

# An explicit supertype is preserved (no supertype injection).
abstract type CsBase end
@cell_struct struct CsSub <: CsBase
    v
end

function test_cell_struct()
@testset "CellStruct" begin

@testset "auto-wrapping constructor" begin
    p = CsPlain(1, 2)
    @test getfield(p, :a) isa Cell
    @test getfield(p, :b) isa Cell
    @test p.a == 1
    @test p.b == 2

    # a Cell argument passes through unwrapped — construction-time sharing
    c = Cell(7)
    q = CsPlain(c, 2)
    @test getfield(q, :a) === c
    @test q.a == 7
end

@testset "transparent read/write through the cells" begin
    p = CsPlain(1, 2)
    p.a = 10
    @test p.a == 10
    @test getfield(p, :a)[] == 10

    # the field cell participates in the reactive graph
    d = Cell(() -> p.a + 1)
    @test d[] == 11
    p.a = 20
    @test d[] == 21
end

@testset "keyword constructor from declared defaults" begin
    k = CsDefaults(x = 3)
    @test k.x == 3
    @test k.y == 1.5
    k2 = CsDefaults(x = 1, y = 2.0)
    @test k2.y == 2.0
    # a field without a default is a required keyword
    @test_throws UndefKeywordError CsDefaults(y = 2.0)
    # the positional auto-wrapping ctor is unchanged
    k3 = CsDefaults(5, 6.0)
    @test k3.x == 5
    @test k3.y == 6.0
end

@testset "explicit supertype is preserved" begin
    s = CsSub(1)
    @test s isa CsBase
    @test s.v == 1
end

end
end
