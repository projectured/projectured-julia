"""
    ProjecturedCollection

The reactive containers every domain reuses: an indexed growable vector, a
dense matrix, a table of rows, and a doubly-linked list node. Each slot is a
reactive `Cell`, so a change to one element invalidates only that slot's
dependents.

The package holds documents alone. The collection-shaped projections
(`SortingProjection`, `FilteringProjection`) live in `ProjecturedProjection`,
which depends on this package.

Kernel submodules are aliased below so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedCollection

using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const OperationModule = ProjecturedKernel.OperationModule
const ChildrenContainerModule = ProjecturedKernel.ChildrenContainerModule

# The four collection shapes. CollectionModule includes its four fragments.
include("Collection.jl")

end # module ProjecturedCollection
