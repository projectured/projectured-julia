"""
    ConstraintSolverModule

Pure constraint-layout solver. Knows nothing about reactive cells, projections,
or graphics — it takes plain numbers and returns plain numbers, exactly like
`allocate_axis` does for the flex layouts. This keeps the solver dependency
(`Tulip` via `MathOptInterface`) isolated and unit-testable.

A UI layout problem is mapped onto a linear program by **goal programming**:

  * **Hard** (`:required`) relations become LP equality/inequality rows.
  * **Soft** (`:strong`/`:medium`/`:weak`) relations introduce non-negative
    slack variables and a weighted penalty in the objective, so the solver
    minimizes a strength-weighted sum of constraint violations. This reproduces
    Cassowary's prioritized least-violation behaviour with a single LP solve
    (the weighted approximation, not exact lexicographic strengths).

Per-child intrinsic sizes enter as **weak stay constraints** (`width ==
intrinsic`, `height == intrinsic`, plus a weaker `left == 0` / `top == 0`) so
the system stays fully determined even when relations under-constrain a child,
while any explicit relation easily overrides them.
"""
module ConstraintSolverModule

import Tulip
import MathOptInterface as MOI

export SolverAnchor, SolverRelation, solve_constraint_layout, DEFAULT_OPTIMIZER

"""
    DEFAULT_OPTIMIZER

The optimizer factory used by [`solve_constraint_layout`](@ref) when none is
passed. `Tulip.Optimizer` is a pure-Julia interior-point LP solver (no native
binary). Swap to `HiGHS.Optimizer` to benchmark — the calling code is written
against the solver-agnostic `MathOptInterface`, so it is a one-field change.
"""
const DEFAULT_OPTIMIZER = Tulip.Optimizer

# Strength → objective weight. Well-separated magnitudes so a higher strength
# always dominates any number of lower-strength constraints in practice. The
# weak `STAY` weight is the lowest, so an explicit relation always wins over the
# intrinsic-size / origin stays.
const STAY_WEIGHT = 1.0

function _strength_weight(strength::Symbol)
    strength === :weak   ? 1.0e2 :
    strength === :medium ? 1.0e4 :
    strength === :strong ? 1.0e6 :
    error("ConstraintSolver: unknown strength $(strength)")
end

"""
    SolverAnchor(child, edge)

Plain (cell-free) anchor naming an edge of `child` (1-based, or `0` for the
parent container). `edge ∈ (:left, :right, :top, :bottom, :width, :height,
:centerx, :centery)`.
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

# Affine expansion of one anchor into LP terms over the per-child variables,
# plus a constant contribution (used for parent edges and derived `:centerx`
# etc.). `L`,`T`,`W`,`H` are the per-child variable-index vectors.
function _anchor_affine(a::SolverAnchor, n::Int, bw::Float64, bh::Float64,
                        L, T, W, H)
    if a.child == 0
        c = a.edge === :left    ? 0.0 :
            a.edge === :top     ? 0.0 :
            a.edge === :width   ? bw  :
            a.edge === :right   ? bw  :
            a.edge === :height  ? bh  :
            a.edge === :bottom  ? bh  :
            a.edge === :centerx ? bw / 2 :
            a.edge === :centery ? bh / 2 :
            error("ConstraintSolver: unknown parent edge $(a.edge)")
        return (Tuple{MOI.VariableIndex,Float64}[], c)
    end
    i = a.child
    (1 <= i <= n) || error("ConstraintSolver: child index $(i) out of range 1:$(n)")
    terms =
        a.edge === :left    ? [(L[i], 1.0)] :
        a.edge === :top     ? [(T[i], 1.0)] :
        a.edge === :width   ? [(W[i], 1.0)] :
        a.edge === :height  ? [(H[i], 1.0)] :
        a.edge === :right   ? [(L[i], 1.0), (W[i], 1.0)] :
        a.edge === :bottom  ? [(T[i], 1.0), (H[i], 1.0)] :
        a.edge === :centerx ? [(L[i], 1.0), (W[i], 0.5)] :
        a.edge === :centery ? [(T[i], 1.0), (H[i], 0.5)] :
        error("ConstraintSolver: unknown edge $(a.edge)")
    (Tuple{MOI.VariableIndex,Float64}[t for t in terms], 0.0)
end

# Build the LP terms for the LHS `Σ coeffₖ · anchorₖ` and accumulate the
# constant part (parent / derived contributions). Returns `(terms, const)`.
function _relation_affine(rel::SolverRelation, n::Int, bw::Float64, bh::Float64,
                          L, T, W, H)
    terms = MOI.ScalarAffineTerm{Float64}[]
    constant = 0.0
    for (a, coeff) in rel.terms
        (av, ac) = _anchor_affine(a, n, bw, bh, L, T, W, H)
        for (v, c) in av
            push!(terms, MOI.ScalarAffineTerm(coeff * c, v))
        end
        constant += coeff * ac
    end
    (terms, constant)
end

"""
    solve_constraint_layout(n, intrinsic_w, intrinsic_h, relations,
                            bounding_w, bounding_h;
                            optimizer=DEFAULT_OPTIMIZER, contain=false)
        -> Vector{NTuple{4,Int}}

