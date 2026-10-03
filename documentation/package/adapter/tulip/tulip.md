# Tulip constraint solver

> **Kind:** design · **Status:** current · **Stands on:** [layout.md](../../platform/layout/layout.md), [package-rules.md](../../../rule/package-rules.md)

`ProjecturedTulip` is an opt-in package that solves the relations of a `ConstraintLayout`. It adds one method to the solver seam of the layout slice, and it brings the linear programming packages `Tulip` and `MathOptInterface`. This document says how a layout problem becomes a linear program.

## How it works

`TulipConstraintSolver(; optimizer = Tulip.Optimizer, contain = false)` implements `solve_constraint_layout(solver, n, intrinsic_w, intrinsic_h, relations, bounding_w, bounding_h)`. It returns the left, top, width and height of each child. The layout and its projection are in the layout slice; see [layout.md](../../platform/layout/layout.md).

The solver builds a linear program through MathOptInterface:

- Each child has four variables: left, top, width and height. The derived edges (`:right`, `:bottom`, `:centerx`, `:centery`) become sums of these.
- A relation with the strength `:required` becomes a row of the program.
- A relation with the strength `:strong`, `:medium` or `:weak` gets slack variables and a penalty in the objective: 10⁶, 10⁴ and 10² for each unit of slack. This is goal programming: one solve that approximates the priorities of Cassowary.
- The size of a child and its origin enter as weaker goals with weight 1, so a child that the relations do not fix keeps its own size. The goal for the origin costs more to the left than to the right, so a chain of equalities that is not fixed comes out at the leftmost place.
- With `contain = true`, every child must stay inside the bounding box.

If the solve is not optimal, has no feasible point, or raises an error, the solver writes a warning and returns the fallback: every child at the origin with its own size.

## How it fits

The code is the slice `TulipModule`, in `source/adapter/tulip/`: `TulipModule.jl` holds its imports and its exports, and `ProjecturedTulip` includes that file and exports the same names.

`ProjecturedTulip` depends on `ProjecturedPlatform`'s layout slice, and on `Tulip` and `MathOptInterface`. It declares the triggers `Projectured` and `Tulip` with the default `auto`, so AutoIntegration loads it when both are loaded; see [autointegration.md](../../autointegration/autointegration.md). It re-exports the essential names of `ProjecturedPlatform.EssentialsModule`; see [essentials.md](../../platform/essentials/essentials.md). No package depends on it. It registers nothing, and loading it changes no default: a caller passes the solver to the projection. This is different from `ProjecturedAdaptagrams`, which registers itself as the engine of `DeferredLayout` when it loads; see [graph.md](../../domain/graph/graph.md).

## Design decisions

- **A linear program, not a port of Cassowary.** No maintained Julia binding of Cassowary or kiwi exists. Tulip is pure Julia, so it adds no native library, and MathOptInterface keeps the cost of each small solve low. See [plan/done/constraint-layout.md](../../../../plan/done/constraint-layout.md).
- **One weighted solve, not a solve for each strength.** The weights are far apart, and the plan found this enough for layout.
- **The optimizer is a field.** `optimizer = HiGHS.Optimizer` changes the solver in one line; the package does not depend on HiGHS.
- **The solver is opt-in.** The layout slice keeps no dependency on a solver.

## Usage

```julia
using Projectured, ProjecturedPlatform, ProjecturedTulip
projection = ConstraintLayoutToGraphicsCanvas(solver = TulipConstraintSolver())
```

- Example: `make_constraint_layout_tulip_projection_example()` in `example/adapter/tulip/`.
- Test: `test_tulip()`, which runs `test_constraint_solver()`.

## Limits

- The priorities are weights, not a strict order. Many weak relations can outweigh one strong relation.
- The solve runs again in full on each change. An incremental solver, for a live drag, is a future extension of the plan.
- A failed solve gives the fallback layout with only a warning in the log.
