"""
`UntrackedCell` and `run_untracked`: a cell that computes at each read and records
no reader, and a struct of cells of that kind. The tests need only the cell layer
and the struct layer.
"""

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.CellStructModule

# A struct whose fields are untracked cells, as a style field of a projection is.
@cell_struct UntrackedCell struct UcSample
    a::Int
    b::String
end

function test_untracked_cell()
@testset "UntrackedCell" begin

@testset "a plain value is a constant" begin
    c = UntrackedCell{Int}(3)
    @test c[] == 3
    @test peek(c) == 3
    @test is_cell_up_to_date(c)
    @test !is_computed_cell(c)
    @test get_cell_value_type(c) === Int
    @test UntrackedCell(4) isa UntrackedCell{Int}
    @test_throws MethodError (c[] = 5)
    copied = copy_cell_as(c, 6)
    @test copied isa UntrackedCell{Int}
    @test copied[] == 6
end

@testset "a computation runs at each read" begin
    source = Cell(1)
    untracked = UntrackedCell{Int}(@computation source[] * 10)
    @test is_computed_cell(untracked)
    @test untracked[] == 10
    source[] = 2
    @test untracked[] == 20
end

@testset "a reader records no edge" begin
    source = Cell(1)
    untracked = UntrackedCell{Int}(@computation source[] * 10)
    reader = Cell(@computation untracked[] + 1)
    @test reader[] == 11
    @test !has_dependent_cells(source)
    source[] = 2
    @test is_cell_up_to_date(reader)
    @test reader[] == 11                    # the reader keeps its value
    @test untracked[] == 20                 # the untracked cell reads the new one
end

@testset "a read deep inside the computation records no edge" begin
    source = Cell(1)
    read_source() = source[]
    untracked = UntrackedCell{Int}(@computation read_source())
    reader = Cell(@computation untracked[])
    @test reader[] == 1
    @test !has_dependent_cells(source)
end

@testset "a cell that computes inside keeps its own dependencies" begin
    source = Cell(1)
    inner = Cell(@computation source[] + 100)
    untracked = UntrackedCell{Int}(@computation inner[])
    reader = Cell(@computation untracked[])
    @test reader[] == 101
    @test has_dependent_cells(source)       # `inner` read it
    @test !has_dependent_cells(inner)       # `reader` did not
    source[] = 5
    @test !is_cell_up_to_date(inner)
    @test is_cell_up_to_date(reader)
    @test untracked[] == 105
end

@testset "an untracked cell inside an untracked cell" begin
    source = Cell(1)
    lower = UntrackedCell{Int}(@computation source[])
    upper = UntrackedCell{Int}(@computation lower[] + 1)
    reader = Cell(@computation upper[])
    @test reader[] == 2
    @test !has_dependent_cells(source)
end

@testset "the stack comes back after an error" begin
    source = Cell(1)
    failing = UntrackedCell{Int}(@computation error("no value"))
    reader = Cell(@computation (try failing[] catch; 0 end) + source[])
    @test reader[] == 1
    @test has_dependent_cells(source)       # the read after the error recorded
    source[] = 2
    @test !is_cell_up_to_date(reader)
    @test reader[] == 2
end

@testset "run_untracked outside a computation" begin
    source = Cell(3)
    @test CellModule.run_untracked(() -> source[] + 1) == 4
    @test !has_dependent_cells(source)
end

@testset "a struct of untracked cells" begin
    sample = UcSample(1, "x")
    @test getfield(sample, :a) isa UntrackedCell{Int}
    @test sample.a == 1
    @test sample.b == "x"
    @test get_cell_struct_kind(sample) === UntrackedCell
    @test_throws MethodError (sample.a = 2)

    source = Cell(7)
    shared = UntrackedCell{Int}(@computation source[])
    one = UcSample(shared, "one")
    other = UcSample(shared, "other")
    @test getfield(one, :a) === shared       # the constructor keeps the cell
    @test getfield(other, :a) === shared
    source[] = 8
    @test one.a == 8
    @test other.a == 8
end

end
end
