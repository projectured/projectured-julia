# ── Tulip opt-in example registry ────────────────────────────────────────────
#
# Projection builder in projection/Layout.jl; the engine-free constraint-layout
# document (make_constraint_layout_document_example) from ProjecturedExample.

# LP-solved ConstraintLayout (TulipConstraintSolver).
const constraint_layout_tulip_example = Example("constraint_layout_tulip", make_constraint_layout_document_example, make_constraint_layout_tulip_projection_example)

# The Tulip tier's example slice.
const tulip_examples = Example[
    constraint_layout_tulip_example,
]
