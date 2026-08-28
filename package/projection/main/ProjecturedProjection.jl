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

const ProjectionApiModule = ProjecturedKernel.ProjectionApiModule
const IoMapModule = ProjecturedKernel.IoMapModule
const IntentModule = ProjecturedKernel.IntentModule
const DocumentModule = ProjecturedKernel.DocumentModule
const GestureBindingModule = ProjecturedKernel.GestureBindingModule
const CollectionModule = ProjecturedCollection.CollectionModule
const ReferenceModule = ProjecturedKernel.ReferenceModule
const PrinterContextModule = ProjecturedKernel.PrinterContextModule
const CellModule = ProjecturedKernel.CellModule
const EventModule = ProjecturedKernel.EventModule
const ProjectionModule = ProjecturedKernel.ProjectionModule
const OperationModule = ProjecturedKernel.OperationModule
const SelectionModule = ProjecturedKernel.SelectionModule
const EventPatternModule = ProjecturedKernel.EventPatternModule
const ProjectionGestureBindingsModule = ProjecturedKernel.ProjectionGestureBindingsModule
const PrimitiveModule = ProjecturedPrimitive.PrimitiveModule
const ReferenceCaseModule = ProjecturedKernel.ReferenceModule

include("generic/Identity.jl")
include("generic/Reversing.jl")
include("generic/Constant.jl")
include("higherorder/Chaining.jl")
include("higherorder/TypeDispatching.jl")
include("higherorder/Recursive.jl")
include("higherorder/Switching.jl")
include("higherorder/PredicateDispatching.jl")
include("higherorder/ReferenceDispatching.jl")
include("higherorder/Nesting.jl")
include("higherorder/WindowInputUnwrapping.jl")
include("generic/Focusing.jl")
include("Sorting.jl")
include("Filtering.jl")
include("Searching.jl")
include("Copying.jl")
include("ReaderDefaults.jl")
include("compound/HigherOrderCompound.jl")
include("compound/GenericCompound.jl")

end # module ProjecturedProjection
