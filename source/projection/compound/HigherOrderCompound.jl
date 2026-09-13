# ──────────────────────────────────────────────────────────────────────────
# Folded in from compound/HigherOrderCompound.jl.
"""
    ApplyAtProjection(reference, projection)

Build a projection that applies `projection` at the given `reference` path
and preserves everything else.  The structural spine from root to the
target is copied; siblings and children below are preserved.

# Example

    ApplyAtProjection(@reference(entries), SortingProjection(by = x -> x.key))
"""
function ApplyAtProjection(reference::Reference, projection)
    RecursiveProjection(ReferenceDispatchingProjection(ref -> @reference_case ref begin
        above(^(reference)) => CopyingProjection()
        ^(reference)         => NestingProjection(
            projection;
            recursion=IdentityProjection(),
        )
        __                   => IdentityProjection()
    end))
end
