# Fragment of `CellModule` — the kind that computes at each read and records no reader.

"""
    UntrackedCell{T}

A cell that runs its computation at each read. It keeps no value and records no
reader, and no read inside its computation records one, because the computation
runs with `run_untracked`. So nothing depends on an untracked cell, and a change
of what its computation reads reaches no computation that read it.

Use it for a value that something else owns, when one place decides when the
readers compute again: a style field of a projection that reads its theme, where
the whole view prints again when the theme changes. When the readers must follow
the value on their own, use a reactive cell instead.

# Example

    theme = Cell(:light)
    background = UntrackedCell{Symbol}(@computation theme[])
    shown = Cell(@computation string(background[]))
    shown[]                    # "light"
    theme[] = :dark
    shown[]                    # still "light": `shown` recorded no edge
    background[]               # :dark, computed at this read

A value that is not a `Computation` makes a constant: `UntrackedCell{Int}(3)`
reads `3`, and it is what a struct of cells stores for a field that its
constructor got as a plain value. There is no `setindex!`: a write is a
`MethodError`, as for an `ImmutableCell`.

See also `ReactiveCell`, which keeps its value and records its readers, and
`ImmutableCell`, which holds one value.
"""
struct UntrackedCell{T} <: AbstractCell{T}
    computation::Function
    UntrackedCell{T}(marker::Computation) where {T} = new{T}(marker.computation)
    UntrackedCell{T}(value) where {T} = new{T}(Returns(convert(T, value)))
end

UntrackedCell(marker::Computation) = UntrackedCell{Any}(marker)
UntrackedCell(value::T) where {T} = UntrackedCell{T}(value)

Base.getindex(c::UntrackedCell{T}) where {T} = run_untracked(c.computation)::T

is_cell_up_to_date(::UntrackedCell) = true
Base.peek(c::UntrackedCell) = c[]

is_computed_cell(c::UntrackedCell) = !(c.computation isa Returns)
copy_cell_as(::UntrackedCell{T}, v) where {T} = UntrackedCell{T}(v)

function Base.show(io::IO, c::UntrackedCell{T}) where {T}
    if c.computation isa Returns
        print(io, "UntrackedCell{", T, "}(")
        show(io, c.computation.value)
        print(io, ")")
    else
        print(io, "UntrackedCell{", T, "}(computation)")
    end
end
