# What a print shows while a value is still to come: a cell that keeps its last
# final value while its value is provisional, a value that never was final shows
# as it is, and a held value that a check refuses gives way to the provisional one.

using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.ProjectionModule: make_final_holding_cell

function test_provisional_output()
@testset "a cell keeps its last final value while its value is provisional" begin
    answer = Cell(nothing)
    # A value that a task still reads: its default 0, provisional, until the answer.
    value = Cell(@computation (given = answer[]; given === nothing ? (mark_computation_provisional!(); 0) : given))
    doubled = make_final_holding_cell(() -> 2 * value[])
    # A value that never was final shows as it is.
    @test doubled[] == 0 && is_cell_provisional(doubled)
    answer[] = 4
    @test doubled[] == 8 && !is_cell_provisional(doubled)
    # A value that is provisional again keeps the last final one.
    answer[] = nothing
    @test doubled[] == 8 && is_cell_provisional(doubled)
    answer[] = 5
    @test doubled[] == 10 && !is_cell_provisional(doubled)
    # A held value that the check refuses gives way to the provisional value.
    refusing = make_final_holding_cell(() -> 2 * value[]; is_usable = held -> held < 10)
    @test refusing[] == 10
    answer[] = nothing
    @test refusing[] == 0 && is_cell_provisional(refusing)
end
end
