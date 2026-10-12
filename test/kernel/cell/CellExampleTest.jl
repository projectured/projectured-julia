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

"""

function test_cell_example()
@testset "Cell example" begin
    @test sprint(print_cell_example) == _CELL_EXAMPLE_TEXT
    # Each call runs in a new module, so a second call starts from no cells.
    @test sprint(print_cell_example) == _CELL_EXAMPLE_TEXT
end
end
