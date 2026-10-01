"""
The fault scope of a computation: a computation made inside `run_in_fault_scope`
keeps the scope, and when it throws it hands the fault to that scope. The tests
need only the cell layer.
"""

using Test
using ProjecturedKernel.CellModule

# A scope that keeps what it took. `takes` says whether it takes a fault.
mutable struct FaultScopeProbe
    name::Symbol
    takes::Bool
    faults::Vector{Any}
end
FaultScopeProbe(name::Symbol; takes::Bool = true) = FaultScopeProbe(name, takes, Any[])

function CellModule.record_computation_fault!(scope::FaultScopeProbe, computation,
                                              exception, traceback)
    push!(scope.faults, (computation, exception))
    scope.takes
end

_get_cell_scope(cell::ReactiveCell) = get_fault_scope(cell.computation)

function test_cell_fault_scope()
@testset "the fault scope of a computation" begin

    @testset "a computation made in a scope keeps it" begin
        outer, inner = FaultScopeProbe(:outer), FaultScopeProbe(:inner)
        loose = Cell(@computation 1)
        kept = run_in_fault_scope(outer) do
            here = Cell(@computation 2)
            nested = run_in_fault_scope(() -> Cell(@computation 3), inner)
            after = Cell(@computation 4)
            (here, nested, after)
        end
        @test _get_cell_scope(loose) === nothing
        @test _get_cell_scope(kept[1]) === outer
        @test _get_cell_scope(kept[2]) === inner
        # The outer scope comes back when the inner print returns.
        @test _get_cell_scope(kept[3]) === outer
    end

    @testset "a computation made by a running computation takes its scope" begin
        scope = FaultScopeProbe(:maker)
        maker = run_in_fault_scope(() -> Cell(@computation Cell(@computation 5)), scope)
        made = maker[]
        @test made[] == 5
        @test _get_cell_scope(made) === scope
    end

    @testset "a scope set inside a running computation takes its place" begin
        outer, inner = FaultScopeProbe(:outer), FaultScopeProbe(:inner)
        maker = run_in_fault_scope(outer) do
            Cell(@computation run_in_fault_scope(() -> Cell(@computation 6), inner))
        end
        @test _get_cell_scope(maker[]) === inner
    end

    @testset "the innermost computation that throws hands the fault to its scope" begin
        outer, inner = FaultScopeProbe(:outer), FaultScopeProbe(:inner)
        broken = run_in_fault_scope(() -> Cell(@computation error("broken")), inner)
        reader = run_in_fault_scope(() -> Cell(@computation broken[] + 1), outer)
        thrown = try
            reader[]
            nothing
        catch exception
            exception
        end
        @test thrown isa RecordedFaultException
        @test thrown.scope === inner
        @test thrown.exception isa ErrorException
        @test length(inner.faults) == 1
        # The scope gets the function of the computation, which runs it again.
        computation, _ = inner.faults[1]
        @test_throws ErrorException computation()
        # The reader above sees the recorded fault and records nothing.
        @test isempty(outer.faults)
    end

    @testset "a scope that does not take the fault lets it go on" begin
        outer, inner = FaultScopeProbe(:outer), FaultScopeProbe(:inner; takes = false)
        broken = run_in_fault_scope(() -> Cell(@computation error("broken")), inner)
        reader = run_in_fault_scope(() -> Cell(@computation broken[] + 1), outer)
        thrown = try
            reader[]
            nothing
        catch exception
            exception
        end
        @test thrown isa RecordedFaultException
        @test thrown.scope === outer
        @test length(inner.faults) == 1
        @test length(outer.faults) == 1
    end

    @testset "a computation outside every scope throws as before" begin
        broken = Cell(@computation error("broken"))
        @test_throws ErrorException broken[]
    end

    @testset "an interrupt passes every scope" begin
        scope = FaultScopeProbe(:scope)
        interrupted = run_in_fault_scope(() -> Cell(@computation throw(InterruptException())),
                                         scope)
        @test_throws InterruptException interrupted[]
        @test isempty(scope.faults)
    end

    @testset "an untracked cell hands its fault to its scope" begin
        scope = FaultScopeProbe(:scope)
        untracked = run_in_fault_scope(
            () -> UntrackedCell{Int}(@computation error("broken")), scope)
        @test_throws RecordedFaultException untracked[]
        @test length(scope.faults) == 1
    end

    @testset "a computation given to a cell that exists keeps the scope" begin
        scope = FaultScopeProbe(:scope)
        cell = Cell(1)
        run_in_fault_scope(() -> set_cell_computation!(cell, () -> 2), scope)
        @test cell[] == 2
        @test _get_cell_scope(cell) === scope
    end

    @testset "a computation made in an untracked run takes the scope that runs" begin
        outer = FaultScopeProbe(:outer)
        # A cell made outside every scope, whose computation makes a cell.
        loose = Cell(@computation Cell(@computation 8))
        made = run_in_fault_scope(outer) do
            CellModule.run_untracked(() -> loose[])
        end
        @test made[] == 8
        @test _get_cell_scope(made) === nothing
    end

    @testset "the value comes back when the computation works" begin
        scope = FaultScopeProbe(:scope)
        is_broken = Cell(true)
        cell = run_in_fault_scope(
            () -> Cell(@computation is_broken[] ? error("broken") : 7), scope)
        @test_throws RecordedFaultException cell[]
        is_broken[] = false
        @test cell[] == 7
    end
end
end
