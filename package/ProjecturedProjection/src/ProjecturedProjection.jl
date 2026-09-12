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

include("../../../source/projection/generic/Identity.jl")
include("../../../source/projection/generic/Reversing.jl")
include("../../../source/projection/generic/Constant.jl")
include("../../../source/projection/higherorder/Chaining.jl")
include("../../../source/projection/higherorder/TypeDispatching.jl")
include("../../../source/projection/higherorder/Recursive.jl")
include("../../../source/projection/higherorder/Switching.jl")
include("../../../source/projection/higherorder/PredicateDispatching.jl")
include("../../../source/projection/higherorder/ReferenceDispatching.jl")
include("../../../source/projection/higherorder/Nesting.jl")
include("../../../source/projection/higherorder/WindowInputUnwrapping.jl")
include("../../../source/projection/generic/Focusing.jl")
include("../../../source/projection/generic/Sorting.jl")
include("../../../source/projection/generic/Filtering.jl")
include("../../../source/projection/generic/Searching.jl")
include("../../../source/projection/generic/Copying.jl")
include("../../../source/projection/ReaderDefaults.jl")
include("../../../source/projection/compound/HigherOrderCompound.jl")
include("../../../source/projection/compound/GenericCompound.jl")

end # module ProjecturedProjection
