"""
    ProjecturedProjection

The domain-free projection *algebra*: the generic and higher-order
combinators, the compound aggregates, `Searching`, `Copying`, the two
collection-shaped projections, and the IoMap-typed reader defaults. None of
these owns a document; each operates over any input by structure.

The submodules below are aliased so this package's source files keep their
relative `..XxxModule` references.
"""
module ProjecturedProjection

using ProjecturedCollection
using ProjecturedKernel
using ProjecturedPrimitive

const IoMapModule = ProjecturedKernel.IoMapModule
const IntentModule = ProjecturedKernel.IntentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const CellModule = ProjecturedKernel.CellModule
const EventModule = ProjecturedKernel.EventModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const OperationModule = ProjecturedKernel.OperationModule
const SelectionModule = ProjecturedKernel.SelectionModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule

include("../../../source/projection/generic/Identity.jl")

end # module ProjecturedProjection
