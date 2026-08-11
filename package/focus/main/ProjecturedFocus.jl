"""
    ProjecturedFocus

The generic focus walk and its open trait `is_focusable_document`: which
leaf a Tab press lands on. The walk names no widget type.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedFocus

using ProjecturedCollection
using ProjecturedKernel

const CellModule = ProjecturedKernel.CellModule
const DocumentModule = ProjecturedKernel.DocumentModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule

include("Focus.jl")

end # module ProjecturedFocus
