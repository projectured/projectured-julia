"""
    ProjectionAlgebraModule

The domain-free projection algebra: the generic and higher-order combinators,
the compound aggregates, `Searching`, `Copying`, the two collection-shaped
projections, and the IoMap-typed reader defaults. None of these owns a
document; each operates over any input by structure.

The module takes a name of its own rather than the slice's, because the
kernel's projection layer already declares `ProjectionModule`. See
`plan/pending/one-module-per-slice.md`.

This file holds `IdentityProjection`: a projection that returns the input as
the output without copying, which a predicate-dispatching projection uses as
its pass-through branch.
"""
module ProjectionAlgebraModule

import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward, print_document_pure
using ..IoMapModule
using ..IntentModule
using ..DocumentModule
using ..GestureBindingModule
export IdentityProjection
using ..CollectionModule
using ..ReferenceModule
using ..PrinterContextModule
export ReversingProjection
export ConstantProjection
using ..CellModule
export ChainingProjection, ChainingIoMap
export TypeDispatchingProjection
export RecursiveProjection
export SwitchingProjection, SwitchingIoMap
export PredicateDispatchingProjection
export ReferenceDispatchingProjection, ReferenceDispatchingIoMap
export NestingProjection, NestingIoMap
using ..EventModule
export WindowInputUnwrappingProjection, WindowInputUnwrappingIoMap
using ..ProjectionModule
using ..OperationModule
import ..OperationModule: evaluate_operation
using ..EventPatternModule
using ..ProjectionGestureBindingsModule
import ..ProjectionGestureBindingsModule: get_projection_gesture_bindings
export FocusingProjection, ReplaceFocusPartOperation
export SortingProjection, SortingIoMap
export FilteringProjection, FilteringIoMap
export SearchingProjection, SearchingIoMap
using ..SelectionModule
export CopyingProjection, CopyingIoMap, make_copying_field_iomap, make_copying_element_iomap
using ..PrimitiveModule
export ApplyAtProjection
export SortingAtProjection



struct IdentityProjection <: Projection end

function print_document(projection::IdentityProjection, recursion, input, ctx)
    SimpleIoMap(projection, input, input)
end

function read_intent(::IdentityProjection, iomap, operation)
    # Asked what is available, answer for the input document: an identity
    # projection introduces nothing of its own, so its input's table is the whole of
    # what it offers. Without this the payload would pass through unchanged like
    # everything else, and a document behind an identity would go unlisted.
    if operation isa CollectIntents
        input = iomap.input
        return input isa Document ? read_gesture(input, operation) : nothing
    end
    operation
end

function map_reference_forward(::IdentityProjection, iomap, reference)
    reference
end

function map_reference_backward(::IdentityProjection, iomap, reference)
    reference
end


include("Reversing.jl")
include("Constant.jl")
include("../higherorder/Chaining.jl")
include("../higherorder/TypeDispatching.jl")
include("../higherorder/Recursive.jl")
include("../higherorder/Switching.jl")
include("../higherorder/PredicateDispatching.jl")
include("../higherorder/ReferenceDispatching.jl")
include("../higherorder/Nesting.jl")
include("../higherorder/WindowInputUnwrapping.jl")
include("Focusing.jl")
include("Sorting.jl")
include("Filtering.jl")
include("Searching.jl")
include("Copying.jl")
include("../ReaderDefaults.jl")
include("../compound/HigherOrderCompound.jl")
include("../compound/GenericCompound.jl")

end # module
