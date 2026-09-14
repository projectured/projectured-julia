"""
    ProjectionAlgebraModule

The domain-free projection algebra: the generic and higher-order combinators,
the compound aggregates, `Searching`, `Copying`, the two collection-shaped
projections, and the IoMap-typed reader defaults. None of these owns a
document; each operates over any input by structure.

The module takes a name of its own rather than the slice's, because the
kernel's projection layer already declares `ProjectionModule`.

The fragments below hold `IdentityProjection`: a projection that returns the
input as the output without copying, which a predicate-dispatching projection
uses as
its pass-through branch.
"""
module ProjectionAlgebraModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..EventPatternModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule

# Imported to extend: this module adds a method to each of these.
import ..OperationModule: evaluate_operation
import ..ProjectionModule: get_projection_gesture_bindings
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward, print_document_pure

export IdentityProjection
export ReversingProjection
export ConstantProjection
export ChainingProjection, ChainingIoMap
export TypeDispatchingProjection
export RecursiveProjection
export SwitchingProjection, SwitchingIoMap
export PredicateDispatchingProjection
export ReferenceDispatchingProjection, ReferenceDispatchingIoMap
export NestingProjection, NestingIoMap
export WindowInputUnwrappingProjection, WindowInputUnwrappingIoMap
export FocusingProjection, ReplaceFocusPartOperation
export SortingProjection, SortingIoMap
export FilteringProjection, FilteringIoMap
export SearchingProjection, SearchingIoMap
export CopyingProjection, CopyingIoMap, make_copying_field_iomap, make_copying_element_iomap
export ApplyAtProjection
export SortingAtProjection


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
include("generic/Sorting.jl")
include("generic/Filtering.jl")
include("generic/Searching.jl")
include("generic/Copying.jl")
include("ReaderDefaults.jl")
include("compound/HigherOrderCompound.jl")
include("compound/GenericCompound.jl")

end # module
