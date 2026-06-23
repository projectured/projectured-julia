module GenericCompoundModule

import ..HigherOrderCompoundModule: ApplyAtProjection
import ..SortingProjectionModule: SortingProjection
import ..ReferenceModule: ReferencePath

export SortingAtProjection

"""
    SortingAtProjection(reference, by)

Sort a sequence at the given `reference` path using the `by` key function.
Shorthand for `ApplyAtProjection(reference, SortingProjection(; by))`.
"""
SortingAtProjection(reference::ReferencePath, by) =
    ApplyAtProjection(reference, SortingProjection(; by))

end