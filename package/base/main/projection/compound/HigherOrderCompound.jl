module HigherOrderCompoundModule

import ..RecursiveProjectionModule: RecursiveProjection
import ..ReferenceDispatchingProjectionModule: ReferenceDispatchingProjection
import ..CopyingProjectionModule: CopyingProjection
import ..IdentityProjectionModule: IdentityProjection
import ..NestingProjectionModule: NestingProjection
import ..ReferenceModule: Reference
import ..ReferenceCaseModule: var"@reference_case"

export ApplyAtProjection

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
        _                    => IdentityProjection()
    end))
end

end
