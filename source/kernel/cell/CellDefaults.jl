# Fragment of `CellModule` — the bodies of `unwrap_cell`, `get_cell_value_type`,
# `make_similar_cell`, `is_computed_cell`, `get_cell_computation` and
# `has_dependent_cells`, which `CellInterface.jl` declares. The methods of each
# generic stand side by side, one for each kind. The file also keeps a
# `Computation` out of the two kinds that can not compute.

unwrap_cell(x) = x isa AbstractCell ? x[] : x

get_cell_value_type(::AbstractCell{T}) where {T} = T

make_similar_cell(c::ReactiveCell{T},  v) where {T} = ReactiveCell{T}(v)
make_similar_cell(c::MutableCell{T},   v) where {T} = MutableCell{T}(v)
make_similar_cell(c::ImmutableCell{T}, v) where {T} = ImmutableCell{T}(v)

is_computed_cell(::AbstractCell) = false
is_computed_cell(c::ReactiveCell) = c.computation !== nothing

get_cell_computation(::AbstractCell) = nothing
get_cell_computation(c::ReactiveCell) = c.computation

has_dependent_cells(::AbstractCell) = false

function has_dependent_cells(c::ReactiveCell)
    ds = c.dependents
    ds === nothing && return false
    any(reference -> reference.value !== nothing, ds)
end

# Only the reactive kind and the untracked kind can compute. A stored kind that
# kept the marker as its value would read back the `Computation` itself and never
# run it, so the two stored kinds throw.
_reject_computation(kind) =
    throw(ArgumentError("$kind can not hold a Computation: only a ReactiveCell " *
                        "and an UntrackedCell compute. To store a function as a value, pass the " *
                        "function itself"))

MutableCell(::Computation)                = _reject_computation("MutableCell")
MutableCell{T}(::Computation)   where {T} = _reject_computation("MutableCell")
Base.setindex!(c::MutableCell, ::Computation) = _reject_computation("MutableCell")
ImmutableCell(::Computation)              = _reject_computation("ImmutableCell")
ImmutableCell{T}(::Computation) where {T} = _reject_computation("ImmutableCell")
