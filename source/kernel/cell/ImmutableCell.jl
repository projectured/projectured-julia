# Fragment of `CellModule` — the read-only, zero-cost cell kind.

"""
    ImmutableCell{T}

A box that holds one value and can never be written.

Use it for a document that is finished: a snapshot to serialize, a page to
export, a value a projection may read but nothing may change. It is free, since
an immutable field of a known type lives inside the thing that holds it.

# Example

    frozen = ImmutableCell("the title")
    frozen[]                 # reads
    frozen[] = "other"       # a MethodError, by contract

See also `MutableCell`, which can be written, and `ReactiveCell`, which is
written and tells its readers.

A plain immutable wrapper: `c[]` reads; there is no write (`c[] = v` is a
`MethodError`, which is the contract). Zero-cost: an immutable struct with a
concrete field type inlines into its parent. `ImmutableCell(v)` infers
`T = typeof(v)`; pass `ImmutableCell{T}(v)` for a wider field type.
"""
# NOTE: as with MutableCell, the `ImmutableCell(v)` ctor is auto-generated.
struct ImmutableCell{T} <: AbstractCell{T}
    value::T
end

# Read-only: `c[]` reads; there is deliberately no `setindex!` (a write is a
# `MethodError`, which is the contract).
Base.getindex(c::ImmutableCell) = c.value

# The value is held outright: nothing can be stale, and an untracked read is the
# plain read (there is no dependency to register in the first place).
is_cell_up_to_date(::ImmutableCell) = true
Base.peek(c::ImmutableCell) = c[]

function Base.show(io::IO, c::ImmutableCell)
    print(io, "ImmutableCell(")
    show(io, c.value)
    print(io, ")")
end
