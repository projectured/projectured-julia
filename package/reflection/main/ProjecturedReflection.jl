"""
    ProjecturedReflection

A bounded shadow of a large or live Julia object: the `UnsyncedDocument`
marker, the sync policies that implement the kernel's `sync_document!` seam,
and the reflected node tree.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedReflection

using ProjecturedCollection
using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const CollectionModule = ProjecturedCollection.CollectionModule
const OperationModule = ProjecturedKernel.OperationModule

include("BoundedSync.jl")
include("DocumentReflection.jl")

end # module ProjecturedReflection
