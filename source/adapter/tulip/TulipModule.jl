"""
    TulipModule

The LP-backed constraint-layout solver for ProjecturEd: a `TulipConstraintSolver`
that adds a `solve_constraint_layout` method to the seam defined in
`ProjecturedPlatform.LayoutModule`. Opt-in so core `ProjecturedPlatform`
carries no `Tulip` / `MathOptInterface` dependency — exactly how
`ProjecturedAdaptagrams` adds the native `AdaptagramsLayout` to the
`GraphLayoutEngine` seam without core depending on the native shim.

Usage:

    using Projectured, ProjecturedPlatform, ProjecturedTulip
    proj = ConstraintLayoutToGraphicsCanvas(solver = TulipConstraintSolver())

A UI layout problem is mapped onto a linear program by **goal programming**:

  * **Hard** (`:required`) relations become LP equality/inequality rows.
  * **Soft** (`:strong`/`:medium`/`:weak`) relations introduce non-negative
    slack variables and a strength-weighted penalty in the objective, so the
    solver minimizes a weighted sum of constraint violations (Cassowary's
    prioritized least-violation behaviour, approximated with one LP solve).

Per-child intrinsic sizes enter as **weak stay constraints** so the system stays
determined when relations under-constrain a child, while any explicit relation
easily overrides them.
"""
module TulipModule

using ..PlatformModule
import Tulip
import MathOptInterface as MOI

# Imported to extend: this module adds a method to each of these.
import ..LayoutModule: solve_constraint_layout

export TulipConstraintSolver

include("TulipConstraintSolver.jl")

end # module TulipModule
