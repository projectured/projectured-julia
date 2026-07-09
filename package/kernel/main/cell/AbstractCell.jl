# Fragment of `CellModule` — the base type of the cell kinds plus the cross-kind
# protocol fallbacks, included before the concrete kinds, which subtype it.

"""
    AbstractCell{T}

Base type of the cell kinds. `T` is the type of the held value. The shared
protocol is the read `c[]`; everything else (writes, thunks, dependency
tracking) is kind-specific. See [`ReactiveCell`](@ref), [`MutableCell`](@ref),
[`ImmutableCell`](@ref).
"""
abstract type AbstractCell{T} end

# Cross-kind protocol fallbacks. The non-reactive kinds are trivially always up
# to date, and `peek` (the untracked read) is a plain read for them. The
# `ReactiveCell` overrides live in ReactiveCell.jl. (`c[]` here dispatches to each
# kind's `getindex`, defined in the kind files included after this one.)
is_up_to_date(c::AbstractCell) = true
Base.peek(c::AbstractCell) = c[]
