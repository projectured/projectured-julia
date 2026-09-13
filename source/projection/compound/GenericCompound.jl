# ──────────────────────────────────────────────────────────────────────────
# Folded in from compound/GenericCompound.jl.
"""
    SortingAtProjection(reference, by)

Sort a sequence at the given `reference` path using the `by` key function.
Shorthand for `ApplyAtProjection(reference, SortingProjection(; by))`.
"""
SortingAtProjection(reference::Reference, by) =
    ApplyAtProjection(reference, SortingProjection(; by))
