"""
The walkthrough of the cell layer: the REPL session that `print_cell_example`
prints, line for line.
"""

using Test
using ProjecturedKernelExample: print_cell_example

const _CELL_EXAMPLE_TEXT = """
# Type each line in a REPL after `using ProjecturedKernel.CellModule`.

# A cell holds a value. `c[]` reads it.
julia> price = Cell(10); quantity = Cell(3); price[]
10

# A computation reads other cells. It runs at its first read, not before.
julia> total = Cell(@computation price[] * quantity[]); is_cell_up_to_date(total)
false

julia> total[]
30

# A write makes each cell that read the cell out of date. The next read computes again.
julia> price[] = 12; is_cell_up_to_date(total)
false

julia> total[]
36

# `peek` reads a cell and records no dependency, so the reader does not follow a write.
julia> shown = Cell(@computation peek(price)); shown[]
12

julia> price[] = 20; is_cell_up_to_date(shown)
true

julia> shown[]
12

# A cell can hold a computation in place of a value. A chain of readers follows each write.
julia> quantity[] = @computation div(price[], 4); total[]
100

julia> price[] = 8; total[]
16

# set_cell_computation! gives a computation to a cell that exists. set_cell_value! gives it a value again.
julia> set_cell_computation!(price, () -> 3 * 4); is_computed_cell(price), total[]
(true, 36)

julia> set_cell_value!(price, 8); is_computed_cell(price), total[]
(false, 16)

# A MutableCell records no reader, so a write to it makes no reader out of date.
julia> frames = MutableCell(0); counted = Cell(@computation frames[] + 1); counted[]
1

julia> frames[] = 9; is_cell_up_to_date(counted)
true

# An ImmutableCell can not be written, and neither of these two kinds can hold a computation.
julia> title = ImmutableCell("report"); try title[] = "other" catch exception; typeof(exception) end
MethodError

julia> try MutableCell(@computation 1) catch exception; typeof(exception) end
ArgumentError

# An UntrackedCell computes at each read and records no reader, so its reader keeps its value.
julia> theme = Cell(:light); background = UntrackedCell{Symbol}(@computation theme[]); styled = Cell(@computation string(background[])); styled[]
"light"

julia> theme[] = :dark; styled[], background[]
("light", :dark)

# run_untracked runs a function so that no read inside it records a reader.
julia> snapshot = Cell(@computation run_untracked(() -> price[] + 1)); snapshot[]
9

julia> price[] = 2; is_cell_up_to_date(snapshot)
true

# A computation that reads its own cell is a cycle. The read throws an ordinary exception, so the editor goes on.
julia> loop = Cell(0); loop[] = @computation loop[] + 1; try loop[] catch exception; sprint(showerror, exception) end
"a Cell read itself while it computed"

# A computation made inside run_in_fault_scope keeps the scope. The code that owns the scope takes the faults of its cells.
julia> struct PartScope; faults::Vector{Any}; end

julia> CellModule.record_computation_fault!(scope::PartScope, computation, exception; traceback) = (push!(scope.faults, exception); true); nothing

julia> scope = PartScope([]); part = run_in_fault_scope(() -> Cell(@computation error("no value")), scope); get_fault_scope(get_cell_computation(part)) === scope
true

julia> try part[] catch exception; typeof(exception) end
RecordedFaultException

julia> scope.faults
1-element Vector{Any}:
 ErrorException("no value")

"""

function test_cell_example()
@testset "Cell example" begin
    @test sprint(print_cell_example) == _CELL_EXAMPLE_TEXT
    # Each call runs in a new module, so a second call starts from no cells.
    @test sprint(print_cell_example) == _CELL_EXAMPLE_TEXT
end
end
