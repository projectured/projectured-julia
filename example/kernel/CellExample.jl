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
    "# set_cell_computation! gives a computation to a cell that exists. set_cell_value! gives it a value again.",
    "set_cell_computation!(price, () -> 3 * 4); is_computed_cell(price), total[]",
    "set_cell_value!(price, 8); is_computed_cell(price), total[]",
    "# A MutableCell records no reader, so a write to it makes no reader out of date.",
    "frames = MutableCell(0); counted = Cell(@computation frames[] + 1); counted[]",
    "frames[] = 9; is_cell_up_to_date(counted)",
    "# An ImmutableCell can not be written, and neither of these two kinds can hold a computation.",
    "title = ImmutableCell(\"report\"); try title[] = \"other\" catch exception; typeof(exception) end",
    "try MutableCell(@computation 1) catch exception; typeof(exception) end",
    "# An UntrackedCell computes at each read and records no reader, so its reader keeps its value.",
    "theme = Cell(:light); background = UntrackedCell{Symbol}(@computation theme[]); styled = Cell(@computation string(background[])); styled[]",
    "theme[] = :dark; styled[], background[]",
    "# run_without_cell_tracking runs a function so that no read inside it records a reader.",
    "snapshot = Cell(@computation run_without_cell_tracking(() -> price[] + 1)); snapshot[]",
    "price[] = 2; is_cell_up_to_date(snapshot)",
    "# A computation that reads its own cell is a cycle. The read throws an ordinary exception, so the editor goes on.",
    "loop = Cell(0); loop[] = @computation loop[] + 1; try loop[] catch exception; sprint(showerror, exception) end",
    "# A computation made inside run_in_cell_fault_scope keeps the scope. The code that owns the scope takes the faults of its cells.",
    "struct PartScope; faults::Vector{Any}; end",
    "CellModule.record_cell_fault!(scope::PartScope, computation, exception; traceback) = (push!(scope.faults, exception); true); nothing",
    "scope = PartScope([]); part = run_in_cell_fault_scope(() -> Cell(@computation error(\"no value\")), scope); get_cell_fault_scope(part) === scope",
    "try part[] catch exception; typeof(exception) end",
    "scope.faults",
]

"""
    print_cell_example(io::IO = stdout)

Print a REPL session that shows the cell layer: a cell that holds a value, a
computation that reads cells, a write that makes the readers out of date, a read
with `peek` that records no dependency, a chain of computations, a new computation
of a cell, the other cell kinds, `run_without_cell_tracking`, a cycle, and a fault scope.

Each line runs as it prints, so the value under a line is the value that the line
gives. Each call adds one method of `record_cell_fault!`, for the scope type
of its own session, and the method stays while the process runs. To try the lines,
type them in a REPL after `using ProjecturedKernel.CellModule`.

# Example

    julia> using ProjecturedKernelExample

    julia> print_cell_example()

See also the guide `kernel/cell`.
"""
print_cell_example(io::IO = stdout) = _print_walkthrough(io, CellModule, _CELL_WALKTHROUGH)
