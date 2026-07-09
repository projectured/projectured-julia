# Fragment of `CellModule` — the read-only, zero-cost cell kind.

"""
    ImmutableCell{T}

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

function Base.show(io::IO, c::ImmutableCell)
    print(io, "ImmutableCell(")
    show(io, c.value)
    print(io, ")")
end
