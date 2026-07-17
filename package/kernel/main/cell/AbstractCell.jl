# Fragment of `CellModule` — the cell **contract**: the base type of the cell
# kinds and the generic they answer. Included before the kinds, which subtype it
# and implement it.

"""
    AbstractCell{T}

Base type of the cell kinds. `T` is the type of the held value. The shared
protocol is the read `c[]`, the untracked read `Base.peek(c)` (a sample that
registers no dependency), and [`is_cell_up_to_date`](@ref); everything else (writes,
thunks, dependency tracking) is kind-specific. See [`ReactiveCell`](@ref),
[`MutableCell`](@ref), [`ImmutableCell`](@ref).
"""
abstract type AbstractCell{T} end

"""
    is_cell_up_to_date(cell) -> Bool

Whether `cell` can be read without recomputing anything. A kind that holds its
value outright is trivially up to date; a kind that holds a computed thunk
answers with the validity of its cache.
"""
function is_cell_up_to_date end
