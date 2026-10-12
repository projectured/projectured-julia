# The walkthrough of the cell layer.

const _CELL_WALKTHROUGH = [
    "# A cell holds a value. `c[]` reads it.",
    "price = Cell(10); quantity = Cell(3); price[]",
    "# A computation reads other cells. It runs at its first read, not before.",
    "total = Cell(@computation price[] * quantity[]); is_cell_up_to_date(total)",
    "total[]",
    "# A write makes each cell that read the cell out of date. The next read computes again.",
    "price[] = 12; is_cell_up_to_date(total)",
    "total[]",
    "# `peek` reads a cell and records no dependency, so the reader does not follow a write.",
    "shown = Cell(@computation peek(price)); shown[]",
    "price[] = 20; is_cell_up_to_date(shown)",
    "shown[]",
    "# A cell can hold a computation in place of a value. A chain of readers follows each write.",
    "quantity[] = @computation div(price[], 4); total[]",
    "price[] = 8; total[]",
]

"""
    print_cell_example(io::IO = stdout)

Print a REPL session that shows the cell layer: a cell that holds a value, a
computation that reads cells, a write that makes the readers out of date, a read
with `peek` that records no dependency, and a chain of computations.

Each line runs as it prints, so the value under a line is the value that the line
gives. To try the lines, type them in a REPL after `using ProjecturedKernel.CellModule`.

# Example

    julia> using ProjecturedKernelExample

    julia> print_cell_example()

See also the guide `kernel/cell`.
"""
print_cell_example(io::IO = stdout) = _print_walkthrough(io, CellModule, _CELL_WALKTHROUGH)
