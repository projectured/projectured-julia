# Fragment of `LayoutModule`.
#
# The constraint-layout solver **seam**. Defines the plain data interchange types
# (`SolverAnchor`, `SolverRelation`), the abstract `ConstraintSolver`, the
# `solve_constraint_layout` generic function, and a dependency-free
# `FallbackConstraintSolver`.
#
# The real LP-backed solver lives in the opt-in `ProjecturedTulip` package
# (`TulipConstraintSolver`, built on `MathOptInterface` + `Tulip`), which adds a
# `solve_constraint_layout` method to the generic here. This mirrors how
# `GraphLayoutEngine` keeps a pure-Julia `GridEmbedding` in core and lets
# `ProjecturedAdaptagrams` add the heavy native `AdaptagramsLayout` — so core
# `ProjecturedPlatform` stays free of the heavy solver dependency, and a
# `ConstraintLayout` degrades gracefully (children stacked at the origin) when the
# solver package is not loaded.
"""
    SolverAnchor(child, edge)

Plain (cell-free) anchor naming an edge of `child` (1-based, or `0` for the
parent container). `edge ∈ (:left, :right, :top, :bottom, :width, :height,
:centerx, :centery)`. This is the interchange type a projection hands to a
[`ConstraintSolver`](@ref); the editable document-level anchor is
`LayoutAnchor`.
"""
struct SolverAnchor
    child::Int
    edge::Symbol
end

"""
    SolverRelation(terms, op, constant, strength)

Plain (cell-free) relation `Σ coeffᵢ · anchorᵢ (op) constant`. `terms` is a
vector of `(SolverAnchor, coefficient)` pairs, `op ∈ (:(==), :(<=), :(>=))`,
`strength ∈ (:required, :strong, :medium, :weak)`.
"""
struct SolverRelation
    terms::Vector{Tuple{SolverAnchor,Float64}}
    op::Symbol
    constant::Float64
    strength::Symbol
end

"""
    ConstraintSolver

Abstract solver interface. Concrete solvers implement

    solve_constraint_layout(solver, n, intrinsic_w, intrinsic_h, relations,
                            bounding_w, bounding_h) -> Vector{NTuple{4,Int}}

returning one `(x, y, w, h)` `Int` rect per child. The core ships
[`FallbackConstraintSolver`](@ref); `TulipConstraintSolver` (opt-in
`ProjecturedTulip` package) is the real LP solver.
"""
abstract type ConstraintSolver end

"""
    solve_constraint_layout(solver, n, intrinsic_w, intrinsic_h, relations,
                            bounding_w, bounding_h) -> Vector{NTuple{4,Int}}

The solver seam. `n` children with the given intrinsic extents are positioned by
`solver` subject to `relations` (over a parent box `bounding_w × bounding_h`,
its `:left`/`:top` pinned to 0). Returns one rounded `(x, y, w, h)` rect per
child. Implemented by [`FallbackConstraintSolver`](@ref) here and by
`TulipConstraintSolver` in the `ProjecturedTulip` package.
"""
function solve_constraint_layout end

"""
    FallbackConstraintSolver()

Dependency-free fallback: ignores the relations and places every child at the
origin at its intrinsic size. A `ConstraintLayout` projected with this solver is
valid and selectable but not actually constraint-solved — load `ProjecturedTulip`
and pass a `TulipConstraintSolver` for real solving. (Analogous to
`GridEmbedding` vs. the native `AdaptagramsLayout`.)
"""
struct FallbackConstraintSolver <: ConstraintSolver end

function solve_constraint_layout(::FallbackConstraintSolver, n::Int,
                                 intrinsic_w::Vector{Int}, intrinsic_h::Vector{Int},
                                 relations::Vector{SolverRelation},
                                 bounding_w::Int, bounding_h::Int)
    NTuple{4,Int}[(0, 0, intrinsic_w[i], intrinsic_h[i]) for i in 1:n]
end
