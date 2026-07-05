"""
`CollectionModule` — the reactive sequence container `CellVector`. Migrated
into base at kernel plan P8. Exercises the R1 seam method: base registers
`child_reference_steps(::CellVector)` onto the kernel's `OperationModule`
generic, which the operation-layer test then validates through the default
fieldnames-walk. Here we cover the container's basic protocol.
"""

using Test
using ProjecturedBase.CollectionModule
using ProjecturedBase.CellModule: Cell

@testset "Collection" begin

    @testset "CellVector constructs and iterates" begin
        v = CellVector([1, 2, 3])
        @test length(v) == 3
        @test v[1] == 1
        @test v[3] == 3
        @test collect(v) == [1, 2, 3]
    end

    @testset "CellVector push/pop mutates in place" begin
        v = CellVector(Any[])
        push!(v, 10)
        push!(v, 20)
        @test length(v) == 2
        @test v[2] == 20
        pop!(v)
        @test length(v) == 1
    end

end
