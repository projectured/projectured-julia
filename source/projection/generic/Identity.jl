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

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
import ..IntentModule: CollectIntents
import ..DocumentModule: Document
import ..GestureBindingModule: read_gesture
export IdentityProjection
import ..ProjectionApiModule: print_document, print_child, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: ChildrenIoMap, reconcile_child_iomaps
import ..CollectionModule: CellVector, ComputedCellVector
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, extend_reference, get_reference_node_type
import ..ReferenceModule: var"@reference_case"
import ..PrinterContextModule: make_child_context
export ReversingProjection
export ConstantProjection
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection,
       print_document_pure
import ..IntentModule: Intent, CollectIntents, CollectedIntentsOperation,
                       merge_collected_intents
import ..GestureBindingModule: GestureBinding
import ..IoMapModule: IoMap, reconcile_child_iomap, var"@iomap"
import ..CellModule: Cell, ComputedCell, AbstractCell, unwrap_cell
export ChainingProjection, ChainingIoMap
import ..IntentModule: Intent
export TypeDispatchingProjection
import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection,
       print_document_pure
export RecursiveProjection
import ..CellModule: Cell, ComputedCell
import ..IoMapModule: IoMap, var"@iomap", reconcile_child_iomap
export SwitchingProjection, SwitchingIoMap
export PredicateDispatchingProjection
import ..IoMapModule: IoMap, var"@iomap"
export ReferenceDispatchingProjection, ReferenceDispatchingIoMap
import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
export NestingProjection, NestingIoMap
import ..EventModule: WindowInput
export WindowInputUnwrappingProjection, WindowInputUnwrappingIoMap
import ..ProjectionModule: var"@projection"
import ..OperationModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation
import ..ReferenceModule: Reference, ConcreteReference, EmptyReference, evaluate_reference, extend_reference, strip_reference_types
import ..EventPatternModule: KeyDownPattern
import ..ProjectionGestureBindingsModule: get_projection_gesture_bindings, read_projection_gesture
export FocusingProjection, ReplaceFocusPartOperation
import ..IoMapModule: IoMap, var"@iomap", reconcile_child_iomaps
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, RangeReferenceStep, extend_reference, get_reference_node_type
export SortingProjection, SortingIoMap
import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward, Projection
export FilteringProjection, FilteringIoMap
import ..CellModule: Cell, ComputedCell, AbstractCell, set_cell_function!, unwrap_cell
import ..ReferenceModule: Reference, EmptyReference, ConcreteReference,
                          FieldReferenceStep, ElementReferenceStep, extend_reference, get_reference_head, get_reference_tail,
                          strip_reference_types
export SearchingProjection, SearchingIoMap
import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..CellModule: Cell, ComputedCell, set_cell_function!, set_cell_value!
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep,
                          ElementReferenceStep, is_element_reference_step, get_reference_head, get_reference_tail
import ..PrinterContextModule: PrinterContext, make_child_context
import ..CollectionModule: CellVector, ComputedCellVector, ListNode
import ..OperationModule: operation_reference, retarget_operation,
                          operation_travels_unchanged, ReplaceReferencedValueOperation
import ..SelectionModule: get_stored_selection
export CopyingProjection, CopyingIoMap, make_copying_field_iomap, make_copying_element_iomap
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..ReferenceModule: Reference
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
