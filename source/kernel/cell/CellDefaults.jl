# Fragment of `CellModule` — what needs every cell kind in scope, and so comes
# after all three: the bodies for the cell contract's utility generics declared in
# `CellInterface.jl` (the `unwrap_cell` default, and `copy_cell_as`, which each
# kind answers for itself — a cell's kind lives in its type, so cloning reads it
# back off the cell already there), `is_computed_cell`, which asks the kind whether
# it computes, and the guards that keep a `Computed` in the one kind that can run
# it.

unwrap_cell(x) = x isa AbstractCell ? x[] : x

copy_cell_as(c::ReactiveCell{T},  v) where {T} = ReactiveCell{T}(v)
copy_cell_as(c::MutableCell{T},   v) where {T} = MutableCell{T}(v)
copy_cell_as(c::ImmutableCell{T}, v) where {T} = ImmutableCell{T}(v)

"""
    is_computed_cell(cell) -> Bool

Whether a cell computes its value or stores one.

Use it to tell a derived value from a written one before copying, printing or
freezing a document: the value of a computed cell is one moment of a
computation, and a cell that stores that moment stops following what the
computation reads.

# Example

    is_computed_cell(Cell(3))                       # false
    is_computed_cell(ComputedCell(() -> 3))         # true

See also `set_cell_function!`, which makes a cell compute, and `copy_cell_as`.

`true` when `cell` computes its value with a thunk, and `false` when it stores
the value it was given. Only the reactive kind can compute, so the stored kinds
always answer `false`.

A copy asks this, because the value of a computed cell is one moment of its
computation: a cell that stores that value does not follow what the thunk reads.
"""
is_computed_cell(::AbstractCell) = false
is_computed_cell(c::ReactiveCell) = getfield(c, :thunk) !== nothing

# Only the reactive kind recomputes, so only it can hold a computation. Refuse the
# marker in the other two rather than storing it as an ordinary value, which would
# read back as the `Computed` wrapper itself and never call anything.
_reject_computation(kind) =
    error("$kind cannot hold a Computed — a computation needs a ReactiveCell; " *
          "for a plain value, pass the function itself")

MutableCell(::Computed)                = _reject_computation("MutableCell")
MutableCell{T}(::Computed)   where {T} = _reject_computation("MutableCell")
ImmutableCell(::Computed)              = _reject_computation("ImmutableCell")
ImmutableCell{T}(::Computed) where {T} = _reject_computation("ImmutableCell")
