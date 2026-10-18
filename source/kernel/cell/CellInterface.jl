# Fragment of `CellModule` — the cell **contract**: the base type of the cell
# kinds and the generics that form their protocol. Included before the kinds,
# which subtype it and implement it. Nothing here carries a body. The read, the
# untracked read and `is_cell_valid` live in the file of each kind, the method of
# `invalidate_cell!` for a reactive cell lives in `ReactiveCell.jl`, and the bodies
# of the other generics live in the sibling `CellDefaults.jl`.

"""
    AbstractCell{T}

What every kind of cell is: a box that holds one value, of type `T`.

Use it to say that something holds a value without saying how it holds it. A
write to a reactive cell invalidates the cells that read it, a write to a
mutable one invalidates nothing, and an immutable one can not be written. Code
that only reads takes any of them.

# Example

    show_value(cell::AbstractCell) = println(cell[])

Every kind has the read `c[]`, the untracked read `Base.peek(c)`, which records
no dependency, and [`is_cell_valid`](@ref). The writes, the computations
and the dependency tracking belong to each kind.

See also `ReactiveCell`, `MutableCell`, `ImmutableCell` and `UntrackedCell`, the
four kinds, and `unwrap_cell`, for a slot that may hold a value instead of a cell.
"""
abstract type AbstractCell{T} end

"""
    is_cell_valid(cell) -> Bool

Whether a read returns the value that the cell holds, or first brings it up to
date: by a computation, or, for a reactive cell below a write, by a check of the
cells that it read, which finds the value up to date when none of them changed.

Use it to tell a value that is ready from one that must be worked out: before a
measurement of what a read costs, or in a test that asks whether a write
reached the cells that depend on it.

# Example

    total = Cell(@computation length(rows[]))
    is_cell_valid(total)       # false until the first read
    total[]
    is_cell_valid(total)       # true

A kind that holds its value, and not a computation, is always valid. An
`UntrackedCell` answers `true` too, although each read of a computed one runs its
computation.

See also `set_cell_computation!`, `invalidate_cell!` and `ReactiveCell`.
"""
function is_cell_valid end

"""
    is_cell_provisional(cell) -> Bool

Whether the value of `cell` is provisional: valid now, but a newer value comes
later, such as the default of a value that a task still reads. A computation that
reads a provisional cell is provisional itself, so the flag goes up through every
computation that the value reaches, and a computation that computes again from
final values only is final. A write of a value is final.

Use it where a drawing chooses what to show while a value comes, such as the last
final rows of a table, or a mark that a sort is not done. Inside a computation the
call records a dependency on `cell`, so the computation computes again when the
flag changes, and the call does not make the computation provisional: whether a
value is provisional is a final fact. The call brings `cell` up to date first, so
it throws the exception of a computation that fails, as a read does. A failure
that a provisional value caused is provisional too: a computation that catches it
is provisional.

# Example

    record = Cell(@computation (mark_computation_provisional!(); "unknown"))
    label = Cell(@computation "configuration: " * record[])
    label[]                          # "configuration: unknown"
    is_cell_provisional(label)       # true
    record[] = "Fifo"
    label[]                          # "configuration: Fifo"
    is_cell_provisional(label)       # false

A read that records no reader takes no part: `peek`, `run_without_cell_tracking`,
an `UntrackedCell` and a read on another task do not make a computation
provisional. Only the reactive kind can be provisional, so the other kinds always
return `false`.

See also `mark_computation_provisional!`, and `is_cell_valid`.
"""
function is_cell_provisional end

"""
    invalidate_cell!(cell) -> nothing

Make every cell that reads `cell` invalid, with no write, and the cells that
read those maybe invalid: each of them computes again only when a cell that it
read gives a new value. A cell that holds a computation becomes invalid too, so
its next read computes again. A cell that holds a value keeps it.

Use it after a change that a write does not show, such as a change inside a
mutable value that the cell holds. A write of plain data that is `===` to the
value of the cell invalidates nothing, so this is also the way to make the
readers compute again then. Call it where a write could stand, never inside a
computation, because one task writes and reads a set of cells, in phases.

# Example

    rows = Cell([1, 2])
    total = Cell(@computation sum(rows[]))
    total[]                    # 3
    push!(peek(rows), 3)
    invalidate_cell!(rows)
    total[]                    # 6

A `MutableCell`, an `ImmutableCell` and an `UntrackedCell` record no reader, so the
call does nothing for them.

See also `is_cell_valid`, and `c[] = value`, the write that invalidates the readers.
"""
function invalidate_cell! end

