function test_constraint_solver()

# Drives the solvers directly — no cells, no projection — exactly like
# LayoutAllocatorTest exercises `allocate_axis`. The LP cases use the opt-in
# `TulipConstraintSolver` (from ProjecturedTulip); the fallback case uses the
# core `FallbackConstraintSolver`. Interior-point solutions round to the integer
# grid, so equalities land exactly; computed extents are checked with a ±1 px
# tolerance to absorb any residual.

solver = TulipConstraintSolver()

@testset "FallbackConstraintSolver — origin stack" begin

# The dependency-free fallback ignores relations and stacks at the origin.
rects = solve_constraint_layout(FallbackConstraintSolver(), 2, [100, 50], [30, 40],
    [SolverRelation([(SolverAnchor(2, :left), 1.0), (SolverAnchor(1, :right), -1.0)],
                    :(==), 8.0, :required)],
    0, 0)
@test rects == [(0, 0, 100, 30), (0, 0, 50, 40)]

end # @testset

@testset "ConstraintSolver — equality pinning" begin

# b.left == a.right + 8, with a stayed at the origin (left=0, width=100).
rects = solve_constraint_layout(solver, 2, [100, 50], [30, 30],
    [SolverRelation([(SolverAnchor(2, :left), 1.0), (SolverAnchor(1, :right), -1.0)],
                    :(==), 8.0, :required)],
    0, 0)
@test length(rects) == 2
@test rects[1][1] == 0                 # a left stays at 0
@test abs(rects[2][1] - 108) <= 1      # b.left = a.right(100) + 8

end # @testset

@testset "ConstraintSolver — inequality min-size" begin

# width >= 120 must win over the weak intrinsic stay (80).
rects = solve_constraint_layout(solver, 1, [80], [20],
    [SolverRelation([(SolverAnchor(1, :width), 1.0)], :(>=), 120.0, :required)],
    0, 0)
@test abs(rects[1][3] - 120) <= 1

# With a competing soft pull toward the intrinsic, the hard min still wins.
rects2 = solve_constraint_layout(solver, 1, [80], [20],
    [SolverRelation([(SolverAnchor(1, :width), 1.0)], :(>=), 120.0, :required),
     SolverRelation([(SolverAnchor(1, :width), 1.0)], :(==), 80.0, :strong)],
    0, 0)
@test abs(rects2[1][3] - 120) <= 1

end # @testset

@testset "ConstraintSolver — fill remaining" begin

# Sidebar fixed at the left; main fills to the parent's right edge.
# bounding_w = 400, sidebar width = 100, gap = 8 ⇒ main width = 400 - 108 = 292.
rects = solve_constraint_layout(solver, 2, [100, 60], [200, 200],
    [SolverRelation([(SolverAnchor(1, :left), 1.0), (SolverAnchor(0, :left), -1.0)],
                    :(==), 0.0, :required),                      # sidebar.left == parent.left
     SolverRelation([(SolverAnchor(2, :left), 1.0), (SolverAnchor(1, :right), -1.0)],
                    :(==), 8.0, :required),                      # main.left == sidebar.right + 8
     SolverRelation([(SolverAnchor(2, :right), 1.0), (SolverAnchor(0, :right), -1.0)],
                    :(==), 0.0, :required)],                     # main.right == parent.right
    400, 400)
@test rects[1][1] == 0
@test abs(rects[2][1] - 108) <= 1
@test abs(rects[2][3] - 292) <= 1

end # @testset

@testset "ConstraintSolver — soft centering" begin

# Weak centering is satisfied when nothing else constrains x.
# bounding_w = 400, width = 100 ⇒ centerx 200 ⇒ left 150.
rects = solve_constraint_layout(solver, 1, [100], [40],
    [SolverRelation([(SolverAnchor(1, :centerx), 1.0), (SolverAnchor(0, :centerx), -1.0)],
                    :(==), 0.0, :weak)],
    400, 400)
@test abs(rects[1][1] - 150) <= 1

# A hard pin to the left edge overrides the weak centering.
rects2 = solve_constraint_layout(solver, 1, [100], [40],
    [SolverRelation([(SolverAnchor(1, :centerx), 1.0), (SolverAnchor(0, :centerx), -1.0)],
                    :(==), 0.0, :weak),
     SolverRelation([(SolverAnchor(1, :left), 1.0)], :(==), 0.0, :required)],
    400, 400)
@test rects2[1][1] == 0

end # @testset

@testset "ConstraintSolver — infeasible falls back, no throw" begin

# width == 100 and width == 200, both required ⇒ infeasible.
rects = solve_constraint_layout(solver, 1, [50], [20],
    [SolverRelation([(SolverAnchor(1, :width), 1.0)], :(==), 100.0, :required),
     SolverRelation([(SolverAnchor(1, :width), 1.0)], :(==), 200.0, :required)],
    0, 0)
@test length(rects) == 1
@test rects[1] == (0, 0, 50, 20)       # intrinsic fallback

end # @testset

@testset "ConstraintSolver — empty" begin

@test solve_constraint_layout(solver, 0, Int[], Int[], SolverRelation[], 0, 0) == NTuple{4,Int}[]

end # @testset

end # test_constraint_solver
