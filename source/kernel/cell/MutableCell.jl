# Fragment of `CellModule` — the plain mutable, non-reactive cell kind.

# Julia generates the constructor `MutableCell(value::T) where T`, which infers `T`
# from the value. A second definition by hand overwrites it and stops the
# precompilation.
"""
    MutableCell{T}

A box that holds a value and records no reader, so a write invalidates nothing.

Use it for state that changes often and that nothing computes from: a counter, a
scroll offset kept for one frame, a cursor position a renderer reads once per
draw. It costs almost nothing to read or write, and nothing recomputes because
of it. When something must follow the value, use a reactive cell instead.

# Example

    frames = MutableCell(0)
    frames[] += 1

See also `ReactiveCell`, whose write invalidates its readers, and
`ImmutableCell`, which can not be written.

`MutableCell(v)` infers `T` from `v`, as `Ref(v)` does. Write `MutableCell{T}(v)`
for a wider type.
"""
mutable struct MutableCell{T} <: AbstractCell{T}
    value::T
end

Base.getindex(c::MutableCell) = c.value
Base.setindex!(c::MutableCell, value) = (c.value = value)

is_cell_up_to_date(::MutableCell) = true
Base.peek(c::MutableCell) = c[]

function Base.show(io::IO, c::MutableCell)
    print(io, "MutableCell(")
    show(io, c.value)
    print(io, ")")
end
