# Fragment of `CellModule` — the read-only, zero-cost cell kind.

# Julia generates the constructor `ImmutableCell(value::T) where T`, which infers
# `T` from the value. A second definition by hand overwrites it and stops the
# precompilation.
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

See also `MutableCell`, which can be written, and `ReactiveCell`, whose write
invalidates its readers.

`ImmutableCell(v)` infers `T` from `v`. Write `ImmutableCell{T}(v)` for a wider
type.
"""
struct ImmutableCell{T} <: AbstractCell{T}
    value::T
end

# There is no `setindex!`: a write is a `MethodError`, and that is the contract.
Base.getindex(c::ImmutableCell) = c.value

is_cell_up_to_date(::ImmutableCell) = true
Base.peek(c::ImmutableCell) = c[]

function Base.show(io::IO, c::ImmutableCell)
    print(io, "ImmutableCell(")
    show(io, c.value)
    print(io, ")")
end
