# Fragment of `CellModule` — the bodies of `unwrap_cell`, `copy_cell_as`,
# `is_computed_cell` and `has_dependent_cells`, which `CellInterface.jl`
# declares. The methods of each generic stand side by side, one for each kind.
# The file also keeps a `Computed` out of the two kinds that can not compute.

unwrap_cell(x) = x isa AbstractCell ? x[] : x

copy_cell_as(c::ReactiveCell{T},  v) where {T} = ReactiveCell{T}(v)
copy_cell_as(c::MutableCell{T},   v) where {T} = MutableCell{T}(v)
copy_cell_as(c::ImmutableCell{T}, v) where {T} = ImmutableCell{T}(v)

is_computed_cell(::AbstractCell) = false
is_computed_cell(c::ReactiveCell) = c.thunk !== nothing

has_dependent_cells(::AbstractCell) = false

function has_dependent_cells(c::ReactiveCell)
    ds = c.dependents
    ds === nothing && return false
    any(reference -> reference.value !== nothing, ds)
end

# Only the reactive kind can compute. A stored kind that kept the marker as its
# value would read back the `Computed` itself and never call the thunk, so the
# two stored kinds throw.
_reject_computation(kind) =
    throw(ArgumentError("$kind can not hold a Computed: only a ReactiveCell " *
                        "computes. To store a function as a value, pass the " *
                        "function itself"))

MutableCell(::Computed)                = _reject_computation("MutableCell")
MutableCell{T}(::Computed)   where {T} = _reject_computation("MutableCell")
ImmutableCell(::Computed)              = _reject_computation("ImmutableCell")
ImmutableCell{T}(::Computed) where {T} = _reject_computation("ImmutableCell")