"""
    unwrap_cell(x) -> value

Read a value that may be wrapped in a cell, or may be the value itself.

Use it wherever a field, a slot or an argument holds either: a struct can store
some fields as cells and some as plain values, and this reads both without
asking which. The read is an ordinary one, so inside a computation
it makes the computation depend on the cell.

# Example

    width(box) = unwrap_cell(box.width) + unwrap_cell(box.padding)

See also `peek`, for a read that depends on nothing, and `AbstractCell`.
"""
function unwrap_cell end

"""
    get_cell_value_type(cell) -> Type

The type of the value that a cell holds: `T` for a cell of the type
`AbstractCell{T}`.

Use it to ask whether a value fits a cell before you write it, or to bind a type
parameter from a cell. The answer comes from the type of the cell, so it reads no
value, and no computation depends on the cell because of it.

# Example

    get_cell_value_type(ImmutableCell{Int}(1))      # Int64
    get_cell_value_type(Cell(1))                    # Any

A `Cell` is a `ReactiveCell{Any}`, so its value type is `Any`.

See also `unwrap_cell`, which reads the value.
"""
function get_cell_value_type end

"""
    make_similar_cell(c::AbstractCell, v) -> AbstractCell

Make a new cell like this one, holding another value.

Use it to copy a struct of cells: each field keeps the kind of cell it had, so a
reactive field stays reactive and a stored field stays stored, and the code that
copies does not test which was which.

# Example

    copied = make_similar_cell(getfield(original, :width), 120)

The new cell has the kind and the declared value type of `c`.

See also `AbstractCell` and `is_computed_cell`, which says whether the value
came from a computation.
"""
function make_similar_cell end

"""
    is_computed_cell(cell) -> Bool

Whether a cell computes its value or stores one.

Use it to tell a derived value from a written one before you copy, print or
freeze a struct of cells: the value of a computed cell is one moment of a
computation, and a cell that stores that moment stops following what the
computation reads.

# Example

    is_computed_cell(Cell(3))                       # false
    is_computed_cell(Cell(@computation 3))          # true

Only the reactive kind and the untracked kind can compute, so the other kinds
always return `false`.

See also `set_cell_computation!`, which makes a cell compute, and `make_similar_cell`.
"""
function is_computed_cell end

"""
    get_cell_computation(cell) -> Function or nothing

The computation that `cell` computes its value with, or `nothing` when it holds
a value.

Use it to put a computation around the one that a cell has, so a caller acts on
each value that the cell makes. The caller gives the new computation with
`set_cell_computation!`.

# Example

    inner = get_cell_computation(cell)
    set_cell_computation!(cell, () -> inspect(inner()))

Only the reactive kind keeps a computation that a caller can put another one
around, so the other kinds always return `nothing`.

See also `is_computed_cell`.
"""
function get_cell_computation end

"""
    has_dependent_cells(cell) -> Bool

Whether a live computed cell reads `cell`.

Use it to skip work that nothing shows: a producer that fills a cell can call it
first, and do nothing when no computation reads the cell.

# Example

    status = Cell("idle")
    has_dependent_cells(status)            # false
    shown = Cell(@computation uppercase(status[]))
    shown[]
    has_dependent_cells(status)            # true

A reactive cell holds its readers through a `WeakRef`. A reader that nothing
else holds still counts until the collector sweeps it, so the answer can stay
`true` for a short time after the last reader goes. That is the safe error: the
caller can do work that nobody needs, but it never skips work that a reader
needs. Only the reactive kind records readers, so the other kinds always return
`false`.

See also `is_cell_valid`, and `peek`, a read that records no reader.
"""
function has_dependent_cells end

"""
    record_cell_fault!(scope, computation, exception; traceback) -> Bool

Hand the fault of a computation to the scope that the computation belongs to, and
answer whether the scope took it.

Use it as the seam of a scope: the code that owns a scope adds a method for the type
of its scope, which keeps the fault and shows it later. The fallback takes nothing
and answers `false`.

The computation calls it once, inside its catch, with its own function, which takes
no argument and computes the value again, the exception and its traceback. It runs
inside a computation, so a method must not write a cell. It can write a collector
that no cell depends on and that no computation reads. A scope that takes the fault
answers `true`, and the computation then throws a
[`RecordedCellFaultException`](@ref), so no scope above records the fault again. A
scope that can not show the fault answers `false`, and the exception goes on as it
is, to the next scope up.

# Example

    function CellModule.record_cell_fault!(scope::PartScope, computation,
                                                  exception; traceback)
        push!(scope.faults, exception)
        true
    end

See also [`run_in_cell_fault_scope`](@ref).
"""
function record_cell_fault! end
