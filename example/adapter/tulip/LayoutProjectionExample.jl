# LP-solved constraint-layout projection (Tulip via MathOptInterface). Split out
# of ProjecturedExample so the base example package carries no dependency on
# Tulip / MathOptInterface; this reuses the base wiring
# (`make_constraint_layout_projection_example`) with the real solver swapped in
# for the dependency-free `FallbackConstraintSolver`. Building the projection is
# cheap; the LP solve happens lazily when the projection is printed.

function make_constraint_layout_tulip_projection_example(; measure=FontFileMeasure())
    make_constraint_layout_projection_example(; measure=measure,
                                              solver=TulipConstraintSolver())
end
