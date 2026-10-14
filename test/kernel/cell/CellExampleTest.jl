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
julia> total = Cell(@computation price[] * quantity[]); is_cell_valid(total)
false

julia> total[]
30

# A write makes each cell that read the cell invalid. The next read computes again.
julia> price[] = 12; is_cell_valid(total)
false

julia> total[]
36

# A write of the same plain value, such as a number or a string, invalidates nothing.
julia> price[] = 12; is_cell_valid(total)
true

# invalidate_cell! makes the readers compute again with no write.
julia> invalidate_cell!(price); is_cell_valid(total)
false

# A computation that gives the same plain value as before stops the walk: the cells below it keep their values.
julia> items = Cell(2); is_odd = Cell(@computation isodd(items[])); runs = Ref(0); label = Cell(@computation (runs[] += 1; is_odd[] ? "odd" : "even")); label[], runs[]
("even", 1)

julia> items[] = 4; label[], runs[]
("even", 1)

julia> items[] = 5; label[], runs[]
("odd", 2)

# `peek` reads a cell and records no dependency, so the reader does not follow a write.
julia> shown = Cell(@computation peek(price)); shown[]
12

julia> price[] = 20; is_cell_valid(shown)
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

# A MutableCell records no reader, so a write to it makes no reader invalid.
julia> frames = MutableCell(0); counted = Cell(@computation frames[] + 1); counted[]
1

julia> frames[] = 9; is_cell_valid(counted)
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

# run_without_cell_tracking runs a function so that no read inside it records a reader.
julia> snapshot = Cell(@computation run_without_cell_tracking(() -> price[] + 1)); snapshot[]
9

julia> price[] = 2; is_cell_valid(snapshot)
true

# A computation that reads its own cell is a cycle. The read throws an ordinary exception, so the editor goes on.
julia> loop = Cell(0); loop[] = @computation loop[] + 1; try loop[] catch exception; sprint(showerror, exception) end
"a Cell read itself while it computed"

# A computation made inside run_in_cell_fault_scope keeps the scope. The code that owns the scope takes the faults of its cells.
julia> struct PartScope; faults::Vector{Any}; end

julia> CellModule.record_cell_fault!(scope::PartScope, computation, exception; traceback) = (push!(scope.faults, exception); true); nothing

julia> scope = PartScope([]); part = run_in_cell_fault_scope(() -> Cell(@computation error("no value")), scope); get_cell_fault_scope(part) === scope
true

julia> try part[] catch exception; typeof(exception) end
RecordedCellFaultException

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