Pure solve. Builds one MOI model with per-child `left/top/width/height`
variables (parent edges are fixed constants `0,0,bounding_w,bounding_h`),
weak stay constraints toward the intrinsic sizes / origin, and one LP row per
relation (soft relations add slack variables and weighted objective terms).

Returns one `(x, y, w, h)` `Int` rect per child (rounded). On an infeasible
system or a solver failure it logs and returns the **intrinsic fallback**
layout (every child at the origin at its intrinsic size), so the editor never
crashes on a bad constraint set.

`contain=true` adds hard `left ≥ 0`, `top ≥ 0`, `right ≤ bounding_w`,
`bottom ≤ bounding_h` bounds (only meaningful when the bounding dims are > 0).
"""
function solve_constraint_layout(n::Int,
                                 intrinsic_w::Vector{Int}, intrinsic_h::Vector{Int},
                                 relations::Vector{SolverRelation},
                                 bounding_w::Int, bounding_h::Int;
                                 optimizer=DEFAULT_OPTIMIZER, contain::Bool=false)
    n == 0 && return NTuple{4,Int}[]

    fallback() = NTuple{4,Int}[(0, 0, intrinsic_w[i], intrinsic_h[i]) for i in 1:n]

    try
        bw = Float64(bounding_w)
        bh = Float64(bounding_h)

        model = optimizer()
        MOI.set(model, MOI.Silent(), true)

        # Per-child variables.
        L = MOI.add_variables(model, n)
        T = MOI.add_variables(model, n)
        W = MOI.add_variables(model, n)
        H = MOI.add_variables(model, n)

        # Sizes are non-negative.
        for i in 1:n
            MOI.add_constraint(model, W[i], MOI.GreaterThan(0.0))
            MOI.add_constraint(model, H[i], MOI.GreaterThan(0.0))
        end

        objective = MOI.ScalarAffineTerm{Float64}[]

        # Add one soft equality `Σ a·v == rhs` penalized at `weight`, via slack
        # variables sp,sn ≥ 0:  Σ a·v − sp + sn == rhs ;  objective += weight·(sp+sn).
        function soft_equal!(terms, rhs, weight)
            sp = MOI.add_variable(model)
            sn = MOI.add_variable(model)
            MOI.add_constraint(model, sp, MOI.GreaterThan(0.0))
            MOI.add_constraint(model, sn, MOI.GreaterThan(0.0))
            f = MOI.ScalarAffineFunction(
                vcat(terms,
                     MOI.ScalarAffineTerm(-1.0, sp),
                     MOI.ScalarAffineTerm(1.0, sn)),
                0.0)
            MOI.add_constraint(model, f, MOI.EqualTo(rhs))
            push!(objective, MOI.ScalarAffineTerm(weight, sp))
            push!(objective, MOI.ScalarAffineTerm(weight, sn))
            return
        end

        # Weak stay constraints: keep the system determined.
        for i in 1:n
            soft_equal!([MOI.ScalarAffineTerm(1.0, W[i])], Float64(intrinsic_w[i]), STAY_WEIGHT)
            soft_equal!([MOI.ScalarAffineTerm(1.0, H[i])], Float64(intrinsic_h[i]), STAY_WEIGHT)
            # Origin stays are weaker still so any positioning relation wins.
            soft_equal!([MOI.ScalarAffineTerm(1.0, L[i])], 0.0, STAY_WEIGHT * 0.1)
            soft_equal!([MOI.ScalarAffineTerm(1.0, T[i])], 0.0, STAY_WEIGHT * 0.1)
        end

        # User relations.
        for rel in relations
            (terms, const_part) = _relation_affine(rel, n, bw, bh, L, T, W, H)
            rhs = rel.constant - const_part
            if rel.strength === :required
                f = MOI.ScalarAffineFunction(terms, 0.0)
                if rel.op === :(==)
                    MOI.add_constraint(model, f, MOI.EqualTo(rhs))
                elseif rel.op === :(<=)
                    MOI.add_constraint(model, f, MOI.LessThan(rhs))
                elseif rel.op === :(>=)
                    MOI.add_constraint(model, f, MOI.GreaterThan(rhs))
                else
                    error("ConstraintSolver: unknown op $(rel.op)")
                end
            else
                weight = _strength_weight(rel.strength)
                if rel.op === :(==)
                    soft_equal!(terms, rhs, weight)
                elseif rel.op === :(<=)
                    # Σ a·v − sp ≤ rhs ; minimize sp (overshoot above rhs).
                    sp = MOI.add_variable(model)
                    MOI.add_constraint(model, sp, MOI.GreaterThan(0.0))
                    f = MOI.ScalarAffineFunction(
                        vcat(terms, MOI.ScalarAffineTerm(-1.0, sp)), 0.0)
                    MOI.add_constraint(model, f, MOI.LessThan(rhs))
                    push!(objective, MOI.ScalarAffineTerm(weight, sp))
                elseif rel.op === :(>=)
                    # Σ a·v + sn ≥ rhs ; minimize sn (shortfall below rhs).
                    sn = MOI.add_variable(model)
                    MOI.add_constraint(model, sn, MOI.GreaterThan(0.0))
                    f = MOI.ScalarAffineFunction(
                        vcat(terms, MOI.ScalarAffineTerm(1.0, sn)), 0.0)
                    MOI.add_constraint(model, f, MOI.GreaterThan(rhs))
                    push!(objective, MOI.ScalarAffineTerm(weight, sn))
                else
                    error("ConstraintSolver: unknown op $(rel.op)")
                end
            end
        end

        # Optional hard containment within the parent box.
        if contain
            for i in 1:n
                MOI.add_constraint(model, L[i], MOI.GreaterThan(0.0))
                MOI.add_constraint(model, T[i], MOI.GreaterThan(0.0))
                MOI.add_constraint(model,
                    MOI.ScalarAffineFunction(
                        [MOI.ScalarAffineTerm(1.0, L[i]), MOI.ScalarAffineTerm(1.0, W[i])], 0.0),
                    MOI.LessThan(bw))
                MOI.add_constraint(model,
                    MOI.ScalarAffineFunction(
                        [MOI.ScalarAffineTerm(1.0, T[i]), MOI.ScalarAffineTerm(1.0, H[i])], 0.0),
                    MOI.LessThan(bh))
            end
        end

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
                MOI.ScalarAffineFunction(objective, 0.0))

        MOI.optimize!(model)

        status = MOI.get(model, MOI.TerminationStatus())
        if status != MOI.OPTIMAL
            @warn "ConstraintSolver: solve did not reach OPTIMAL ($(status)); using intrinsic fallback"
            return fallback()
        end
        if MOI.get(model, MOI.PrimalStatus()) != MOI.FEASIBLE_POINT
            @warn "ConstraintSolver: no feasible primal; using intrinsic fallback"
            return fallback()
        end

        lv = MOI.get(model, MOI.VariablePrimal(), L)
        tv = MOI.get(model, MOI.VariablePrimal(), T)
        wv = MOI.get(model, MOI.VariablePrimal(), W)
        hv = MOI.get(model, MOI.VariablePrimal(), H)

        return NTuple{4,Int}[(round(Int, lv[i]), round(Int, tv[i]),
                              round(Int, max(0.0, wv[i])), round(Int, max(0.0, hv[i])))
                             for i in 1:n]
    catch err
        @warn "ConstraintSolver: solve threw ($(err)); using intrinsic fallback"
        return fallback()
    end
end

end # module
